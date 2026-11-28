import Foundation
import Testing
@testable import JimmyKit

struct SilenceDetectorTests {
    private let rate = 48_000.0

    private func tone(_ seconds: Double) -> [Float] {
        LoudnessTestSignals.sine(amplitude: 0.3, frequency: 300, seconds: seconds)
    }

    private func quiet(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    private func detect(_ samples: [Float]) -> [SilenceRange] {
        var detector = SilenceDetector(sampleRate: rate)
        detector.process(samples)
        return detector.finish()
    }

    @Test func findsAPauseBetweenSpeechAndTrimsThePadding() throws {
        let ranges = detect(tone(2) + quiet(1) + tone(2))
        let range = try #require(ranges.first)
        #expect(ranges.count == 1)
        #expect(abs(range.start - 2.12) < 0.05)
        #expect(abs(range.end - 2.88) < 0.05)
    }

    @Test func ignoresPausesShorterThanTheMinimum() {
        #expect(detect(tone(2) + quiet(0.3) + tone(2)).isEmpty)
    }

    @Test func continuousToneHasNoSilence() {
        #expect(detect(tone(5)).isEmpty)
    }

    @Test func aTrailingPauseCounts() throws {
        let ranges = detect(tone(2) + quiet(1))
        let range = try #require(ranges.first)
        #expect(abs(range.end - 2.88) < 0.05)
    }

    @Test func neverCutsIntoTheTone() {
        let ranges = detect(tone(2) + quiet(1) + tone(2))
        for range in ranges {
            #expect(range.start >= 2.0)
            #expect(range.end <= 3.0)
        }
    }

    @Test func chunkSizeDoesNotChangeTheResult() {
        let samples = tone(2) + quiet(1) + tone(2) + quiet(0.8) + tone(1)
        let whole = detect(samples)
        var detector = SilenceDetector(sampleRate: rate)
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + 777)
            detector.process(Array(samples[start..<end]))
            start = end
        }
        #expect(detector.finish() == whole)
        #expect(whole.count == 2)
    }
}
