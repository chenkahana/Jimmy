import Foundation
import GRDB

/// Podcast detail, episode rows, and episode detail: the one place these screens read episodes
/// (joined with progress/queue/download state), mark played/unplayed, and read/write bookmarks,
/// transcripts, and chapters — all on the existing legacy tables (`episodes`, `progress`, `queue`,
/// `downloads`, `bookmarks`, `episode_transcripts`, `episode_details.chaptersJSON`).
nonisolated extension Store {
    /// One episode by id, or `nil` if it doesn't exist (e.g. deleted since a cached navigation
    /// target was captured).
    public func episode(id: UUID) async throws -> Episode? {
        try await pool.read { db in try Episode.fetchOne(db, key: id.uuidString) }
    }

    /// An async sequence of `podcastID`'s episodes — or, with `podcastID` nil, every episode
    /// across the whole library (newest first, for the Library screen's flat episode list) —
    /// each joined with its progress, queue membership, and download state. Re-emitted whenever
    /// any of those change.
    public func observeEpisodes(podcastID: UUID?) -> AsyncValueObservation<[EpisodeListItem]> {
        ValueObservation
            .tracking { db in try Self.fetchEpisodeListItems(podcastID: podcastID, db: db) }
            .values(in: pool)
    }

    /// The queued episodes, in queue order, with their progress and download state. Cheaper than
    /// `observeEpisodes(podcastID: nil)` for the Queue screen, which re-reads on every progress save.
    public func observeQueueItems() -> AsyncValueObservation<[EpisodeListItem]> {
        ValueObservation
            .tracking { db in try Self.wrapAsListItems(Self.fetchQueueEpisodes(db), db: db) }
            .values(in: pool)
    }

    private static func fetchEpisodeListItems(podcastID: UUID?, db: Database) throws -> [EpisodeListItem] {
        let episodes: [Episode]
        if let podcastID {
            episodes = try Episode
                .filter(Column("podcastID") == podcastID.uuidString)
                .order(Column("publishedDate").desc)
                .fetchAll(db)
        } else {
            episodes = try Episode.order(Column("publishedDate").desc).fetchAll(db)
        }
        return try wrapAsListItems(episodes, db: db)
    }

    /// Joins `episodes` with their progress, queue membership, and download state — the common
    /// tail of `fetchEpisodeListItems` above and `Store+Playlists.swift`'s rule-filtered fetches,
    /// which only differ in which episodes they start from.
    static func wrapAsListItems(_ episodes: [Episode], db: Database) throws -> [EpisodeListItem] {
        guard !episodes.isEmpty else { return [] }

        let episodeIDStrings = episodes.map(\.id.uuidString)
        let progressByID = Dictionary(
            uniqueKeysWithValues: try Progress
                .filter(episodeIDStrings.contains(Column("episodeID")))
                .fetchAll(db)
                .map { ($0.episodeID, $0) }
        )
        let queuedIDs = Set(
            try QueueEntry
                .filter(episodeIDStrings.contains(Column("episodeID")))
                .fetchAll(db)
                .map(\.episodeID)
        )
        let downloadStateByID = Dictionary(
            uniqueKeysWithValues: try Download
                .filter(episodeIDStrings.contains(Column("episodeID")))
                .fetchAll(db)
                .map { ($0.episodeID, $0.state) }
        )

        return episodes.map { episode in
            EpisodeListItem(
                episode: episode,
                progress: progressByID[episode.id],
                isQueued: queuedIDs.contains(episode.id),
                downloadState: downloadStateByID[episode.id]
            )
        }
    }

    // MARK: - Played / unplayed

    /// Marks `episodeID` played. Creates a zeroed `Progress` row if none exists yet; otherwise
    /// only flips `isFinished` — position is left exactly as it is, matching today's "mark
    /// played" toggle, which doesn't touch playback position either.
    public func markPlayed(_ episodeID: UUID) async throws {
        try await setFinished(episodeID, isFinished: true)
    }

    public func markUnplayed(_ episodeID: UUID) async throws {
        try await setFinished(episodeID, isFinished: false)
    }

    private func setFinished(_ episodeID: UUID, isFinished: Bool) async throws {
        try await pool.write { db in
            var progress = try Progress.fetchOne(db, key: episodeID.uuidString)
                ?? Progress(episodeID: episodeID, position: 0)
            progress.isFinished = isFinished
            progress.updatedAt = Date()
            try progress.save(db)
        }
    }

    // MARK: - Bookmarks (table: bookmarks)

    public func bookmarks(for episodeID: UUID) async throws -> [Bookmark] {
        try await pool.read { db in
            try Bookmark
                .filter(Column("episodeID") == episodeID.uuidString)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    @discardableResult
    public func addBookmark(episodeID: UUID, timestamp: TimeInterval, note: String = "") async throws -> Bookmark {
        let bookmark = Bookmark(episodeID: episodeID, timestamp: timestamp, note: note)
        try await pool.write { db in try bookmark.insert(db) }
        return bookmark
    }

    public func deleteBookmark(_ id: UUID) async throws {
        _ = try await pool.write { db in try Bookmark.deleteOne(db, key: id.uuidString) }
    }

    // MARK: - Transcript (table: episode_transcripts)
    //
    // Not a `FetchableRecord`/`PersistableRecord` conformance: the stored row allows a `NULL`
    // `transcriptURL`, while `Transcript.url` is non-optional (a transcript is only ever saved
    // after fetching it from somewhere) — a plain row read/write sidesteps that mismatch.

    public func transcript(for episodeID: UUID) async throws -> Transcript? {
        try await pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT transcriptURL, format, segmentsJSON FROM episode_transcripts WHERE episodeID = ?",
                arguments: [episodeID.uuidString]
            ) else { return nil }

            let urlString: String? = row["transcriptURL"]
            guard let urlString, let url = URL(string: urlString) else { return nil }
            let format = TranscriptFormat(rawValue: row["format"] ?? "srt") ?? .srt
            let segmentsJSON: String = row["segmentsJSON"] ?? "[]"
            let segments = segmentsJSON.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode([TranscriptSegment].self, from: $0) }
            return Transcript(episodeID: episodeID, url: url, format: format, segments: segments)
        }
    }

    public func saveTranscript(_ transcript: Transcript) async throws {
        let data = try JSONEncoder().encode(transcript.segments ?? [])
        let json = String(data: data, encoding: .utf8) ?? "[]"
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO episode_transcripts (episodeID, transcriptURL, format, segmentsJSON, fetchedAt)
                    VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(episodeID) DO UPDATE SET
                        transcriptURL = excluded.transcriptURL, format = excluded.format,
                        segmentsJSON = excluded.segmentsJSON, fetchedAt = CURRENT_TIMESTAMP
                    """,
                arguments: [
                    transcript.episodeID.uuidString, transcript.url.absoluteString,
                    transcript.format.rawValue, json,
                ]
            )
        }
    }

    // MARK: - Chapters (table: episode_details, column: chaptersJSON)

    public func chapters(for episodeID: UUID) async throws -> [Chapter] {
        try await pool.read { db in
            guard let json = try String.fetchOne(
                db, sql: "SELECT chaptersJSON FROM episode_details WHERE episodeID = ?", arguments: [episodeID.uuidString]
            ), let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([Chapter].self, from: data)) ?? []
        }
    }

    public func saveChapters(_ chapters: [Chapter], for episodeID: UUID) async throws {
        let data = try JSONEncoder().encode(chapters)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        try await pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO episode_details (episodeID, fullDescription, chaptersJSON, updatedAt)
                    VALUES (?, '', ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(episodeID) DO UPDATE SET chaptersJSON = excluded.chaptersJSON, updatedAt = CURRENT_TIMESTAMP
                    """,
                arguments: [episodeID.uuidString, json]
            )
        }
    }
}
