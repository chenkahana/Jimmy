import Foundation
import GRDB

/// Errors thrown by `Store`. There is no `fatalError` and no silent `:memory:` fallback
/// anywhere in this type — a failure to open or migrate is always reported to the caller.
public enum StoreError: Error, Sendable {
    case openFailed(underlying: String)
    case migrationFailed(underlying: String)
    /// A stored id that is neither a UUID string nor a 16-byte UUID blob.
    case badID(column: String)
}

/// The one GRDB store for JimmyKit. Opens the user's existing `Documents/jimmy.db` (as left by
/// today's app, migrated through `v17_create_transcripts`) and extends it additively with
/// `v19_progress` through `v22_downloads`. Nothing from the legacy schema is dropped or
/// altered, so today's app can keep reading/writing the same file during the transition.
public nonisolated final class Store: Sendable {
    // Internal (not `private`) so `Store+Library.swift` and other same-module extensions can
    // drive their own `pool.read`/`pool.write` calls.
    let pool: DatabasePool

    /// The on-disk path this store was opened with. Not used by any production code path (every
    /// read/write goes through `pool`) — kept only so tests can open a second raw connection to
    /// poke at a column `Store`'s own API never writes (e.g. the legacy `played` column).
    let testOnlyPath: String

    /// Opens (creating if needed) the database at `path`, running the frozen legacy migrations
    /// followed by this package's own, then — if `legacy` is non-nil — importing legacy
    /// on-disk data exactly once (subsequent opens, with or without `legacy`, are no-ops for
    /// migrations already applied).
    public init(path: String, legacy: LegacyInput? = nil) throws {
        let pool: DatabasePool
        do {
            // DatabasePool always runs in WAL mode; `Configuration().foreignKeysEnabled`
            // already defaults to `true`. From PR 15 on, the legacy app's own `DatabasePool`
            // writes this same file concurrently — `busyMode` makes a write wait for the other
            // pool's transaction to finish instead of immediately failing with `SQLITE_BUSY`.
            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            pool = try DatabasePool(path: path, configuration: configuration)
        } catch {
            throw StoreError.openFailed(underlying: String(describing: error))
        }

        var migrator = DatabaseMigrator()
        LegacyMigrations.register(on: &migrator)
        Migrations.register(on: &migrator, legacy: legacy)

        do {
            try migrator.migrate(pool)
        } catch {
            throw StoreError.migrationFailed(underlying: String(describing: error))
        }

        self.pool = pool
        self.testOnlyPath = path
    }

    // MARK: - Podcasts

    public func podcasts() async throws -> [Podcast] {
        try await pool.read { db in
            try Podcast.order(Column("title")).fetchAll(db)
        }
    }

    // MARK: - Episodes

    public func episodes(podcastID: UUID) async throws -> [Episode] {
        try await pool.read { db in
            try Episode
                .filter(Column("podcastID") == podcastID.uuidString)
                .order(Column("publishedDate").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Queue
    //
    // Positions are always kept at 1...n, with no gaps and no duplicates. Unlike today's app
    // (see QueueOrderTests), dequeuing position 1 promotes the next episode into position 1
    // rather than leaving a gap — this is an intentional behavior change for the new store.

    /// The queue's episodes, in play order.
    public func queue() async throws -> [Episode] {
        try await pool.read { db in try Self.fetchQueueEpisodes(db) }
    }

    /// Inserts (or moves, if already queued) `episodeID` to `position`, shifting everything
    /// else to keep positions contiguous. `position` is clamped to `1...(count + 1)`.
    public func enqueue(_ episodeID: UUID, at position: Int) async throws {
        try await pool.write { db in try Self.insertIntoQueue(episodeID, at: position, db: db) }
    }

    /// Removes `episodeID` from the queue, if present, closing the gap left behind. A no-op if
    /// the episode isn't queued.
    public func dequeue(_ episodeID: UUID) async throws {
        try await pool.write { db in try Self.removeFromQueue(episodeID, db: db) }
    }

    /// Moves an already-queued `episodeID` to `position`. Implemented as remove-then-insert, so
    /// it shares `enqueue`'s clamping and renumbering.
    public func moveInQueue(_ episodeID: UUID, to position: Int) async throws {
        try await pool.write { db in try Self.insertIntoQueue(episodeID, at: position, db: db) }
    }

    /// An async sequence of the queue's episodes, re-emitted whenever the queue changes.
    public func observeQueue() -> AsyncValueObservation<[Episode]> {
        ValueObservation
            .tracking { db in try Self.fetchQueueEpisodes(db) }
            .values(in: pool)
    }

    // MARK: - Progress

    public func progress(for episodeID: UUID) async throws -> Progress? {
        try await pool.read { db in
            try Progress.fetchOne(db, key: episodeID.uuidString)
        }
    }

    public func saveProgress(_ progress: Progress) async throws {
        try await pool.write { db in try progress.save(db) }
    }

    // MARK: - Downloads

    public func downloads() async throws -> [Download] {
        try await pool.read { db in try Download.fetchAll(db) }
    }

    public func saveDownload(_ download: Download) async throws {
        try await pool.write { db in try download.save(db) }
    }

    // MARK: - Queue internals

    private static func fetchQueueEpisodes(_ db: Database) throws -> [Episode] {
        try Episode.fetchAll(db, sql: """
            SELECT episodes.* FROM episodes
            JOIN queue ON queue.episodeID = episodes.id
            ORDER BY queue.position ASC
            """)
    }

    private static func insertIntoQueue(_ episodeID: UUID, at position: Int, db: Database) throws {
        try removeFromQueue(episodeID, db: db)
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM queue") ?? 0
        let clamped = max(1, min(position, count + 1))
        try shiftUp(from: clamped, db: db)
        try db.execute(
            sql: "INSERT INTO queue (episodeID, position) VALUES (?, ?)",
            arguments: [episodeID.uuidString, clamped]
        )
    }

    private static func removeFromQueue(_ episodeID: UUID, db: Database) throws {
        guard let removedPosition = try Int.fetchOne(
            db, sql: "SELECT position FROM queue WHERE episodeID = ?", arguments: [episodeID.uuidString]
        ) else {
            return
        }
        try db.execute(sql: "DELETE FROM queue WHERE episodeID = ?", arguments: [episodeID.uuidString])
        try shiftDown(after: removedPosition, db: db)
    }

    /// Opens a one-slot gap at `position` by pushing everything at or after it up by one.
    /// Processes highest-position-first so no single-row UPDATE ever collides with the
    /// UNIQUE constraint on `queue.position`.
    private static func shiftUp(from position: Int, db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT episodeID, position FROM queue WHERE position >= ? ORDER BY position DESC",
            arguments: [position]
        )
        for row in rows {
            let episodeID: String = row["episodeID"]
            let currentPosition: Int = row["position"]
            try db.execute(
                sql: "UPDATE queue SET position = ? WHERE episodeID = ?",
                arguments: [currentPosition + 1, episodeID]
            )
        }
    }

    /// Closes the one-slot gap left at `position` by pulling everything after it down by one.
    /// Processes lowest-position-first for the same collision-avoidance reason as `shiftUp`.
    private static func shiftDown(after position: Int, db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT episodeID, position FROM queue WHERE position > ? ORDER BY position ASC",
            arguments: [position]
        )
        for row in rows {
            let episodeID: String = row["episodeID"]
            let currentPosition: Int = row["position"]
            try db.execute(
                sql: "UPDATE queue SET position = ? WHERE episodeID = ?",
                arguments: [currentPosition - 1, episodeID]
            )
        }
    }
}

// MARK: - Downloads records

extension Store: DownloadRecords {
    public func loadDownloads() async throws -> [Download] {
        try await downloads()
    }

    public func deleteDownload(_ episodeID: UUID) async throws {
        _ = try await pool.write { db in try Download.deleteOne(db, key: episodeID.uuidString) }
    }
}
