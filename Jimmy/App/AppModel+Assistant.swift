import Foundation
import JimmyKit

/// `AppModel`'s conformance to `AssistantActions` — what the on-device assistant's tools call
/// (`Jimmy/Assistant/AssistantTools.swift`). Kept in its own extension so tests can fake
/// `AssistantActions` instead of spinning up a real `AppModel`/`Store`/network call.
///
/// `subscribe`/`unsubscribe` go through the legacy `PodcastService` — PR 17 adds JimmyKit's
/// library API (`podcasts`, `subscribe(feedURL:)`, `unsubscribe(_:)`, `refreshAll()`) to `AppModel`
/// in `AppModel+Library.swift`; once that lands, these two bodies become one-line forwards to it.
extension AppModel: AssistantActions {
    private var assistantStore: Store? {
        guard case .ready(let ready) = launchState else { return nil }
        return ready.store
    }

    func libraryPodcasts() async -> [JimmyKit.Podcast] {
        guard let assistantStore else { return [] }
        return (try? await assistantStore.podcasts()) ?? []
    }

    func libraryEpisodes() async -> [JimmyKit.Episode] {
        guard let assistantStore else { return [] }
        let podcasts = (try? await assistantStore.podcasts()) ?? []
        var episodes: [JimmyKit.Episode] = []
        for podcast in podcasts {
            episodes.append(contentsOf: (try? await assistantStore.episodes(podcastID: podcast.id)) ?? [])
        }
        return episodes
    }

    func playNow(_ episode: JimmyKit.Episode) async {
        await play(episode)
    }

    func queueEpisode(_ episode: JimmyKit.Episode, playNext: Bool) async {
        if playNext {
            await self.playNext(episode.id)
        } else {
            await enqueue(episode.id)
        }
    }

    func currentQueue() -> [JimmyKit.Episode] {
        queue
    }

    func nowPlayingEpisode() -> JimmyKit.Episode? {
        playback?.currentEpisode
    }

    func searchApplePodcasts(query: String) async -> [AssistantPodcastResult] {
        await iTunesSearchService.shared.searchPodcasts(query: query).map {
            AssistantPodcastResult(title: $0.title, author: $0.author, feedURL: $0.feedURL)
        }
    }

    // PR 17 replaces this with a forward to JimmyKit's `AppModel.subscribe(feedURL:)`.
    func subscribe(feedURL: URL) async throws {
        _ = try await PodcastService.shared.addPodcast(from: feedURL)
    }

    // PR 17 replaces this with a forward to JimmyKit's `AppModel.unsubscribe(_:)`.
    func unsubscribe(_ podcastID: UUID) async throws {
        try await PodcastService.shared.removePodcast(id: podcastID)
    }

    func setSleepTimer(minutes: Int?) {
        guard let playback else { return }
        if let minutes {
            playback.startSleepTimer(.duration(TimeInterval(minutes * 60)))
        } else {
            playback.startSleepTimer(.endOfEpisode)
        }
    }
}
