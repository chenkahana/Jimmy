import Foundation
import Testing
@testable import JimmyKit

struct StoreAudioAnalysisTests {
    private func makeStore() throws -> Store {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-analysis-\(UUID().uuidString).sqlite")
            .path
        return try Store(path: path)
    }

    @Test func missingAnalysisIsNil() async throws {
        let store = try makeStore()
        #expect(try await store.audioAnalysis(for: UUID()) == nil)
    }

    @Test func savedAnalysisRoundTrips() async throws {
        let store = try makeStore()
        let id = UUID()
        let analysis = AudioAnalysis(
            episodeID: id,
            integratedLUFS: -21.5,
            samplePeak: 0.8,
            silenceRanges: [SilenceRange(start: 1, end: 2), SilenceRange(start: 10.5, end: 11)],
            analyzedAt: Date(timeIntervalSince1970: 1_000)
        )
        try await store.saveAudioAnalysis(analysis)
        let loaded = try #require(try await store.audioAnalysis(for: id))
        #expect(loaded.episodeID == id)
        #expect(loaded.integratedLUFS == -21.5)
        #expect(loaded.samplePeak == 0.8)
        #expect(loaded.silenceRanges == analysis.silenceRanges)
        #expect(abs(loaded.skippableDuration - 1.5) < 0.0001)
    }

    @Test func savingAgainReplacesAndNilLoudnessIsKept() async throws {
        let store = try makeStore()
        let id = UUID()
        try await store.saveAudioAnalysis(AudioAnalysis(episodeID: id, integratedLUFS: -20, samplePeak: 0.5, silenceRanges: []))
        try await store.saveAudioAnalysis(AudioAnalysis(episodeID: id, integratedLUFS: nil, samplePeak: 0, silenceRanges: []))
        let loaded = try #require(try await store.audioAnalysis(for: id))
        #expect(loaded.integratedLUFS == nil)
    }

    @Test func deleteRemovesTheRow() async throws {
        let store = try makeStore()
        let id = UUID()
        try await store.saveAudioAnalysis(AudioAnalysis(episodeID: id, integratedLUFS: -20, samplePeak: 0.5, silenceRanges: []))
        try await store.deleteAudioAnalysis(for: id)
        #expect(try await store.audioAnalysis(for: id) == nil)
    }
}
