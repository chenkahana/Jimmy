import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct VolumeBoostSettingTests {
    @Test func playbackPassesTheSettingToTheEngine() {
        let engine = FakePlayerEngine()
        let playback = Playback(engine: engine, progressStore: FakeProgressStore(), queueSource: FakeQueueSource(), clock: FakeClock())
        playback.setVolumeBoost(.high)
        #expect(engine.volumeBoost == .high)
    }

    @Test func playbackPassesVoiceClarityToTheEngine() {
        let engine = FakePlayerEngine()
        let playback = Playback(engine: engine, progressStore: FakeProgressStore(), queueSource: FakeQueueSource(), clock: FakeClock())
        playback.setVoiceClarity(true)
        #expect(engine.voiceClarity == true)
    }

    @Test func onlyHighUsesTheCompressor() {
        #expect(VolumeBoost.high.usesCompressor)
        #expect(!VolumeBoost.normal.usesCompressor)
        #expect(!VolumeBoost.off.usesCompressor)
    }

    @Test func storedLevelRoundTripsAndFallsBackToTheDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "VolumeBoostSettingTests"))
        defaults.removePersistentDomain(forName: "VolumeBoostSettingTests")
        #expect(VolumeBoost.stored(in: defaults) == VolumeBoost.defaultLevel)
        defaults.set(VolumeBoost.normal.rawValue, forKey: VolumeBoost.defaultsKey)
        #expect(VolumeBoost.stored(in: defaults) == .normal)
        defaults.set("nonsense", forKey: VolumeBoost.defaultsKey)
        #expect(VolumeBoost.stored(in: defaults) == VolumeBoost.defaultLevel)
        defaults.removePersistentDomain(forName: "VolumeBoostSettingTests")
    }
}
