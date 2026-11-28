import Foundation
import Testing
@testable import JimmyKit

struct VoiceEQTests {
    private let rate = 48_000.0

    /// Gain in dB the EQ applies to a steady sine at `frequency`, measured on the settled output.
    private func gainDB(at frequency: Double) -> Double {
        let eq = VoiceEQ(sampleRate: rate)
        var samples = LoudnessTestSignals.sine(amplitude: 0.1, frequency: frequency, seconds: 1)
        samples.withUnsafeMutableBufferPointer { pointer in
            eq.process(left: pointer.baseAddress!, right: nil, frameCount: pointer.count)
        }
        let settled = samples[(samples.count / 2)...]
        let peak = Double(LoudnessTestSignals.peak(settled))
        return 20 * log10(peak / 0.1)
    }

    @Test func removesRumble() {
        #expect(gainDB(at: 30) < -15)
        #expect(abs(gainDB(at: 80) - -3) < 0.5)
    }

    @Test func leavesTheLowMidsAlone() {
        #expect(abs(gainDB(at: 200)) < 0.3)
        #expect(abs(gainDB(at: 1_000)) < 0.7)
    }

    @Test func liftsThePresenceBand() {
        #expect(abs(gainDB(at: 3_000) - 2.5) < 0.3)
        #expect(gainDB(at: 2_000) > 1)
        #expect(gainDB(at: 5_000) > 0.7)
    }

    @Test func leavesTheTopEndAlone() {
        #expect(abs(gainDB(at: 10_000)) < 0.6)
    }

    @Test func stereoChannelsAreFilteredIndependently() {
        let eq = VoiceEQ(sampleRate: rate)
        var left = LoudnessTestSignals.sine(amplitude: 0.1, frequency: 3_000, seconds: 0.5)
        var right = [Float](repeating: 0, count: left.count)
        let count = left.count
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                eq.process(left: l.baseAddress!, right: r.baseAddress!, frameCount: count)
            }
        }
        #expect(LoudnessTestSignals.peak(right[...]) == 0)
        #expect(LoudnessTestSignals.peak(left[(count / 2)...]) > 0.1)
    }
}
