import Foundation
import GRDB

/// Whole-library reads and writes for `BackupService`'s full export/restore — the only place that
/// needs every row rather than one podcast's or one episode's worth.
nonisolated extension Store {
    public func allEpisodes() async throws -> [Episode] {
        try await pool.read { db in try Episode.fetchAll(db) }
    }

    public func allProgress() async throws -> [Progress] {
        try await pool.read { db in try Progress.fetchAll(db) }
    }

    public func allBookmarks() async throws -> [Bookmark] {
        try await pool.read { db in try Bookmark.fetchAll(db) }
    }

    /// Upserts every row from a backup, in dependency order (a podcast before its episodes, an
    /// episode before its progress/bookmarks) so foreign keys never fail partway through.
    public func restore(podcasts: [Podcast], episodes: [Episode], progress: [Progress], bookmarks: [Bookmark]) async throws {
        try await pool.write { db in
            for podcast in podcasts { try podcast.save(db) }
            for episode in episodes { try episode.save(db) }
            for entry in progress { try entry.save(db) }
            for bookmark in bookmarks { try bookmark.save(db) }
        }
    }
}
