import Foundation
import GRDB

/// Per-episode results of `AudioAnalyzer`. Additive: a missing row just means "not analyzed yet".
nonisolated extension Store {
    public func audioAnalysis(for episodeID: UUID) async throws -> AudioAnalysis? {
        try await pool.read { db in
            try AudioAnalysis.fetchOne(db, key: episodeID.uuidString)
        }
    }

    public func saveAudioAnalysis(_ analysis: AudioAnalysis) async throws {
        try await pool.write { db in try analysis.save(db) }
    }

    public func deleteAudioAnalysis(for episodeID: UUID) async throws {
        try await pool.write { db in
            _ = try AudioAnalysis.deleteOne(db, key: episodeID.uuidString)
        }
    }
}
