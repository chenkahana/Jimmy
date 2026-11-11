import Foundation

/// Codable model shared between the main app and widget extension via App Group UserDefaults
struct WidgetData: Codable {
    let updatedAt: Date

    // Now Playing
    var nowPlayingTitle: String?
    var nowPlayingPodcast: String?
    var nowPlayingArtworkURL: URL?
    var nowPlayingProgress: Double?  // 0.0 - 1.0
    var nowPlayingDuration: TimeInterval?
    var nowPlayingPosition: TimeInterval?
    var isPlaying: Bool = false

    // Up Next (first 3 in queue)
    var upNext: [WidgetEpisode] = []

    // Continue Listening (in-progress episodes)
    var continueListening: [WidgetEpisode] = []
}

/// Lightweight episode representation for widgets
struct WidgetEpisode: Codable, Identifiable {
    let id: UUID
    let title: String
    let podcastTitle: String
    var artworkURL: URL?
    var progress: Double?  // 0.0 - 1.0
    var remainingTime: TimeInterval?
}
