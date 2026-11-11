import Foundation
import JimmyKit

/// `AppModel`'s conformance to `SuggestionsActions` — what the Suggestions screen calls
/// (`Jimmy/Suggestions/*`). `libraryPodcasts()`, `libraryEpisodes()`, and `playNow(_:)` are
/// already implemented in `AppModel+Assistant.swift` with the exact signatures this protocol
/// needs, and `subscribe(feedURL:)` in `AppModel+Library.swift` — so only the
/// Suggestions-specific reads and actions are added here.
extension AppModel: SuggestionsActions {
    func allProgress() async -> [JimmyKit.Progress] {
        guard let readyStore else { return [] }
        return (try? await readyStore.allProgress()) ?? []
    }

    func listeningStats() async -> [JimmyKit.ListeningStat] {
        guard let readyStore else { return [] }
        return (try? await readyStore.listeningStats()) ?? []
    }

    func queuedEpisodeIDs() -> Set<UUID> {
        Set(queueEpisodeIDs)
    }

    func queueEpisode(_ episode: JimmyKit.Episode) async {
        await enqueue(episode.id)
    }

    func searchPodcastsForSuggestions(query: String) async -> [SuggestedShowResult] {
        await iTunesSearchService.shared.searchPodcasts(query: query).map {
            SuggestedShowResult(title: $0.title, author: $0.author, feedURL: $0.feedURL, artworkURL: $0.artworkURL)
        }
    }
}
