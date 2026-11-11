import Foundation
import Testing
@testable import JimmyKit

/// `SuggestionsRanker` is pure (no `Store`, no network) — everything here is plain fixtures and
/// a frozen `now`, so every signal (finish count, recency, in-progress, duration closeness) can
/// be isolated from the others.
struct SuggestionsRankingTests {
    private func podcast(author: String = "Author", title: String = "Show") -> Podcast {
        Podcast(
            title: title,
            cleanTitle: title,
            author: author,
            feedURL: URL(string: "https://example.com/\(title.replacingOccurrences(of: " ", with: "-"))")!
        )
    }

    private func finished(_ episode: Episode, updatedAt: Date = Date()) -> JimmyKit.Progress {
        JimmyKit.Progress(episodeID: episode.id, position: episode.duration ?? 1_800, duration: episode.duration, isFinished: true, updatedAt: updatedAt)
    }

    // MARK: - rankUpNext

    @Test func ranksShowsFinishedMostAboveShowsNeverFinished() {
        let finishedShow = podcast(title: "Finished Show")
        let freshShow = podcast(title: "Fresh Show")

        let finishedEpisodes = (0..<3).map { Episode(podcastID: finishedShow.id, title: "Finished \($0)", duration: 1_800) }
        let candidateFromFinishedShow = Episode(podcastID: finishedShow.id, title: "Candidate A", duration: 1_800)
        let candidateFromFreshShow = Episode(podcastID: freshShow.id, title: "Candidate B", duration: 1_800)

        let results = SuggestionsRanker.rankUpNext(
            episodes: finishedEpisodes + [candidateFromFinishedShow, candidateFromFreshShow],
            podcasts: [finishedShow, freshShow],
            progress: finishedEpisodes.map { finished($0) }
        )

        #expect(results.count == 2)
        #expect(results.first?.episode.id == candidateFromFinishedShow.id)
        #expect(results.first?.finishedCountForShow == 3)
    }

    @Test func recentlyFinishedShowRanksAboveOneFinishedLongAgo() {
        let now = Date()
        let recentShow = podcast(title: "Recent Show")
        let staleShow = podcast(title: "Stale Show")

        let recentFinished = Episode(podcastID: recentShow.id, title: "Recent Finished", duration: 1_800)
        let staleFinished = Episode(podcastID: staleShow.id, title: "Stale Finished", duration: 1_800)
        let candidateRecent = Episode(podcastID: recentShow.id, title: "Candidate Recent", duration: 1_800)
        let candidateStale = Episode(podcastID: staleShow.id, title: "Candidate Stale", duration: 1_800)

        let progress = [
            finished(recentFinished, updatedAt: now),
            finished(staleFinished, updatedAt: now.addingTimeInterval(-90 * 86_400)),
        ]

        let results = SuggestionsRanker.rankUpNext(
            episodes: [recentFinished, staleFinished, candidateRecent, candidateStale],
            podcasts: [recentShow, staleShow],
            progress: progress,
            now: now
        )

        let ids = results.map(\.episode.id)
        let recentIndex = ids.firstIndex(of: candidateRecent.id) ?? .max
        let staleIndex = ids.firstIndex(of: candidateStale.id) ?? .max
        #expect(recentIndex < staleIndex)
    }

    @Test func inProgressEpisodeOutranksAFreshEpisodeOfTheSameShow() {
        let show = podcast(title: "Show")
        let inProgressEpisode = Episode(podcastID: show.id, title: "In Progress", duration: 1_800)
        let freshEpisode = Episode(podcastID: show.id, title: "Fresh", duration: 1_800)

        let progress = [Progress(episodeID: inProgressEpisode.id, position: 600, duration: 1_800, isFinished: false)]

        let results = SuggestionsRanker.rankUpNext(episodes: [inProgressEpisode, freshEpisode], podcasts: [show], progress: progress)

        #expect(results.first?.episode.id == inProgressEpisode.id)
        #expect(results.first?.isInProgress == true)
    }

    @Test func prefersEpisodesCloseToTheUsualFinishedLength() {
        let show = podcast(title: "Show")
        let finishedEpisodes = (0..<2).map { Episode(podcastID: show.id, title: "Finished \($0)", duration: 1_800) }
        let closeCandidate = Episode(podcastID: show.id, title: "Close", duration: 1_900)
        let farCandidate = Episode(podcastID: show.id, title: "Far", duration: 7_200)

        let results = SuggestionsRanker.rankUpNext(
            episodes: finishedEpisodes + [closeCandidate, farCandidate],
            podcasts: [show],
            progress: finishedEpisodes.map { finished($0) }
        )

        let ids = results.map(\.episode.id)
        #expect((ids.firstIndex(of: closeCandidate.id) ?? .max) < (ids.firstIndex(of: farCandidate.id) ?? .max))
    }

