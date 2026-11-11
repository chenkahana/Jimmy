import Foundation
import GRDB

/// CRUD service for episode bookmarks
final class BookmarkService {
    static let shared = BookmarkService()
    private init() {}

    // MARK: - CRUD

    func addBookmark(episodeID: UUID, timestamp: TimeInterval, note: String = "") async throws -> Bookmark {
        let bookmark = Bookmark(episodeID: episodeID, timestamp: timestamp, note: note)
        try await DatabaseManager.shared.writeAsync { db in
            try bookmark.save(db)
        }
        return bookmark
    }

    func deleteBookmark(_ id: UUID) async throws {
        try await DatabaseManager.shared.writeAsync { db in
            try db.execute(sql: "DELETE FROM bookmarks WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func updateBookmarkNote(_ id: UUID, note: String) async throws {
        try await DatabaseManager.shared.writeAsync { db in
            try db.execute(sql: "UPDATE bookmarks SET note = ? WHERE id = ?", arguments: [note, id.uuidString])
        }
    }

    // MARK: - Queries

    func bookmarks(for episodeID: UUID) async throws -> [Bookmark] {
        try await DatabaseManager.shared.readAsync { db in
            try Bookmark
                .filter(Bookmark.Columns.episodeID == episodeID.uuidString)
                .order(Bookmark.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    func allBookmarks() async throws -> [Bookmark] {
        try await DatabaseManager.shared.readAsync { db in
            try Bookmark.order(Bookmark.Columns.createdAt.desc).fetchAll(db)
        }
    }

    func bookmarkCount(for episodeID: UUID) async throws -> Int {
        try await DatabaseManager.shared.readAsync { db in
            try Bookmark
                .filter(Bookmark.Columns.episodeID == episodeID.uuidString)
                .fetchCount(db)
        }
    }
}
