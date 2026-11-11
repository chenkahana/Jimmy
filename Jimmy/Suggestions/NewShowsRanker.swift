import Foundation

/// Merges "new shows like the ones you finish" search results from several seed queries (each
/// already ordered by Apple Podcasts' own relevance) into one list: round-robin across seeds so
/// no single seed crowds out the others, skipping anything already subscribed to and anything
/// already picked by an earlier seed. Pure and synchronous — the network call itself
/// (`SuggestionsActions.searchPodcastsForSuggestions`) happens before this runs.
enum NewShowsRanker {
    static func rank(
        resultsBySeed: [[SuggestedShowResult]],
        subscribedFeedURLs: Set<URL>,
        limit: Int = 10
    ) -> [SuggestedShowResult] {
        guard !resultsBySeed.isEmpty else { return [] }

        var seen = subscribedFeedURLs
        var merged: [SuggestedShowResult] = []
        var cursors = Array(repeating: 0, count: resultsBySeed.count)

        while merged.count < limit {
            var pickedThisRound = false
            for seedIndex in resultsBySeed.indices {
                guard merged.count < limit else { break }
                let seedResults = resultsBySeed[seedIndex]
                while cursors[seedIndex] < seedResults.count {
                    let candidate = seedResults[cursors[seedIndex]]
                    cursors[seedIndex] += 1
                    guard !seen.contains(candidate.feedURL) else { continue }
                    seen.insert(candidate.feedURL)
                    merged.append(candidate)
                    pickedThisRound = true
                    break
                }
            }
            guard pickedThisRound else { break }
        }

        return merged
    }
}
