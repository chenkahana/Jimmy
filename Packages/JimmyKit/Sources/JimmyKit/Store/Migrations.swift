import Foundation
import GRDB

/// Legacy on-disk data to import, once, during the `v20_legacy_import` migration. Decoding
/// happens inside that migration (not by the caller), so this type owns exactly how each
/// legacy format is read — matching `Tests/Fixtures/LegacyData/README.md`'s decoder
/// configurations. A `nil` field (or a `nil` `LegacyInput` passed to `Store.init`) is a no-op
/// for that piece of data.
public nonisolated struct LegacyInput: Sendable {
    /// UserDefaults key `"saved_podcasts"`: plain `JSONDecoder()` -> `[Podcast]`.
    public var savedPodcastsData: Data?
    /// `Documents/AppData/podcasts.json`: plain `JSONDecoder()` -> `[Podcast]`.
    public var appDataPodcastsData: Data?
    /// UserDefaults key `"episode_queue"`: plain `JSONDecoder()` -> `[Episode]` (legacy shape).
    public var episodeQueueData: Data?
    /// `Documents/listening_stats.json`: `JSONDecoder` with `.iso8601` -> `ListeningStats`.
    public var listeningStatsData: Data?
    /// The last episode the user was playing, from wherever today's app tracks it.
    public var lastPlayedEpisodeID: UUID?

    public init(
        savedPodcastsData: Data? = nil,
        appDataPodcastsData: Data? = nil,
        episodeQueueData: Data? = nil,
        listeningStatsData: Data? = nil,
        lastPlayedEpisodeID: UUID? = nil
    ) {
        self.savedPodcastsData = savedPodcastsData
        self.appDataPodcastsData = appDataPodcastsData
        self.episodeQueueData = episodeQueueData
        self.listeningStatsData = listeningStatsData
        self.lastPlayedEpisodeID = lastPlayedEpisodeID
    }
}

