import Foundation

struct Podcast: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var author: String
    var description: String = ""
    var feedURL: URL
    var artworkURL: URL?
    var autoAddToQueue: Bool = false
    var notificationsEnabled: Bool = false
    var lastEpisodeDate: Date? = nil
    // Add more properties as needed
} 