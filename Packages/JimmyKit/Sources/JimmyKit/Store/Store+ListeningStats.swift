import Foundation
import GRDB

/// Listening-time tracking: one row per (day, podcast) logged against `listening_stats`.
/// Aggregates (totals, streaks, top podcasts) are derived by querying these rows — see
/// `ListeningStat`'s doc comment — rather than stored as separate fields, so there's nothing to
/// keep in sync. Replaces `ListeningStatsService`, which polled a 5-second `Timer` to persist a
/// single JSON aggregate.
nonisolated extension Store {
    /// Logs `seconds` of listening on `date`'s calendar day, optionally attributed to a podcast.
    /// A no-op for a non-positive duration (nothing meaningful to log).
    public func addListeningSeconds(_ seconds: TimeInterval, podcastID: UUID?, on date: Date = Date()) async throws {
        guard seconds > 0 else { return }
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO listening_stats (id, date, podcastID, seconds) VALUES (?, ?, ?, ?)",
                arguments: [UUID().uuidString, Self.dayString(date), podcastID?.uuidString, seconds]
            )
        }
    }

    /// One row per day that has any logged time, summed across podcasts, newest first.
    public func listeningStatsByDay() async throws -> [ListeningStat] {
        try await pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT date, SUM(seconds) AS seconds FROM listening_stats GROUP BY date ORDER BY date DESC"
            ).map { row in
                ListeningStat(date: row["date"], seconds: row["seconds"] ?? 0)
            }
        }
    }

    public func totalListeningSeconds() async throws -> TimeInterval {
        try await pool.read { db in
            try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(seconds), 0) FROM listening_stats") ?? 0
        }
    }

    /// Episodes marked finished — a direct count from `progress`, unlike the legacy
    /// `ListeningStats.episodesCompleted` counter, which nothing ever actually incremented.
    public func episodesCompletedCount() async throws -> Int {
        try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM progress WHERE isFinished = 1") ?? 0
        }
    }

    public struct PodcastListeningTotal: Sendable, Hashable {
        public let podcastID: UUID
        public let seconds: TimeInterval
    }

    public func topPodcastsByListeningTime(limit: Int = 5) async throws -> [PodcastListeningTotal] {
        try await pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT podcastID, SUM(seconds) AS seconds FROM listening_stats
                    WHERE podcastID IS NOT NULL
                    GROUP BY podcastID
                    ORDER BY seconds DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).compactMap { row -> PodcastListeningTotal? in
                guard let idString: String = row["podcastID"], let id = UUID(uuidString: idString) else { return nil }
                return PodcastListeningTotal(podcastID: id, seconds: row["seconds"] ?? 0)
            }
        }
    }

    /// "yyyy-MM-dd" in the user's local calendar — matches `ListeningStat.date`'s documented format.
    public static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