/// New, additive migrations layered on top of the 17 frozen `LegacyMigrations`. These never
/// drop or alter an existing legacy table or column — today's app keeps reading and writing
/// them unchanged until its screens move onto `Store`.
nonisolated enum Migrations {
    static func register(on migrator: inout DatabaseMigrator, legacy: LegacyInput?) {
        migrator.registerMigration("v18_uuid_text") { db in
            try Self.convertBlobUUIDsToText(db)
        }
        migrator.registerMigration("v19_progress") { db in
            try Self.runProgressAndQueueBackfill(db)
        }
        migrator.registerMigration("v20_legacy_import") { db in
            try Self.runLegacyImport(db, legacy: legacy)
        }
        migrator.registerMigration("v21_playlists") { db in
            try db.create(table: "playlists", ifNotExists: true) { t in
                t.column("id", .text).primaryKey().notNull()
                t.column("name", .text).notNull()
                t.column("rule", .text).notNull()
            }
        }
        migrator.registerMigration("v22_downloads") { db in
            try Self.runDownloadsBackfill(db)
        }
    }

    // MARK: - v18_uuid_text

    /// Older builds wrote some UUID columns as 16-byte blobs, and today's app reads both forms.
    /// Rewrite blobs as uppercase `uuidString` text so every id compares as text in SQL and
    /// decodes the same way. `UPDATE OR IGNORE` leaves a row alone if its text form already exists.
    static let uuidColumns: [(table: String, column: String)] = [
        ("podcasts", "id"), ("episodes", "id"), ("episodes", "podcastID"),
        ("playback_state", "episodeID"), ("episode_details", "episodeID"),
        ("bookmarks", "id"), ("bookmarks", "episodeID"), ("episode_transcripts", "episodeID"),
    ]

    private static func convertBlobUUIDsToText(_ db: Database) throws {
        let text = """
            substr(hex(%@), 1, 8) || '-' || substr(hex(%@), 9, 4) || '-' || substr(hex(%@), 13, 4) || '-' || \
            substr(hex(%@), 17, 4) || '-' || substr(hex(%@), 21, 12)
            """
        for (table, column) in uuidColumns {
            guard try db.tableExists(table),
                  try db.columns(in: table).contains(where: { $0.name == column }) else { continue }
            let expression = text.replacingOccurrences(of: "%@", with: column)
            try db.execute(sql: """
                UPDATE OR IGNORE \(table) SET \(column) = \(expression)
                WHERE typeof(\(column)) = 'blob' AND length(\(column)) = 16
                """)
        }
    }

    // MARK: - v19_progress

    private static func runProgressAndQueueBackfill(_ db: Database) throws {
        try db.create(table: "progress", ifNotExists: true) { t in
            t.column("episodeID", .text).primaryKey()
                .references("episodes", column: "id", onDelete: .cascade)
            t.column("position", .double).notNull().defaults(to: 0.0)
            t.column("duration", .double)
            t.column("isFinished", .boolean).notNull().defaults(to: false)
            t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        }
        try db.create(table: "queue", ifNotExists: true) { t in
            t.column("episodeID", .text).primaryKey()
                .references("episodes", column: "id", onDelete: .cascade)
            t.column("position", .integer).notNull().unique()
        }

        // progress: finished if playback_state.finished OR episodes.played OR the status
        // played bit is set; position = playback_state.position if present, else
        // episodes.playbackPosition.
        let episodes = try Row.fetchAll(db, sql: "SELECT id, duration, playbackPosition, played, status FROM episodes")
        for row in episodes {
            let episodeID: String = row["id"]
            let duration: Double? = row["duration"]
            let playbackPosition: Double = (row["playbackPosition"] as Double?) ?? 0.0
            let played: Bool = (row["played"] as Bool?) ?? false
            let status: Int = (row["status"] as Int?) ?? 0

            var position = playbackPosition
            var isFinished = played || (status & 1) == 1
            var updatedAt = Date()

            if let playbackState = try Row.fetchOne(
                db,
                sql: "SELECT position, finished, updatedAt FROM playback_state WHERE episodeID = ?",
                arguments: [episodeID]
            ) {
                let psPosition: Double? = playbackState["position"]
                let psFinished: Bool? = playbackState["finished"]
                let psUpdatedAt: Date? = playbackState["updatedAt"]
                position = psPosition ?? position
                isFinished = isFinished || (psFinished ?? false)
                updatedAt = psUpdatedAt ?? updatedAt
            }

            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO progress (episodeID, position, duration, isFinished, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [episodeID, position, duration, isFinished, updatedAt]
            )
        }

        // queue: from playback_state.queuePosition, renumbered 1...n with no gaps, ordered by
        // the old queuePosition.
        let queueRows = try Row.fetchAll(
            db,
            sql: "SELECT episodeID FROM playback_state WHERE queuePosition IS NOT NULL ORDER BY queuePosition ASC"
        )
        for (index, row) in queueRows.enumerated() {
            let episodeID: String = row["episodeID"]
            try db.execute(
                sql: "INSERT OR REPLACE INTO queue (episodeID, position) VALUES (?, ?)",
                arguments: [episodeID, index + 1]
            )
        }
    }

    // MARK: - v20_legacy_import

    /// Shape of `Podcast` as written by the legacy app (UserDefaults `"saved_podcasts"` and
    /// `Documents/AppData/podcasts.json`), decoded with a plain `JSONDecoder()`. Today's
    /// `Podcast` model adds `createdAt`/`updatedAt`, which aren't in the legacy JSON, so this
    /// mirrors the on-disk shape exactly instead of decoding into the model directly.
    private struct LegacyPodcast: Decodable {
        var id: UUID
        var title: String
        var cleanTitle: String
        var author: String
        var description: String
        var feedURL: URL
        var artworkURL: URL?
        var autoAddToQueue: Bool
        var notificationsEnabled: Bool
        var lastEpisodeDate: Date?
        var etag: String?
        var lastFetched: Date?
    }

    /// Only the `id` is needed to reconstruct queue order; `Decodable` ignores the rest of the
    /// legacy episode JSON's keys.
    private struct LegacyQueuedEpisodeID: Decodable {
        var id: UUID
    }

    /// Only `dailyLogs` fits the `listening_stats` table, which requires a `date` per row.
    /// `totalListeningTime`, `perPodcast`, the streak counters, `lastListenedDate` and
    /// `episodesCompleted` are aggregates that don't have a single day to attach to and are
    /// intentionally not imported — see the final report for this gap.
    private struct LegacyListeningStats: Decodable {
        struct DailyLog: Decodable {
            var dateString: String
            var seconds: TimeInterval
        }
        var dailyLogs: [DailyLog]
    }

    private static func runLegacyImport(_ db: Database, legacy: LegacyInput?) throws {
        try db.create(table: "listening_stats", ifNotExists: true) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("date", .text).notNull()
            t.column("podcastID", .text)
            t.column("seconds", .double).notNull().defaults(to: 0.0)
        }
        try db.create(table: "settings", ifNotExists: true) { t in
            t.column("key", .text).primaryKey().notNull()
            t.column("value", .text).notNull()
        }

        guard let legacy else { return }

        // Keep every legacy source verbatim, so nothing is lost even where the import below
        // can't map it (e.g. per-podcast totals and streaks in listening_stats.json).
        let sources: [(String, Data?)] = [
            ("legacy.saved_podcasts", legacy.savedPodcastsData),
            ("legacy.podcasts_json", legacy.appDataPodcastsData),
            ("legacy.episode_queue", legacy.episodeQueueData),
            ("legacy.listening_stats_json", legacy.listeningStatsData),
        ]
        for (key, data) in sources {
            guard let data else { continue }
            try db.execute(
                sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arguments: [key, data.base64EncodedString()]
            )
        }

        // A source that doesn't decode is skipped rather than failing the migration:
        // the store must still open, and the raw copy above is kept.
        try importSubscriptions(legacy, into: db)
        try importQueue(legacy, into: db)
        try importListeningStats(legacy, into: db)
        try importLastPlayedEpisode(legacy, into: db)
    }

    /// Subscriptions from `saved_podcasts` + `podcasts.json`, not already in `podcasts`
    /// (matched on `feedURL`, which is UNIQUE on that table, so `INSERT OR IGNORE` is enough —
    /// this also naturally de-duplicates the overlap between the two legacy sources).
    private static func importSubscriptions(_ legacy: LegacyInput, into db: Database) throws {
        var podcasts: [LegacyPodcast] = []
        if let data = legacy.savedPodcastsData {
            podcasts += (try? JSONDecoder().decode([LegacyPodcast].self, from: data)) ?? []
        }
        if let data = legacy.appDataPodcastsData {
            podcasts += (try? JSONDecoder().decode([LegacyPodcast].self, from: data)) ?? []
        }

        for podcast in podcasts {
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO podcasts
                        (id, title, author, description, feedURL, artworkURL, autoAddToQueue,
                         notificationsEnabled, lastEpisodeDate, etag, lastFetched, cleanTitle)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    podcast.id.uuidString, podcast.title, podcast.author, podcast.description,
                    podcast.feedURL.absoluteString, podcast.artworkURL?.absoluteString,
                    podcast.autoAddToQueue, podcast.notificationsEnabled,
                    podcast.lastEpisodeDate, podcast.etag, podcast.lastFetched, podcast.cleanTitle
                ]
            )
        }
    }

    /// Queue entries from `episode_queue`, appended after the existing queue, in file order,
    /// skipping any episode that doesn't exist (or is already queued).
    private static func importQueue(_ legacy: LegacyInput, into db: Database) throws {
        guard let data = legacy.episodeQueueData else { return }
        guard let entries = try? JSONDecoder().decode([LegacyQueuedEpisodeID].self, from: data) else { return }

        var nextPosition = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), 0) FROM queue") ?? 0
        for entry in entries {
            let episodeIDString = entry.id.uuidString
            let episodeExists = try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM episodes WHERE id = ?)", arguments: [episodeIDString]
            ) ?? false
            guard episodeExists else { continue }

            let alreadyQueued = try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM queue WHERE episodeID = ?)", arguments: [episodeIDString]
            ) ?? false
            guard !alreadyQueued else { continue }

            nextPosition += 1
            try db.execute(
                sql: "INSERT INTO queue (episodeID, position) VALUES (?, ?)",
                arguments: [episodeIDString, nextPosition]
            )
        }
    }

    /// Day-level listening stats from `listening_stats.json`, decoded with `.iso8601` per the
    /// fixture README (the reduced `LegacyListeningStats` shape here only needs `dailyLogs`,
    /// which don't contain dates to decode, but the strategy is set for fidelity with the spec).
    private static func importListeningStats(_ legacy: LegacyInput, into db: Database) throws {
        guard let data = legacy.listeningStatsData else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stats = try? decoder.decode(LegacyListeningStats.self, from: data) else { return }

        for log in stats.dailyLogs {
            try db.execute(
                sql: "INSERT INTO listening_stats (id, date, podcastID, seconds) VALUES (?, ?, NULL, ?)",
                arguments: [UUID().uuidString, log.dateString, log.seconds]
            )
        }
    }

    private static func importLastPlayedEpisode(_ legacy: LegacyInput, into db: Database) throws {
        guard let episodeID = legacy.lastPlayedEpisodeID else { return }
        try db.execute(
            sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            arguments: ["lastPlayedEpisodeID", episodeID.uuidString]
        )
    }

    // MARK: - v22_downloads

    private static func runDownloadsBackfill(_ db: Database) throws {
        try db.create(table: "downloads", ifNotExists: true) { t in
            t.column("episodeID", .text).primaryKey()
                .references("episodes", column: "id", onDelete: .cascade)
            t.column("relativePath", .text).notNull()
            t.column("byteCount", .integer)
            t.column("state", .text).notNull().defaults(to: DownloadState.done.rawValue)
            t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        }

        let rows = try Row.fetchAll(db, sql: "SELECT id, localFileURL FROM episodes WHERE localFileURL IS NOT NULL")
        for row in rows {
            let episodeID: String = row["id"]
            let localFileURL: String? = row["localFileURL"]
            guard let localFileURL, !localFileURL.isEmpty,
                  let relativePath = Self.relativeDownloadPath(from: localFileURL) else { continue }

            try db.execute(
                sql: "INSERT OR REPLACE INTO downloads (episodeID, relativePath, state) VALUES (?, ?, ?)",
                arguments: [episodeID, relativePath, DownloadState.done.rawValue]
            )
        }
    }

    /// Strips everything up to and including `Documents/` from an absolute (or already
    /// app-container-relative) file path, e.g. `Documents/Downloads/<id>.mp3` becomes
    /// `Downloads/<id>.mp3`. Returns `nil` when there's no `Documents/` segment to anchor on.
    private static func relativeDownloadPath(from localFileURL: String) -> String? {
        let marker = "Documents/"
        guard let range = localFileURL.range(of: marker) else { return nil }
        let relative = String(localFileURL[range.upperBound...])
        return relative.isEmpty ? nil : relative
    }
}
