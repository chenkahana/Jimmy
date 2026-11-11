import Foundation
import GRDB

// All UUID-typed columns are written as `uuidString` TEXT, the format today's app writes.
// Reads accept a 16-byte blob as well (older builds wrote some), and a value that is neither
// throws instead of being replaced with a new random id. `v18_uuid_text` converts the blobs.

nonisolated enum StoredUUID {
    static func decode(_ value: DatabaseValue, column: String) throws -> UUID {
        guard let uuid = decodeIfPresent(value) else { throw StoreError.badID(column: column) }
        return uuid
    }

    static func decodeIfPresent(_ value: DatabaseValue) -> UUID? {
        switch value.storage {
        case .string(let string):
            return UUID(uuidString: string)
        case .blob(let data) where data.count == 16:
            return UUID(uuid: data.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
        default:
            return nil
        }
    }
}

// MARK: - Podcast (table: podcasts)

extension Podcast: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "podcasts"

    public nonisolated init(row: Row) throws {
        self.init(
            id: try StoredUUID.decode(row["id"], column: "id"),
            title: row["title"],
            cleanTitle: row["cleanTitle"],
            author: row["author"],
            description: row["description"] ?? "",
            feedURL: row["feedURL"],
            artworkURL: row["artworkURL"],
            autoAddToQueue: row["autoAddToQueue"] ?? false,
            notificationsEnabled: row["notificationsEnabled"] ?? false,
            lastEpisodeDate: row["lastEpisodeDate"],
            etag: row["etag"],
            lastFetched: row["lastFetched"],
            createdAt: row["createdAt"] ?? Date(),
            updatedAt: row["updatedAt"] ?? Date()
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["title"] = title
        container["cleanTitle"] = cleanTitle
        container["author"] = author
        container["description"] = description
        container["feedURL"] = feedURL
        container["artworkURL"] = artworkURL
        container["autoAddToQueue"] = autoAddToQueue
        container["notificationsEnabled"] = notificationsEnabled
        container["lastEpisodeDate"] = lastEpisodeDate
        container["etag"] = etag
        container["lastFetched"] = lastFetched
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}

// MARK: - Episode (table: episodes)
//
// Maps only the columns `Episode` has. The legacy-only columns still on this table —
// `played`, `localFileURL`, `playbackPosition`, `lastFetched`, `status` — are deliberately left
// untouched here; that state now lives in `Progress` / `Download`.
//
// Note: `episodes.podcastID` is NOT NULL in the frozen legacy schema, while `Episode.podcastID`
// is `Optional`. Inserting an `Episode` with a `nil` podcastID through this conformance will
// throw a constraint violation at the database layer — flagged in the PR report rather than
// loosening the historical constraint, which is out of this PR's scope.

extension Episode: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "episodes"

    public nonisolated init(row: Row) throws {
        self.init(
            id: try StoredUUID.decode(row["id"], column: "id"),
            podcastID: StoredUUID.decodeIfPresent(row["podcastID"]),
            title: row["title"],
            audioURL: row["audioURL"],
            publishedDate: row["publishedDate"],
            duration: row["duration"],
            artworkURL: row["artworkURL"],
            description: row["description"],
            isNew: row["isNew"] ?? true,
            fetchedAt: row["fetchedAt"] ?? Date(),
            page: row["page"] ?? 1,
            starred: row["starred"] ?? false
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["podcastID"] = podcastID?.uuidString
        container["title"] = title
        container["audioURL"] = audioURL
        container["publishedDate"] = publishedDate
        container["duration"] = duration
        container["artworkURL"] = artworkURL
        container["description"] = description
        container["isNew"] = isNew
        container["fetchedAt"] = fetchedAt
        container["page"] = page
        container["starred"] = starred
    }
}

// MARK: - Progress (table: progress)

extension Progress: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "progress"

    public nonisolated init(row: Row) throws {
        self.init(
            episodeID: try StoredUUID.decode(row["episodeID"], column: "episodeID"),
            position: row["position"],
            duration: row["duration"],
            isFinished: row["isFinished"] ?? false,
            updatedAt: row["updatedAt"] ?? Date()
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["episodeID"] = episodeID.uuidString
        container["position"] = position
        container["duration"] = duration
        container["isFinished"] = isFinished
        container["updatedAt"] = updatedAt
    }
}

// MARK: - QueueEntry (table: queue)
//
// `Store` manages the `queue` table directly with hand-written SQL (to keep positions 1...n
// with no gaps under concurrent inserts/removals/moves), so this conformance isn't used
// internally, but is provided as general-purpose plumbing per spec.

extension QueueEntry: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "queue"

    public nonisolated init(row: Row) throws {
        self.init(
            episodeID: try StoredUUID.decode(row["episodeID"], column: "episodeID"),
            position: row["position"]
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["episodeID"] = episodeID.uuidString
        container["position"] = position
    }
}

// MARK: - Download (table: downloads)

extension DownloadState: DatabaseValueConvertible {}

extension Download: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "downloads"

    public nonisolated init(row: Row) throws {
        self.init(
            episodeID: try StoredUUID.decode(row["episodeID"], column: "episodeID"),
            relativePath: row["relativePath"],
            byteCount: row["byteCount"],
            state: row["state"],
            updatedAt: row["updatedAt"] ?? Date()
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["episodeID"] = episodeID.uuidString
        container["relativePath"] = relativePath
        container["byteCount"] = byteCount
        container["state"] = state
        container["updatedAt"] = updatedAt
    }
}

// MARK: - Playlist (table: playlists)

extension PlaylistRule: DatabaseValueConvertible {}

extension Playlist: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "playlists"

    public nonisolated init(row: Row) throws {
        self.init(
            id: try StoredUUID.decode(row["id"], column: "id"),
            name: row["name"],
            rule: row["rule"]
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["name"] = name
        container["rule"] = rule
    }
}
