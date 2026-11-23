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

/// Shared by the app (which writes `WidgetData` and reloads) and the widget extension (which reads it).
enum WidgetShared {
    static let appGroupID = "group.com.chenkahana.jimmy"
    static let widgetDataKey = "jimmy.widgetData"
    static let nowPlayingKind = "com.chenkahana.Jimmy.NowPlaying"
    static let playPauseControlKind = "com.chenkahana.Jimmy.PlayPauseControl"

    static func load() -> WidgetData? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: widgetDataKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetData.self, from: data)
    }
}
