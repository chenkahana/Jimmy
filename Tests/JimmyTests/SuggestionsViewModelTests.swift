import XCTest
@testable import Jimmy
import JimmyKit

/// `SuggestionsViewModel.load()` ranks both lists from `actions`, builds a plain reason for every
/// item, and — only when a `SuggestionsModelSession` is given — asks it for a sharper reason on
/// the top items instead.
@MainActor
final class SuggestionsViewModelTests: XCTestCase {
    func testLoadRanksUpNextFromFinishedShowHistory() async {
        let actions = FakeSuggestionsActions()
        let show = JimmyKit.Podcast.fixture(title: "Hard Fork")
        let finishedEpisode = JimmyKit.Episode.fixture(title: "Finished", podcastID: show.id)
        let candidate = JimmyKit.Episode.fixture(title: "Candidate", podcastID: show.id)
        actions.podcastsToReturn = [show]
        actions.episodesToReturn = [finishedEpisode, candidate]
        actions.progressToReturn = [JimmyKit.Progress(episodeID: finishedEpisode.id, position: 100, isFinished: true)]

        let viewModel = SuggestionsViewModel(actions: actions, availability: .available, session: nil)
        await viewModel.load()

        XCTAssertEqual(viewModel.upNext.count, 1)
        guard case .episode(let episode, let showTitle) = viewModel.upNext.first?.kind else {
            return XCTFail("expected an episode item")
        }
        XCTAssertEqual(episode.id, candidate.id)
        XCTAssertEqual(showTitle, "Hard Fork")
        XCTAssertTrue(viewModel.upNext.first?.reason.contains("Hard Fork") ?? false)
    }

    func testLoadExcludesQueuedEpisodesFromUpNext() async {
        let actions = FakeSuggestionsActions()
        let show = JimmyKit.Podcast.fixture(title: "Show")
        let queued = JimmyKit.Episode.fixture(title: "Queued", podcastID: show.id)
        let candidate = JimmyKit.Episode.fixture(title: "Candidate", podcastID: show.id)
        actions.podcastsToReturn = [show]
        actions.episodesToReturn = [queued, candidate]
        actions.queuedIDsToReturn = [queued.id]

        let viewModel = SuggestionsViewModel(actions: actions, availability: .available, session: nil)
        await viewModel.load()

        let ids: [UUID] = viewModel.upNext.compactMap { item in
            if case .episode(let episode, _) = item.kind { return episode.id }
            return nil
        }
        XCTAssertEqual(ids, [candidate.id])
    }

    func testLoadSeedsNewShowsFromTheMostFinishedShowsAuthor() async {
        let actions = FakeSuggestionsActions()
        let finishedShow = JimmyKit.Podcast.fixture(title: "Finished Show") // author defaults to "Fixture Author"
        let finishedEpisode = JimmyKit.Episode.fixture(title: "F", podcastID: finishedShow.id)
        actions.podcastsToReturn = [finishedShow]
        actions.episodesToReturn = [finishedEpisode]
        actions.progressToReturn = [JimmyKit.Progress(episodeID: finishedEpisode.id, position: 100, isFinished: true)]
        let newShow = SuggestedShowResult(
            title: "New Show", author: "Fixture Author", feedURL: URL(string: "https://example.com/new")!, artworkURL: nil
        )
        actions.searchResultsByQuery["Fixture Author"] = [newShow]

        let viewModel = SuggestionsViewModel(actions: actions, availability: .available, session: nil)
        await viewModel.load()

        XCTAssertEqual(actions.searchedQueries, ["Fixture Author"])
        XCTAssertEqual(viewModel.newShows.count, 1)
        guard case .show(let show) = viewModel.newShows.first?.kind else {
            return XCTFail("expected a show item")
        }
        XCTAssertEqual(show.feedURL, newShow.feedURL)
    }

    func testNewShowsExcludesAlreadySubscribedFeeds() async {
        let actions = FakeSuggestionsActions()
        let finishedShow = JimmyKit.Podcast.fixture(title: "Finished Show")
        let subscribedShow = JimmyKit.Podcast.fixture(title: "Subscribed Show", feedURL: URL(string: "https://example.com/subscribed")!)
        let finishedEpisode = JimmyKit.Episode.fixture(title: "F", podcastID: finishedShow.id)
        actions.podcastsToReturn = [finishedShow, subscribedShow]
        actions.episodesToReturn = [finishedEpisode]
        actions.progressToReturn = [JimmyKit.Progress(episodeID: finishedEpisode.id, position: 100, isFinished: true)]
        let alreadySubscribed = SuggestedShowResult(
            title: "Subscribed Show", author: "Fixture Author", feedURL: subscribedShow.feedURL, artworkURL: nil
        )
        actions.searchResultsByQuery["Fixture Author"] = [alreadySubscribed]

        let viewModel = SuggestionsViewModel(actions: actions, availability: .available, session: nil)
        await viewModel.load()

        XCTAssertTrue(viewModel.newShows.isEmpty)
    }

    func testModelSessionOverridesThePlainReasonForTopItems() async {
        let actions = FakeSuggestionsActions()
        let show = JimmyKit.Podcast.fixture(title: "Show")
        let finishedEpisode = JimmyKit.Episode.fixture(title: "F", podcastID: show.id)
        let candidate = JimmyKit.Episode.fixture(title: "Candidate", podcastID: show.id)
        actions.podcastsToReturn = [show]
        actions.episodesToReturn = [finishedEpisode, candidate]
        actions.progressToReturn = [JimmyKit.Progress(episodeID: finishedEpisode.id, position: 100, isFinished: true)]
        let session = FakeSuggestionsModelSession()
        session.reasonToReturn = "Model-written reason"

        let viewModel = SuggestionsViewModel(actions: actions, availability: .available, session: session)
        await viewModel.load()

        XCTAssertEqual(viewModel.upNext.first?.reason, "Model-written reason")
        XCTAssertFalse(session.prompts.isEmpty)
    }

    func testAModelErrorLeavesThePlainReasonInPlace() async {
        let actions = FakeSuggestionsActions()
        let show = JimmyKit.Podcast.fixture(title: "Show")
        let candidate = JimmyKit.Episode.fixture(title: "Candidate", podcastID: show.id)
        actions.podcastsToReturn = [show]
        actions.episodesToReturn = [candidate]
        let session = FakeSuggestionsModelSession()
        session.errorToThrow = FakeSuggestionsError()

        let viewModel = SuggestionsViewModel(actions: actions, availability: .available, session: session)
        await viewModel.load()

        XCTAssertFalse(viewModel.upNext.first?.reason.isEmpty ?? true)
        XCTAssertNotEqual(viewModel.upNext.first?.reason, "Model-written reason")
    }

    func testUnavailableNoteReflectsTheAvailabilityReason() {
        let viewModel = SuggestionsViewModel(
            actions: FakeSuggestionsActions(),
            availability: .unavailable(reason: "Turn on Apple Intelligence"),
            session: nil
        )

        XCTAssertEqual(viewModel.unavailableNote, "Turn on Apple Intelligence")
    }

    func testAvailableHasNoUnavailableNote() {
        let viewModel = SuggestionsViewModel(actions: FakeSuggestionsActions(), availability: .available, session: nil)

        XCTAssertNil(viewModel.unavailableNote)
    }
}
