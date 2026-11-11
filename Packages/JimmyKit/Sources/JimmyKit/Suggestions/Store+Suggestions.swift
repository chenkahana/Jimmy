import Foundation
import GRDB

// MARK: - ListeningStat (table: listening_stats)

extension ListeningStat: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "listening_stats"

    public nonisolated init(row: Row) throws {
        self.init(
            id: try StoredUUID.decode(row["id"], column: "id"),
            date: row["date"],
            podcastID: StoredUUID.decodeIfPresent(row["podcastID"]),
            seconds: row["seconds"]
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["date"] = date
        container["podcastID"] = podcastID?.uuidString
        container["seconds"] = seconds
    }
}

/// Reads for `SuggestionsRanker`'s signals — listening history beyond what `Store`'s core API
/// exposes. Kept here (not in `Store.swift`) since only Suggestions needs them.
public extension Store {
    /// Every episode's progress row — "finished a show a lot", "in progress", and "usual episode
    /// length" are all derived from this by `SuggestionsRanker`.
    func allProgress() async throws -> [Progress] {
        try await pool.read { db in try Progress.fetchAll(db) }
    }

    /// Day-level listening time, optionally attributed to a podcast (see `ListeningStat`). Mostly
    /// imported from the legacy app without a `podcastID` (see
    /// `Migrations.importListeningStats`), so `SuggestionsRanker` only treats rows that do carry
    /// one as a recency signal.
    func listeningStats() async throws -> [ListeningStat] {
        try await pool.read { db in try ListeningStat.fetchAll(db) }
    }
}
