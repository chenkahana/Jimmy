import AVFoundation
import Testing
@testable import JimmyKit

struct PlaybackQualityTests {
    @Test func normalSpeedUsesTheCheapAlgorithm() {
        #expect(PlaybackQuality.pitchAlgorithm(rate: 1.0, cheapProcessing: false) == .timeDomain)
    }

    @Test func spedUpSpeechUsesSpectral() {
        #expect(PlaybackQuality.pitchAlgorithm(rate: 1.25, cheapProcessing: false) == .spectral)
        #expect(PlaybackQuality.pitchAlgorithm(rate: 2.0, cheapProcessing: false) == .spectral)
    }

    @Test func slowedSpeechUsesSpectral() {
        #expect(PlaybackQuality.pitchAlgorithm(rate: 0.8, cheapProcessing: false) == .spectral)
    }

    @Test func cheapProcessingAlwaysUsesTimeDomain() {
        #expect(PlaybackQuality.pitchAlgorithm(rate: 1.5, cheapProcessing: true) == .timeDomain)
    }
}
