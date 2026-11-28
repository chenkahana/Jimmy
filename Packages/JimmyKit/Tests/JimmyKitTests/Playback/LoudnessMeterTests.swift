import Foundation
import Testing
@testable import JimmyKit

struct LoudnessMeterTests {
    private let sampleRate = 48_000.0

    private func measure(_ channels: [[Float]], sampleRate: Double = 48_000) -> Double? {
        var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: channels.count)
        meter.process(channels: channels)
        return meter.integratedLUFS
    }

    @Test func monoSineMatchesTheReferenceLevel() throws {
        // BS.1770: a 997 Hz sine at -20 dBFS peak, mono, reads about -23 LUFS.
        let signal = LoudnessTestSignals.sine(amplitude: 0.1, seconds: 5)
        let lufs = try #require(measure([signal]))
        #expect(abs(lufs - -23.01) < 0.15)
    }

    @Test func theSameSignalOnTwoChannelsIsAboutThreeLULouder() throws {
        let signal = LoudnessTestSignals.sine(amplitude: 0.1, seconds: 5)
        let mono = try #require(measure([signal]))
        let stereo = try #require(measure([signal, signal]))
        #expect(abs((stereo - mono) - 3.01) < 0.05)
    }

    @Test func tenDecibelsOfGainIsTenLU() throws {
        let quiet = try #require(measure([LoudnessTestSignals.sine(amplitude: 0.05, seconds: 5)]))
        let louder = try #require(measure([LoudnessTestSignals.sine(amplitude: 0.05 * 3.1623, seconds: 5)]))
        #expect(abs((louder - quiet) - 10) < 0.05)
    }

    @Test func the44100SampleRateAgrees() throws {
        let signal = LoudnessTestSignals.sine(amplitude: 0.1, seconds: 5, sampleRate: 44_100)
        let lufs = try #require(measure([signal], sampleRate: 44_100))
        #expect(abs(lufs - -23.01) < 0.15)
    }

    @Test func silenceHasNoLoudness() {
        #expect(measure([[Float](repeating: 0, count: 48_000 * 3)]) == nil)
    }

    @Test func audioShorterThanOneBlockHasNoLoudness() {
        #expect(measure([LoudnessTestSignals.sine(amplitude: 0.1, seconds: 0.3)]) == nil)
    }

    @Test func chunkSizeDoesNotChangeTheResult() throws {
        let signal = LoudnessTestSignals.sine(amplitude: 0.1, seconds: 5)
        let whole = try #require(measure([signal]))
        var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: 1)
        var start = 0
        while start < signal.count {
            let end = min(signal.count, start + 1_237)
            meter.process(channels: [Array(signal[start..<end])])
            start = end
        }
        let chunked = try #require(meter.integratedLUFS)
        #expect(abs(whole - chunked) < 0.001)
    }

    @Test func gatingIgnoresQuietPassages() throws {
        // Three seconds of speech-level tone and three of near-silence: the silence must not drag
        // the integrated level down.
        let loud = LoudnessTestSignals.sine(amplitude: 0.1, seconds: 3)
        let hush = LoudnessTestSignals.sine(amplitude: 0.0001, seconds: 3)
        let lufs = try #require(measure([loud + hush]))
        #expect(abs(lufs - -23.01) < 0.5)
    }

    @Test func tracksTheSamplePeak() {
        var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: 1)
        meter.process(channels: [[0.1, -0.7, 0.3]])
        #expect(meter.samplePeak == 0.7)
    }
}
