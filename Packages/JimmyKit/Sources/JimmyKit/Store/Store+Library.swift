import Foundation
import GRDB

/// Podcast subscriptions: the Library screen's entire read/write surface onto `Store`.
nonisolated extension Store {
    /// An async sequence of the subscribed podcasts, re-emitted whenever they change — sorted the
    /// way the Library screen has always sorted them: newest episode first (podcasts with no
    /// episode yet sort last), then alphabetically by title as a stable tiebreaker.
    public func observePodcasts() -> AsyncValueObservation<[Podcast]> {
        ValueObservation
            .tracking { db in try Self.fetchSortedPodcasts(db) }
            .values(in: pool)
    }

    /// Subscribes to `feedURL`, inserting its podcast row and `parsed`'s episodes. Idempotent on
    /// feed URL (the column is UNIQUE): if a podcast with this feed URL already exists, it's
    /// returned unchanged rather than inserting a duplicate — callers that want to pull in
    /// whatever is new should follow up with `apply(_:)` instead.
    ///
    /// The podcast id is `FeedIDs.generatePodcastID(from:)`, the same deterministic id today's
    /// app already uses, so re-subscribing to a feed a user previously unsubscribed from lines
    /// back up with any of that podcast's episodes left over from before (if any ever
    /// survive a cascade delete — in practice they won't, since unsubscribing cascades).
    public func subscribe(feedURL: URL, parsed: ParsedFeed, etag: String? = nil) async throws -> Podcast {
        try await pool.write { db in
            if let existing = try Podcast
                .filter(Column("feedURL") == feedURL.absoluteString)
                .fetchOne(db) {
                return existing
            }

            let title = parsed.podcast.title ?? feedURL.absoluteString
            let podcast = Podcast(
                id: FeedIDs.generatePodcastID(from: feedURL),
                title: title,
                cleanTitle: title,
                author: parsed.podcast.author ?? "",
                description: parsed.podcast.description ?? "",
                feedURL: feedURL,
                artworkURL: parsed.podcast.artworkURL,
                lastEpisodeDate: parsed.episodes.compactMap(\.publishedDate).max(),
                etag: etag,
                lastFetched: Date()
            )
            try podcast.insert(db)

            // `FeedParser` already stamped every episode's id deterministically (see `FeedIDs`),
            // so a brand-new subscribe can never collide with another podcast's episodes; `.ignore`
            // only guards against the same feed being subscribed to concurrently from two places.
            for episode in parsed.episodes {
                try episode.insert(db, onConflict: .ignore)
            }

            return podcast
        }
    }

    /// Unsubscribes from `podcastID`, deleting its podcast row. Every table that references an
    /// episode (`queue`, `progress`, `downloads`, `playback_state`, `episode_details`,
    /// `bookmarks`, `episode_transcripts`) declares `ON DELETE CASCADE` back to `episodes`, which
    /// itself cascades from `podcasts` (see `LegacyMigrations`) — so this one delete is enough;
    /// nothing is left to clean up explicitly. Callers that need the queue's `1...n` positions
    /// renumbered around the gap this can leave (e.g. `AppModel`) should dequeue this podcast's
    /// episodes themselves first.
    public func unsubscribe(_ podcastID: UUID) async throws {
        _ = try await pool.write { db in
            try Podcast.deleteOne(db, key: podcastID.uuidString)
        }
    }

    /// Applies one feed's refresh outcome: `.notModified` and a failed outcome are both no-ops
    /// here (the caller, `AppModel.refreshAll`, surfaces a failure itself). `.updated` upserts any
    /// new episodes — an episode already on file is left exactly as it is, with its progress,
    /// played state, and every other legacy column untouched — and updates the podcast's own
    /// metadata and conditional-GET validator.
    ///
    /// - Returns: The ids of episodes this call actually inserted (i.e. that weren't already in
    ///   the store), for callers that auto-add new episodes to the queue.
    @discardableResult
    public func apply(_ outcome: FeedRefreshOutcome) async throws -> [UUID] {
        guard case .success(.updated(let parsed, let etag, _)) = outcome.result else { return [] }

        return try await pool.write { db in
            guard var podcast = try Podcast.fetchOne(db, key: outcome.podcastID.uuidString) else { return [] }

            var insertedIDs: [UUID] = []
            for episode in parsed.episodes {
                // Also match on audio URL within the podcast: episodes saved by older builds can
                // carry random ids instead of the deterministic ones `FeedParser` stamps.
                let alreadyExists = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT EXISTS(SELECT 1 FROM episodes WHERE id = ?
                            OR (podcastID = ? AND audioURL IS NOT NULL AND audioURL = ?))
                        """,
                    arguments: [episode.id.uuidString, outcome.podcastID.uuidString, episode.audioURL?.absoluteString]
                ) ?? false
                guard !alreadyExists else { continue }
                try episode.insert(db)
                insertedIDs.append(episode.id)
            }

            let latestEpisodeDate = try Date.fetchOne(
                db,
                sql: "SELECT MAX(publishedDate) FROM episodes WHERE podcastID = ?",
                arguments: [outcome.podcastID.uuidString]
            )

            podcast.title = parsed.podcast.title ?? podcast.title
            podcast.author = parsed.podcast.author ?? podcast.author
            podcast.description = parsed.podcast.description ?? podcast.description
            podcast.artworkURL = parsed.podcast.artworkURL ?? podcast.artworkURL
            podcast.lastEpisodeDate = latestEpisodeDate ?? podcast.lastEpisodeDate
            podcast.etag = etag
            podcast.lastFetched = Date()
            podcast.updatedAt = Date()
            try podcast.update(db)

            return insertedIDs
        }
    }

    /// Sets whether newly-fetched episodes of `podcastID` are auto-added to the queue (see
    /// `AppModel.refreshAll()`). A no-op if `podcastID` isn't subscribed.
    public func setAutoAddToQueue(_ enabled: Bool, podcastID: UUID) async throws {
        try await pool.write { db in
            try db.execute(
                sql: "UPDATE podcasts SET autoAddToQueue = ? WHERE id = ?",
                arguments: [enabled, podcastID.uuidString]
            )
        }
    }

    /// Inserts `episode` under `podcast`, creating `podcast` first if this is its first episode
    /// (idempotent on id, like `subscribe`). Used for locally imported audio, which has no feed to
    /// subscribe to — every import after the first lands on the same already-inserted podcast row.
    public func addLocalEpisode(_ episode: Episode, to podcast: Podcast) async throws {
        try await pool.write { db in
            if try Podcast.fetchOne(db, key: podcast.id.uuidString) == nil {
                try podcast.insert(db)
            }
            try episode.insert(db, onConflict: .replace)
        }
    }

    private static func fetchSortedPodcasts(_ db: Database) throws -> [Podcast] {
        try Podcast.fetchAll(db, sql: """
            SELECT * FROM podcasts
            ORDER BY lastEpisodeDate IS NULL, lastEpisodeDate DESC, title COLLATE NOCASE ASC
            """)
    }
}
