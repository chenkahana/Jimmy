import Foundation
import GRDB

struct EpisodeDetail: Codable, Equatable, FetchableRecord, PersistableRecord {
    var episodeID: UUID
    var fullDescription: String
    var chaptersJSON: String? // Storing chapters as JSON string
    var updatedAt: Date

    static var databaseTableName: String = "episode_details"

    enum Columns: String, ColumnExpression {
        case episodeID, fullDescription, chaptersJSON, updatedAt
    }

    init(episodeID: UUID, fullDescription: String, chaptersJSON: String?, updatedAt: Date = Date()) {
        self.episodeID = episodeID
        self.fullDescription = fullDescription
        self.chaptersJSON = chaptersJSON
        self.updatedAt = updatedAt
    }

    init(row: Row) {
        // Handle UUID that might be stored as Data or String
        if let uuidData = row[Columns.episodeID] as? Data {
            // UUID stored as binary data (16 bytes)
            episodeID = UUID(uuid: uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) })
        } else if let uuidString = row[Columns.episodeID] as? String {
            // UUID stored as string
            episodeID = UUID(uuidString: uuidString) ?? UUID()
        } else {
            // Fallback to new UUID
            episodeID = UUID()
        }
        
        fullDescription = row[Columns.fullDescription]
        chaptersJSON = row[Columns.chaptersJSON]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        // Store UUID as string to ensure compatibility
        container[Columns.episodeID] = episodeID.uuidString
        container[Columns.fullDescription] = fullDescription
        container[Columns.chaptersJSON] = chaptersJSON
        container[Columns.updatedAt] = updatedAt
    }
} 