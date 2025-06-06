import Foundation

struct Episode: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artworkURL: URL?
    var audioURL: URL?
    var description: String?
    var played: Bool = false
    var podcastID: UUID?
    var publishedDate: Date?
    var localFileURL: URL?
    var playbackPosition: TimeInterval = 0
    var duration: TimeInterval? // Duration of the episode in seconds - optional for backward compatibility
    
    // Computed property for easy access with default value
    var episodeDuration: TimeInterval {
        return duration ?? 0
    }
    
    // Add other necessary properties here
} 