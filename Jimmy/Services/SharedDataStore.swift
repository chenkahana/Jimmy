import Foundation

/// Writes WidgetData to App Group UserDefaults for cross-target sharing.
/// Used by the main app to push data to widget extensions.
final class SharedDataStore {
    static let shared = SharedDataStore()

    private let appGroupID = "group.com.chenkahana.jimmy"
    private let widgetDataKey = "jimmy.widgetData"

    private lazy var sharedDefaults: UserDefaults? = {
        UserDefaults(suiteName: appGroupID)
    }()

    private init() {}

    // MARK: - Write

    /// Update widget data from the current app state
    @MainActor
    func updateWidgetData() {
        let audioPlayer = AudioPlayerService.shared
        let queueVM = QueueViewModel.shared

        var data = WidgetData(updatedAt: Date())

        // Now Playing
        if let current = queueVM.currentEpisode {
            data.nowPlayingTitle = current.title
            let podcast = PodcastService.shared.loadPodcasts().first { $0.id == current.podcastID }
            data.nowPlayingPodcast = podcast?.title
            data.nowPlayingArtworkURL = current.artworkURL ?? podcast?.artworkURL
            data.nowPlayingDuration = current.duration
            data.nowPlayingPosition = current.playbackPosition
            if let duration = current.duration, duration > 0 {
                data.nowPlayingProgress = current.playbackPosition / duration
            }
            data.isPlaying = audioPlayer.isPlaying
        }

        // Up Next (first 3 queued episodes after current)
        let podcasts = PodcastService.shared.loadPodcasts()
        let queueEpisodes = Array(queueVM.episodes.prefix(3))
        data.upNext = queueEpisodes.map { episode in
            let podcast = podcasts.first { $0.id == episode.podcastID }
            return WidgetEpisode(
                id: episode.id,
                title: episode.title,
                podcastTitle: podcast?.title ?? "",
                artworkURL: episode.artworkURL ?? podcast?.artworkURL,
                progress: episode.duration.map { d in d > 0 ? episode.playbackPosition / d : nil } ?? nil,
                remainingTime: episode.remainingTime > 0 ? episode.remainingTime : nil
            )
        }

        // Continue Listening — in-progress episodes (position > 0, not finished)
        let inProgress = queueVM.episodes.filter { $0.playbackPosition > 0 && !$0.played }
        data.continueListening = Array(inProgress.prefix(3)).map { episode in
            let podcast = podcasts.first { $0.id == episode.podcastID }
            return WidgetEpisode(
                id: episode.id,
                title: episode.title,
                podcastTitle: podcast?.title ?? "",
                artworkURL: episode.artworkURL ?? podcast?.artworkURL,
                progress: episode.duration.map { d in d > 0 ? episode.playbackPosition / d : nil } ?? nil,
                remainingTime: episode.remainingTime > 0 ? episode.remainingTime : nil
            )
        }

        save(data)
    }

    // MARK: - Persistence

    private func save(_ data: WidgetData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(data) else { return }
        sharedDefaults?.set(encoded, forKey: widgetDataKey)
    }

    func load() -> WidgetData? {
        guard let data = sharedDefaults?.data(forKey: widgetDataKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetData.self, from: data)
    }
}
