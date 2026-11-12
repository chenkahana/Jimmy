import Foundation
import GRDB

/// Three orthogonal flags – can be combined (e.g., queued & played)
public nonisolated struct EpisodeStatus: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let played   = EpisodeStatus(rawValue: 1 << 0)
    public static let queued   = EpisodeStatus(rawValue: 1 << 1)
    public static let playing  = EpisodeStatus(rawValue: 1 << 2)
}

public nonisolated struct Episode: Identifiable, Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public let id: UUID
    public var title: String
    public var audioURL: URL?
    public var podcastID: UUID?
    public var publishedDate: Date?
    public var duration: TimeInterval?
    
    // Additional properties for compatibility
    public var artworkURL: URL?
    public var description: String?
    public var played: Bool = false
    public var isNew: Bool = true
    public var localFileURL: URL?
    public var playbackPosition: TimeInterval = 0
    public var lastFetched: Date?
    
    // NEW: Episode status indicators
    public var status: EpisodeStatus = []
    public var starred: Bool = false

    // Initializer with proper parameter order
    public init(
        id: UUID = UUID(),
        title: String,
        podcastID: UUID? = nil,
        publishedDate: Date? = nil,
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil,
        description: String? = nil,
        audioURL: URL? = nil,
        played: Bool = false,
        isNew: Bool = true,
        localFileURL: URL? = nil,
        playbackPosition: TimeInterval = 0,
        lastFetched: Date? = nil,
        status: EpisodeStatus = [],
        starred: Bool = false
    ) {
        self.id = id
        self.title = title
        self.podcastID = podcastID
        self.publishedDate = publishedDate
        self.duration = duration
        self.artworkURL = artworkURL
        self.description = description
        self.audioURL = audioURL
        self.played = played
        self.isNew = isNew
        self.localFileURL = localFileURL
        self.playbackPosition = playbackPosition
        self.lastFetched = lastFetched
        self.status = status
        self.starred = starred
    }

    // Codable implementation
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        audioURL = try container.decodeIfPresent(URL.self, forKey: .audioURL)
        podcastID = try container.decodeIfPresent(UUID.self, forKey: .podcastID)
        publishedDate = try container.decodeIfPresent(Date.self, forKey: .publishedDate)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        played = try container.decodeIfPresent(Bool.self, forKey: .played) ?? false
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew) ?? true
        localFileURL = try container.decodeIfPresent(URL.self, forKey: .localFileURL)
        playbackPosition = try container.decodeIfPresent(TimeInterval.self, forKey: .playbackPosition) ?? 0
        lastFetched = try container.decodeIfPresent(Date.self, forKey: .lastFetched)
        status = try container.decodeIfPresent(EpisodeStatus.self, forKey: .status) ?? []
        starred = try container.decodeIfPresent(Bool.self, forKey: .starred) ?? false
    }

    public enum CodingKeys: String, CodingKey {
        case id, title, audioURL, podcastID, publishedDate, duration
        case artworkURL, description, played, isNew, localFileURL, playbackPosition
        case lastFetched, status, starred
    }
    
    // Custom encoding to ensure Codable conformance
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(audioURL, forKey: .audioURL)
        try container.encodeIfPresent(podcastID, forKey: .podcastID)
        try container.encodeIfPresent(publishedDate, forKey: .publishedDate)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(artworkURL, forKey: .artworkURL)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(played, forKey: .played)
        try container.encode(isNew, forKey: .isNew)
        try container.encodeIfPresent(localFileURL, forKey: .localFileURL)
        try container.encode(playbackPosition, forKey: .playbackPosition)
        try container.encodeIfPresent(lastFetched, forKey: .lastFetched)
        try container.encode(status, forKey: .status)
        try container.encode(starred, forKey: .starred)
    }
    
    // MARK: - Queue Tab Helper Properties
    
    /// Computed property for remaining playback time
    public var remainingTime: TimeInterval {
        guard let totalDuration = duration, totalDuration > 0 else { return 0 }
        return max(0, totalDuration - playbackPosition)
    }
    
    /// Formatted duration string (e.g., "45:30", "1:23:45")
    public var formattedDuration: String {
        guard let totalDuration = duration, totalDuration > 0 else { return "0:00" }
        return formatTime(totalDuration)
    }
    
    /// Formatted remaining time string (e.g., "30:15 left")
    public var formattedRemainingTime: String {
        let remaining = remainingTime
        guard remaining > 0 else { return "Finished" }
        return "\(formatTime(remaining)) left"
    }
    
    /// Share URL for the episode
    public var shareURL: URL? {
        // For now, return the audio URL if available, or create a placeholder
        return audioURL ?? URL(string: "https://jimmy.app/episode/\(id.uuidString)")
    }
    
    /// Helper to format time intervals into human-readable strings
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - GRDB Conformance
    
    public static let databaseTableName: String = "episodes"
    
    public enum Columns: String, ColumnExpression {
        case id, title, audioURL, podcastID, publishedDate, duration
        case artworkURL, description, played, isNew, localFileURL, playbackPosition
        case lastFetched, status, starred
    }
    
    public init(row: Row) {
        // Handle UUID that might be stored as Data or String
        if let uuidData = row[Columns.id] as? Data {
            // UUID stored as binary data (16 bytes)
            id = UUID(uuid: uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) })
        } else if let uuidString = row[Columns.id] as? String {
            // UUID stored as string
            id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            // Fallback to new UUID
            id = UUID()
        }
        
        title = row[Columns.title]
        audioURL = row[Columns.audioURL]
        
        // Handle podcastID UUID that might be stored as Data or String
        if let podcastUUIDData = row[Columns.podcastID] as? Data {
            // UUID stored as binary data (16 bytes)
            podcastID = UUID(uuid: podcastUUIDData.withUnsafeBytes { $0.load(as: uuid_t.self) })
        } else if let podcastUUIDString = row[Columns.podcastID] as? String {
            // UUID stored as string
            podcastID = UUID(uuidString: podcastUUIDString)
        } else {
            // Null or invalid value
            podcastID = nil
        }
        
        publishedDate = row[Columns.publishedDate]
        duration = row[Columns.duration]
        artworkURL = row[Columns.artworkURL]
        description = row[Columns.description]
        played = row[Columns.played]
        isNew = row[Columns.isNew]
        localFileURL = row[Columns.localFileURL]
        playbackPosition = row[Columns.playbackPosition]
        lastFetched = row[Columns.lastFetched]
        status = EpisodeStatus(rawValue: row[Columns.status] ?? 0)
        starred = row[Columns.starred] ?? false
    }
    
    public func encode(to container: inout PersistenceContainer) {
        // Store UUIDs as strings to ensure compatibility
        container[Columns.id] = id.uuidString
        container[Columns.title] = title
        container[Columns.audioURL] = audioURL
        container[Columns.podcastID] = podcastID?.uuidString
        container[Columns.publishedDate] = publishedDate
        container[Columns.duration] = duration
        container[Columns.artworkURL] = artworkURL
        container[Columns.description] = description
        container[Columns.played] = played
        container[Columns.isNew] = isNew
        container[Columns.localFileURL] = localFileURL
        container[Columns.playbackPosition] = playbackPosition
        container[Columns.lastFetched] = lastFetched
        container[Columns.status] = status.rawValue
        container[Columns.starred] = starred
    }
} 