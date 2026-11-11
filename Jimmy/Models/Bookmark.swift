import Foundation
import GRDB

/// A user-created bookmark at a specific timestamp in an episode
struct Bookmark: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    var id: UUID
    var episodeID: UUID
    var timestamp: TimeInterval
    var note: String
    var createdAt: Date

    static var databaseTableName: String = "bookmarks"

    enum Columns: String, ColumnExpression {
        case id, episodeID, timestamp, note, createdAt
    }

    init(id: UUID = UUID(), episodeID: UUID, timestamp: TimeInterval, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.episodeID = episodeID
        self.timestamp = timestamp
        self.note = note
        self.createdAt = createdAt
    }

    init(row: Row) {
        if let uuidString = row[Columns.id] as? String {
            id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            id = UUID()
        }
        if let epString = row[Columns.episodeID] as? String {
            episodeID = UUID(uuidString: epString) ?? UUID()
        } else {
            episodeID = UUID()
        }
        timestamp = row[Columns.timestamp]
        note = row[Columns.note]
        createdAt = row[Columns.createdAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.episodeID] = episodeID.uuidString
        container[Columns.timestamp] = timestamp
        container[Columns.note] = note
        container[Columns.createdAt] = createdAt
    }
}
