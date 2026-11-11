import Foundation
import GRDB

public struct Podcast: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    public var id: UUID = UUID()
    public var title: String
    public var cleanTitle: String // Processed title with duplicates removed
    public var author: String
    public var description: String = ""
    public var feedURL: URL
    public var artworkURL: URL?
    public var autoAddToQueue: Bool = false
    public var notificationsEnabled: Bool = false
    public var lastEpisodeDate: Date? = nil
    public var etag: String?
    public var lastFetched: Date?
    
    public static var databaseTableName: String = "podcasts"
    
    public enum Columns: String, ColumnExpression {
        case id, title, cleanTitle, author, description, feedURL, artworkURL
        case autoAddToQueue, notificationsEnabled, lastEpisodeDate
        case etag, lastFetched
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        author: String,
        description: String = "",
        feedURL: URL,
        artworkURL: URL? = nil,
        autoAddToQueue: Bool = false,
        notificationsEnabled: Bool = false,
        lastEpisodeDate: Date? = nil,
        etag: String? = nil,
        lastFetched: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.cleanTitle = Self.processCleanTitle(from: title) // Auto-process clean title
        self.author = author
        self.description = description
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.autoAddToQueue = autoAddToQueue
        self.notificationsEnabled = notificationsEnabled
        self.lastEpisodeDate = lastEpisodeDate
        self.etag = etag
        self.lastFetched = lastFetched
    }
    
    public init(row: Row) {
        // UUIDs are stored as TEXT in the database, so always expect String
        if let uuidString = row[Columns.id] as? String {
            id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            // Fallback to new UUID if somehow not a string
            id = UUID()
        }
        
        title = row[Columns.title]
        // Safely handle cleanTitle column that might not exist in older database records
        if row.hasColumn(Columns.cleanTitle.rawValue) {
            cleanTitle = row[Columns.cleanTitle]
        } else {
            // Fallback: generate cleanTitle from title if column doesn't exist
            cleanTitle = Self.processCleanTitle(from: row[Columns.title])
        }
        author = row[Columns.author]
        description = row[Columns.description]
        feedURL = row[Columns.feedURL]
        artworkURL = row[Columns.artworkURL]
        autoAddToQueue = row[Columns.autoAddToQueue]
        notificationsEnabled = row[Columns.notificationsEnabled]
        lastEpisodeDate = row[Columns.lastEpisodeDate]
        etag = row[Columns.etag]
        lastFetched = row[Columns.lastFetched]
    }
    
    public func encode(to container: inout PersistenceContainer) {
        // Store UUID as string to ensure compatibility
        container[Columns.id] = id.uuidString
        container[Columns.title] = title
        container[Columns.cleanTitle] = cleanTitle
        container[Columns.author] = author
        container[Columns.description] = description
        container[Columns.feedURL] = feedURL
        container[Columns.artworkURL] = artworkURL
        container[Columns.autoAddToQueue] = autoAddToQueue
        container[Columns.notificationsEnabled] = notificationsEnabled
        container[Columns.lastEpisodeDate] = lastEpisodeDate
        container[Columns.etag] = etag
        container[Columns.lastFetched] = lastFetched
    }
    
    // MARK: - Clean Title Processing
    public static func processCleanTitle(from title: String) -> String {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the cleaned title is empty, return the original title
        guard !cleanedTitle.isEmpty else {
            return title
        }
        
        // Check for exact duplicate halves (like "The Joe Rogan Experience The Joe Rogan Experience")
        let words = cleanedTitle.components(separatedBy: " ")
        let halfCount = words.count / 2
        
        if words.count > 1 && words.count % 2 == 0 {
            let firstHalf = Array(words[0..<halfCount]).joined(separator: " ")
            let secondHalf = Array(words[halfCount..<words.count]).joined(separator: " ")
            
            if firstHalf == secondHalf && !firstHalf.isEmpty {
                return firstHalf
            }
        }
        
        // Enhanced duplicate detection for case-insensitive matches
        if words.count > 1 && words.count % 2 == 0 {
            let firstHalf = Array(words[0..<halfCount]).joined(separator: " ")
            let secondHalf = Array(words[halfCount..<words.count]).joined(separator: " ")
            
            if firstHalf.lowercased() == secondHalf.lowercased() && !firstHalf.isEmpty {
                return firstHalf
            }
        }
        
        // Check for pattern where title is repeated with slight variations or no space
        // Like "The Joe Rogan ExperienceThe Joe Rogan Experience" (no space)
        let lowercased = cleanedTitle.lowercased()
        let length = lowercased.count
        if length > 10 { // Only check for longer titles to avoid false positives
            let midPoint = length / 2
            let firstHalf = String(lowercased.prefix(midPoint))
            let secondHalf = String(lowercased.suffix(length - midPoint))
            
            if firstHalf == secondHalf {
                return String(cleanedTitle.prefix(midPoint))
            }
        }
        
        // Check for patterns like "Title Title" where the title is repeated exactly
        let titleComponents = cleanedTitle.components(separatedBy: " ")
        if titleComponents.count >= 4 { // At least 4 words to have meaningful duplicates
            let midPoint = titleComponents.count / 2
            let firstPart = Array(titleComponents[0..<midPoint]).joined(separator: " ")
            let secondPart = Array(titleComponents[midPoint..<titleComponents.count]).joined(separator: " ")
            
            // Check if the second half exactly matches the first half (case-insensitive)
            if firstPart.lowercased() == secondPart.lowercased() && !firstPart.isEmpty {
                return firstPart
            }
        }
        
        // Check for titles that are repeated with different patterns
        // Split by common separators and check for duplicates
        let separators = [" - ", " | ", " :: ", ": "]
        for separator in separators {
            let parts = cleanedTitle.components(separatedBy: separator)
            if parts.count == 2 && parts[0].lowercased() == parts[1].lowercased() {
                return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return cleanedTitle
    }
}

extension Podcast {
    /// Returns the canonical DB key string for a podcast UUID.
    static func dbKey(for id: UUID) -> String { id.uuidString.uppercased() }
} 