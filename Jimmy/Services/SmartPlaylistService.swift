import Foundation
import GRDB

/// Maps each SmartPlaylistType to a GRDB query returning matching episodes
final class SmartPlaylistService {
    static let shared = SmartPlaylistService()
    private init() {}

    func fetchEpisodes(for playlist: SmartPlaylistType, limit: Int = 50) async throws -> [EpisodeWithPlaybackState] {
        try await DatabaseManager.shared.readAsync { db in
            let sql: String
            switch playlist {
            case .recentlyAdded:
                sql = """
                    SELECT e.*, ps.position, ps.finished, ps.queuePosition, ps.updatedAt AS psUpdatedAt
                    FROM episodes e
                    LEFT JOIN playback_state ps ON e.id = ps.episodeID
                    ORDER BY e.publishedDate DESC
                    LIMIT \(limit)
                """
            case .inProgress:
                sql = """
                    SELECT e.*, ps.position, ps.finished, ps.queuePosition, ps.updatedAt AS psUpdatedAt
                    FROM episodes e
                    JOIN playback_state ps ON e.id = ps.episodeID
                    WHERE ps.position > 0 AND ps.finished = 0
                    ORDER BY ps.updatedAt DESC
                    LIMIT \(limit)
                """
            case .downloaded:
                sql = """
                    SELECT e.*, ps.position, ps.finished, ps.queuePosition, ps.updatedAt AS psUpdatedAt
                    FROM episodes e
                    LEFT JOIN playback_state ps ON e.id = ps.episodeID
                    WHERE e.localFileURL IS NOT NULL AND e.localFileURL != ''
                    ORDER BY e.publishedDate DESC
                    LIMIT \(limit)
                """
            case .unplayed:
                sql = """
                    SELECT e.*, ps.position, ps.finished, ps.queuePosition, ps.updatedAt AS psUpdatedAt
                    FROM episodes e
                    LEFT JOIN playback_state ps ON e.id = ps.episodeID
                    WHERE e.played = 0 AND (ps.finished IS NULL OR ps.finished = 0)
                    ORDER BY e.publishedDate DESC
                    LIMIT \(limit)
                """
            case .starred:
                sql = """
                    SELECT e.*, ps.position, ps.finished, ps.queuePosition, ps.updatedAt AS psUpdatedAt
                    FROM episodes e
                    LEFT JOIN playback_state ps ON e.id = ps.episodeID
                    WHERE e.starred = 1
                    ORDER BY e.publishedDate DESC
                    LIMIT \(limit)
                """
            }

            let rows = try Row.fetchAll(db, sql: sql)
            return rows.compactMap { row in
                guard let episode = try? Episode(row: row) else { return nil }
                let playbackState = PlaybackState(
                    episodeID: episode.id,
                    position: row["position"] ?? 0.0,
                    finished: row["finished"] ?? false,
                    queuePosition: row["queuePosition"],
                    updatedAt: row["psUpdatedAt"] ?? Date()
                )
                return EpisodeWithPlaybackState(episode: episode, playbackState: playbackState)
            }
        }
    }

    func episodeCount(for playlist: SmartPlaylistType) async throws -> Int {
        try await DatabaseManager.shared.readAsync { db in
            let sql: String
            switch playlist {
            case .recentlyAdded:
                sql = "SELECT COUNT(*) FROM episodes"
            case .inProgress:
                sql = "SELECT COUNT(*) FROM playback_state WHERE position > 0 AND finished = 0"
            case .downloaded:
                sql = "SELECT COUNT(*) FROM episodes WHERE localFileURL IS NOT NULL AND localFileURL != ''"
            case .unplayed:
                sql = "SELECT COUNT(*) FROM episodes e LEFT JOIN playback_state ps ON e.id = ps.episodeID WHERE e.played = 0 AND (ps.finished IS NULL OR ps.finished = 0)"
            case .starred:
                sql = "SELECT COUNT(*) FROM episodes WHERE starred = 1"
            }
            return try Int.fetchOne(db, sql: sql) ?? 0
        }
    }
}
