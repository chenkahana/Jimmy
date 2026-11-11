import Foundation
import GRDB

/// Smart playlists: a fixed set of rows in `playlists` (seeded by `v25_seed_smart_playlists`),
/// each naming a `PlaylistRule` that selects episodes dynamically — no episode ever belongs to a
/// playlist row directly. Replaces `SmartPlaylistService`'s hand-rolled queries against the
/// legacy `episodes`/`playback_state` columns.
nonisolated extension Store {
    public func playlists() async throws -> [Playlist] {
        try await pool.read { db in try Playlist.order(Column("name")).fetchAll(db) }
    }

    /// `rule`'s matching episodes, newest/most-relevant first, joined with progress, queue
    /// membership, and download state like any other episode list.
    public func episodes(matching rule: PlaylistRule, limit: Int = 50) async throws -> [EpisodeListItem] {
        try await pool.read { db in
            let episodes = try Self.fetchEpisodes(matching: rule, limit: limit, db: db)
            return try Self.wrapAsListItems(episodes, db: db)
        }
    }

    public func episodeCount(matching rule: PlaylistRule) async throws -> Int {
        try await pool.read { db in
            let sql: String
            switch rule {
            case .recentlyAdded:
                sql = "SELECT COUNT(*) FROM episodes"
            case .inProgress:
                sql = "SELECT COUNT(*) FROM progress WHERE position > 0 AND isFinished = 0"
            case .downloaded:
                sql = "SELECT COUNT(*) FROM downloads WHERE state = ?"
            case .unplayed:
                sql = """
                    SELECT COUNT(*) FROM episodes e
                    LEFT JOIN progress p ON e.id = p.episodeID
                    WHERE p.isFinished IS NOT 1
                    """
            case .starred:
                sql = "SELECT COUNT(*) FROM episodes WHERE starred = 1"
            }
            let arguments: StatementArguments = rule == .downloaded ? [DownloadState.done.rawValue] : []
            return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    private static func fetchEpisodes(matching rule: PlaylistRule, limit: Int, db: Database) throws -> [Episode] {
        switch rule {
        case .recentlyAdded:
            return try Episode.order(Column("publishedDate").desc).limit(limit).fetchAll(db)

        case .inProgress:
            return try Episode.fetchAll(db, sql: """
                SELECT e.* FROM episodes e
                JOIN progress p ON e.id = p.episodeID
                WHERE p.position > 0 AND p.isFinished = 0
                ORDER BY p.updatedAt DESC
                LIMIT ?
                """, arguments: [limit])

        case .downloaded:
            return try Episode.fetchAll(db, sql: """
                SELECT e.* FROM episodes e
                JOIN downloads d ON e.id = d.episodeID
                WHERE d.state = ?
                ORDER BY e.publishedDate DESC
                LIMIT ?
                """, arguments: [DownloadState.done.rawValue, limit])

        case .unplayed:
            return try Episode.fetchAll(db, sql: """
                SELECT e.* FROM episodes e
                LEFT JOIN progress p ON e.id = p.episodeID
                WHERE p.isFinished IS NOT 1
                ORDER BY e.publishedDate DESC
                LIMIT ?
                """, arguments: [limit])

        case .starred:
            return try Episode
                .filter(Column("starred") == true)
                .order(Column("publishedDate").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
