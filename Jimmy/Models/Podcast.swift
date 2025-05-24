import Foundation

struct Podcast: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var author: String
    var description: String = ""
    var feedURL: URL
    var artworkURL: URL?
    var autoAddToQueue: Bool = false
    var notificationsEnabled: Bool = false
    // Add more properties as needed
} 