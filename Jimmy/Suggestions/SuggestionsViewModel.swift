import Foundation
import JimmyKit

/// One row the Suggestions screen shows — either an unplayed episode ("up next") or a show to
/// subscribe to ("new shows like yours") — with the reason text the view displays underneath it.
/// `reason` starts as a plain sentence built from the ranking signals and is replaced with the
/// model's sharper one-liner when `SuggestionsModelSession` is available (see
/// `SuggestionsViewModel.load()`).
struct SuggestionItem: Identifiable {
    enum Kind {
        case episode(JimmyKit.Episode, showTitle: String)
        case show(SuggestedShowResult)
    }

    let id: String
    let kind: Kind
    var reason: String
}

/// Drives the Suggestions screen: ranks "up next" and "new shows like yours" from `actions`'
/// listening history (`SuggestionsRanker`, in JimmyKit), then — when the on-device model is
/// available — asks `session` for a sharper one-line reason on the top 5 of each list. When it
/// isn't, `unavailableNote` explains why and every item keeps its plain, signal-based reason.
@MainActor
@Observable
final class SuggestionsViewModel {
    private(set) var upNext: [SuggestionItem] = []
    private(set) var newShows: [SuggestionItem] = []
    private(set) var isLoading = true
    let availability: AssistantAvailability

    /// How many of each list's top items get a model-written reason instead of the plain one.
    private static let reasonedItemCount = 5

    private let actions: SuggestionsActions
    private let session: SuggestionsModelSession?

    var unavailableNote: String? {
        guard case .unavailable(let reason) = availability else { return nil }
        return reason
    }

    init(actions: SuggestionsActions, availability: AssistantAvailability, session: SuggestionsModelSession?) {
        self.actions = actions
        self.availability = availability
        self.session = session
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let podcastsTask = actions.libraryPodcasts()
        async let episodesTask = actions.libraryEpisodes()
        async let progressTask = actions.allProgress()
        async let statsTask = actions.listeningStats()
        let podcasts = await podcastsTask
        let episodes = await episodesTask
        let progress = await progressTask
        let stats = await statsTask

        let podcastTitlesByID = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.id, $0.cleanTitle) })

        let upNextCandidates = SuggestionsRanker.rankUpNext(
            episodes: episodes,
            podcasts: podcasts,
            progress: progress,
            listeningStats: stats,
            excluding: actions.queuedEpisodeIDs(),
            limit: 10
        )
        var upNextItems = upNextCandidates.map { candidate -> SuggestionItem in
            let showTitle = podcastTitlesByID[candidate.podcastID] ?? "this show"
            return SuggestionItem(
                id: "episode-\(candidate.episode.id.uuidString)",
                kind: .episode(candidate.episode, showTitle: showTitle),
                reason: Self.plainReason(for: candidate, showTitle: showTitle)
            )
        }

        let seeds = SuggestionsRanker.seedQueries(podcasts: podcasts, episodes: episodes, progress: progress, limit: 3)
        var newShowItems: [SuggestionItem] = []
        var seedByShow: [URL: String] = [:]
        if !seeds.isEmpty {
            var resultsBySeed: [[SuggestedShowResult]] = []
            for seed in seeds {
                let results = await actions.searchPodcastsForSuggestions(query: seed)
                resultsBySeed.append(results)
                for result in results where seedByShow[result.feedURL] == nil {
                    seedByShow[result.feedURL] = seed
                }
            }
            let subscribedFeedURLs = Set(podcasts.map(\.feedURL))
            let shows = NewShowsRanker.rank(resultsBySeed: resultsBySeed, subscribedFeedURLs: subscribedFeedURLs, limit: 10)
            newShowItems = shows.map { show in
                let seed = seedByShow[show.feedURL] ?? seeds[0]
                return SuggestionItem(
                    id: "show-\(show.feedURL.absoluteString)",
                    kind: .show(show),
                    reason: Self.plainReason(for: show, seed: seed)
                )
            }
        }

        if let session {
            for index in upNextItems.indices.prefix(Self.reasonedItemCount) {
                guard case .episode(let episode, let showTitle) = upNextItems[index].kind else { continue }
                let candidate = upNextCandidates[index]
                let prompt = Self.prompt(forEpisode: episode, showTitle: showTitle, candidate: candidate)
                if let reason = try? await session.reason(for: prompt) {
                    upNextItems[index].reason = reason
                }
            }
            for index in newShowItems.indices.prefix(Self.reasonedItemCount) {
                guard case .show(let show) = newShowItems[index].kind else { continue }
                let seed = seedByShow[show.feedURL] ?? seeds.first ?? ""
                if let reason = try? await session.reason(for: Self.prompt(forShow: show, seed: seed)) {
                    newShowItems[index].reason = reason
                }
            }
        }

        upNext = upNextItems
        newShows = newShowItems
    }

    // MARK: - Plain reasons (always computed; shown as-is when the model is unavailable)

    private static func plainReason(for candidate: UpNextSuggestion, showTitle: String) -> String {
        if candidate.isInProgress {
            return "Picking up where you left off in \(showTitle)."
        }
        if candidate.finishedCountForShow > 0 {
            let episodeWord = candidate.finishedCountForShow == 1 ? "episode" : "episodes"
            return "Because you've finished \(candidate.finishedCountForShow) \(episodeWord) of \(showTitle)."
        }
        return "From \(showTitle), in your library."
    }

    private static func plainReason(for show: SuggestedShowResult, seed: String) -> String {
        "Because you listen to \(seed)."
    }

    // MARK: - Model prompts

    private static func prompt(forEpisode episode: JimmyKit.Episode, showTitle: String, candidate: UpNextSuggestion) -> String {
        var signals = ["you've finished \(candidate.finishedCountForShow) episode(s) of \"\(showTitle)\""]
        if candidate.isInProgress {
            signals.append("you already started this exact episode but haven't finished it")
        }
        return """
            Episode: "\(episode.title)" from the show "\(showTitle)".
            Listening signals: \(signals.joined(separator: "; ")).
            Write one short reason this episode is suggested next.
            """
    }

    private static func prompt(forShow show: SuggestedShowResult, seed: String) -> String {
        """
        Show: "\(show.title)" by \(show.author).
        Listening signal: found by searching for "\(seed)", one of the people/shows this listener finishes most often.
        Write one short reason this new show is suggested.
        """
    }
}
