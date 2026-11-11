import Foundation

struct PodcastMetadata: Codable, Equatable {
    var title: String?
    var author: String?
    var description: String?
    var artworkURL: URL?
} 