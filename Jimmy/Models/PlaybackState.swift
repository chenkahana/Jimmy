import Foundation
import GRDB

/// A struct to represent the playback state of an episode, conforming to GRDB requirements.
struct PlaybackState: Codable, Equatable, FetchableRecord, PersistableRecord {
    var episodeID: UUID
    var position: Double
    var finished: Bool
    var queuePosition: Int? // NULL means not in queue, 1 = first in queue
    var updatedAt: Date

    static var databaseTableName: String = "playback_state"
    
    // Define database columns
    enum Columns: String, ColumnExpression {
        case episodeID, position, finished, queuePosition, updatedAt
    }
    
    init(episodeID: UUID, position: Double, finished: Bool, queuePosition: Int? = nil, updatedAt: Date = Date()) {
        self.episodeID = episodeID
        self.position = position
        self.finished = finished
        self.queuePosition = queuePosition
        self.updatedAt = updatedAt
    }
    
    // GRDB initializers and encoders
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
        
        position = row[Columns.position]
        finished = row[Columns.finished]
        queuePosition = row[Columns.queuePosition]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        // Store UUID as string to ensure compatibility
        container[Columns.episodeID] = episodeID.uuidString
        container[Columns.position] = position
        container[Columns.finished] = finished
        container[Columns.queuePosition] = queuePosition
        container[Columns.updatedAt] = updatedAt
    }
} 