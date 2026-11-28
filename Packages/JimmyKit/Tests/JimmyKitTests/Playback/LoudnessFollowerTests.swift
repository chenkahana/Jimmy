import Foundation
import Testing
@testable import JimmyKit

struct LoudnessFollowerTests {
    private let sampleRate = 48_000.0

    private func feed(_ follower: LoudnessFollower, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { pointer in
            follower.process(left: pointer.baseAddress!, right: nil, frameCount: pointer.count)
        }
    }

    @Test func hasNoEstimateDuringWarmUp() {
        let follower = LoudnessFollower(sampleRate: sampleRate, channelCount: 1)
        feed(follower, LoudnessTestSignals.sine(amplitude: 0.1, seconds: 0.5))
        #expect(follower.estimatedLUFS == nil)
    }

    @Test func settlesNearTheMeasuredLoudness() throws {
        let follower = LoudnessFollower(sampleRate: sampleRate, channelCount: 1)
        feed(follower, LoudnessTestSignals.sine(amplitude: 0.05, seconds: 20))
        let estimate = try #require(follower.estimatedLUFS)
        // A 997 Hz sine at amplitude 0.05 (-26 dBFS peak) measures -29.0 LUFS mono.
        #expect(abs(estimate - -29.01) < 0.5)
    }

    @Test func silenceDoesNotPullTheEstimateDown() throws {
        let follower = LoudnessFollower(sampleRate: sampleRate, channelCount: 1)
        feed(follower, LoudnessTestSignals.sine(amplitude: 0.1, seconds: 10))
        let before = try #require(follower.estimatedLUFS)
        feed(follower, [Float](repeating: 0, count: 48_000 * 10))
        let after = try #require(follower.estimatedLUFS)
        // A moment of fade-out is still above the gate and nudges it; it must stay under 0.5 LU.
        #expect(abs(before - after) < 0.5)
    }

    @Test func stereoReadsThreeLUlouderThanMonoForTheSameSignal() throws {
        let signal = LoudnessTestSignals.sine(amplitude: 0.1, seconds: 15)
        let mono = LoudnessFollower(sampleRate: sampleRate, channelCount: 1)
        feed(mono, signal)
        let stereo = LoudnessFollower(sampleRate: sampleRate, channelCount: 2)
        signal.withUnsafeBufferPointer { pointer in
            stereo.process(left: pointer.baseAddress!, right: pointer.baseAddress!, frameCount: pointer.count)
        }
        let stereoEstimate = try #require(stereo.estimatedLUFS)
        let monoEstimate = try #require(mono.estimatedLUFS)
        let difference = stereoEstimate - monoEstimate
        #expect(abs(difference - 3.01) < 0.1)
    }
}