    @Test func excludesFinishedAndExplicitlyExcludedEpisodes() {
        let show = podcast(title: "Show")
        let finishedEpisode = Episode(podcastID: show.id, title: "Finished", duration: 1_800)
        let queuedEpisode = Episode(podcastID: show.id, title: "Already Queued", duration: 1_800)
        let candidate = Episode(podcastID: show.id, title: "Candidate", duration: 1_800)

        let results = SuggestionsRanker.rankUpNext(
            episodes: [finishedEpisode, queuedEpisode, candidate],
            podcasts: [show],
            progress: [finished(finishedEpisode)],
            excluding: [queuedEpisode.id]
        )

        #expect(results.map(\.episode.id) == [candidate.id])
    }

    @Test func honorsTheLimit() {
        let show = podcast(title: "Show")
        let episodes = (0..<5).map { Episode(podcastID: show.id, title: "Episode \($0)", duration: 1_800) }

        let results = SuggestionsRanker.rankUpNext(episodes: episodes, podcasts: [show], progress: [], limit: 2)

        #expect(results.count == 2)
    }

    @Test func ignoresEpisodesWithNoPodcastID() {
        let orphan = Episode(podcastID: nil, title: "Orphan", duration: 1_800)

        let results = SuggestionsRanker.rankUpNext(episodes: [orphan], podcasts: [], progress: [])

        #expect(results.isEmpty)
    }

    // MARK: - seedQueries

    @Test func seedQueriesOrdersAuthorsByFinishedCount() {
        let showA = podcast(author: "Author A", title: "Show A")
        let showB = podcast(author: "Author B", title: "Show B")

        let aEpisodes = (0..<3).map { Episode(podcastID: showA.id, title: "A\($0)", duration: 1_800) }
        let bEpisodes = (0..<1).map { Episode(podcastID: showB.id, title: "B\($0)", duration: 1_800) }

        let seeds = SuggestionsRanker.seedQueries(
            podcasts: [showA, showB],
            episodes: aEpisodes + bEpisodes,
            progress: (aEpisodes + bEpisodes).map { finished($0) }
        )

        #expect(seeds == ["Author A", "Author B"])
    }

    @Test func seedQueriesSkipsShowsWithNoFinishedEpisodes() {
        let finishedShow = podcast(author: "Finished Author", title: "Finished Show")
        let neverFinishedShow = podcast(author: "Never Author", title: "Never Finished")

        let finishedEpisode = Episode(podcastID: finishedShow.id, title: "F", duration: 1_800)
        let neverEpisode = Episode(podcastID: neverFinishedShow.id, title: "N", duration: 1_800)

        let seeds = SuggestionsRanker.seedQueries(
            podcasts: [finishedShow, neverFinishedShow],
            episodes: [finishedEpisode, neverEpisode],
            progress: [finished(finishedEpisode)]
        )

        #expect(seeds == ["Finished Author"])
    }

    @Test func seedQueriesFallsBackToTitleWhenAuthorIsBlankAndDedupesCaseInsensitively() {
        let blankAuthorShow = podcast(author: "  ", title: "Blank Author Show")
        let showB = podcast(author: "Same Author", title: "Show B")
        let showC = podcast(author: "SAME AUTHOR", title: "Show C")

        let episodeA = Episode(podcastID: blankAuthorShow.id, title: "A", duration: 1_800)
        let episodeB = Episode(podcastID: showB.id, title: "B", duration: 1_800)
        let episodeC = Episode(podcastID: showC.id, title: "C", duration: 1_800)

        let seeds = SuggestionsRanker.seedQueries(
            podcasts: [blankAuthorShow, showB, showC],
            episodes: [episodeA, episodeB, episodeC],
            progress: [episodeA, episodeB, episodeC].map { finished($0) },
            limit: 5
        )

        #expect(seeds.contains("Blank Author Show"))
        #expect(seeds.filter { $0.lowercased() == "same author" }.count == 1)
    }

    @Test func seedQueriesRespectsTheLimit() {
        let shows = (0..<5).map { podcast(author: "Author \($0)", title: "Show \($0)") }
        let episodes = shows.map { Episode(podcastID: $0.id, title: "Ep", duration: 1_800) }

        let seeds = SuggestionsRanker.seedQueries(
            podcasts: shows,
            episodes: episodes,
            progress: episodes.map { finished($0) },
            limit: 3
        )

        #expect(seeds.count == 3)
    }
}
