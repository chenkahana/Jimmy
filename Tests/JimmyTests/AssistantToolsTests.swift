import XCTest
@testable import Jimmy
import JimmyKit

/// Each tool's `call` should invoke the right `AssistantActions` method with the parsed
/// arguments — and `UnsubscribeTool`/`ClearQueueTool` must never act directly: they register a
/// confirmation and only `AssistantConfirmationBroker.confirmPending` performs the action.
@MainActor
final class AssistantToolsTests: XCTestCase {
    func testPlayEpisodeToolPlaysTheMatchingEpisode() async throws {
        let actions = FakeAssistantActions()
        let episode = JimmyKit.Episode.fixture(title: "The Daily: November 11")
        actions.episodesToReturn = [episode]
        let tool = PlayEpisodeTool(actions: actions)

        let result = try await tool.call(arguments: PlayEpisodeArguments(query: "Daily"))

        XCTAssertEqual(actions.playedEpisodes, [episode])
        XCTAssertTrue(result.contains(episode.title))
    }

    func testPlayEpisodeToolReportsNoMatchWithoutPlaying() async throws {
        let actions = FakeAssistantActions()
        let tool = PlayEpisodeTool(actions: actions)

        let result = try await tool.call(arguments: PlayEpisodeArguments(query: "Nonexistent Show"))

        XCTAssertTrue(actions.playedEpisodes.isEmpty)
        XCTAssertTrue(result.lowercased().contains("couldn't find"))
    }

    func testQueueEpisodeToolQueuesWithThePlayNextFlag() async throws {
        let actions = FakeAssistantActions()
        let episode = JimmyKit.Episode.fixture(title: "Episode 42")
        actions.episodesToReturn = [episode]
        let tool = QueueEpisodeTool(actions: actions)

        _ = try await tool.call(arguments: QueueEpisodeArguments(query: "Episode 42", playNext: true))

        XCTAssertEqual(actions.queuedEpisodes.count, 1)
        XCTAssertEqual(actions.queuedEpisodes.first?.episode, episode)
        XCTAssertEqual(actions.queuedEpisodes.first?.playNext, true)
    }

    func testQueueEpisodeToolAddsToTheEndWhenNotPlayNext() async throws {
        let actions = FakeAssistantActions()
        let episode = JimmyKit.Episode.fixture(title: "Episode 42")
        actions.episodesToReturn = [episode]
        let tool = QueueEpisodeTool(actions: actions)

        _ = try await tool.call(arguments: QueueEpisodeArguments(query: "Episode 42", playNext: false))

        XCTAssertEqual(actions.queuedEpisodes.first?.playNext, false)
    }

    func testSearchPodcastsToolListsTheResults() async throws {
        let actions = FakeAssistantActions()
        actions.searchResultsToReturn = [
            AssistantPodcastResult(title: "Radiolab", author: "WNYC", feedURL: URL(string: "https://example.com/radiolab")!)
        ]
        let tool = SearchPodcastsTool(actions: actions)

        let result = try await tool.call(arguments: SearchPodcastsArguments(query: "Radiolab"))

        XCTAssertTrue(result.contains("Radiolab"))
    }

    func testSearchPodcastsToolReportsNoResults() async throws {
        let actions = FakeAssistantActions()
        let tool = SearchPodcastsTool(actions: actions)

        let result = try await tool.call(arguments: SearchPodcastsArguments(query: "Nothing"))

        XCTAssertTrue(result.lowercased().contains("didn't find"))
    }

    func testSubscribeToolSubscribesToTheTopSearchMatch() async throws {
        let actions = FakeAssistantActions()
        let feedURL = URL(string: "https://example.com/feed")!
        actions.searchResultsToReturn = [AssistantPodcastResult(title: "Radiolab", author: "WNYC", feedURL: feedURL)]
        let tool = SubscribeTool(actions: actions)

        let result = try await tool.call(arguments: SubscribeArguments(show: "Radiolab"))

        XCTAssertEqual(actions.subscribedFeedURLs, [feedURL])
        XCTAssertTrue(result.contains("Radiolab"))
    }

    func testSubscribeToolReportsWhenSubscribingFails() async throws {
        let actions = FakeAssistantActions()
        let feedURL = URL(string: "https://example.com/feed")!
        actions.searchResultsToReturn = [AssistantPodcastResult(title: "Radiolab", author: "WNYC", feedURL: feedURL)]
        actions.subscribeError = FakeAssistantError()
        let tool = SubscribeTool(actions: actions)

        let result = try await tool.call(arguments: SubscribeArguments(show: "Radiolab"))

        XCTAssertTrue(actions.subscribedFeedURLs.isEmpty)
        XCTAssertTrue(result.lowercased().contains("couldn't subscribe"))
    }

    func testUnsubscribeToolRequestsConfirmationAndDoesNotActUntilConfirmed() async throws {
        let actions = FakeAssistantActions()
        let podcast = JimmyKit.Podcast.fixture(title: "Radiolab")
        actions.podcastsToReturn = [podcast]
        let confirmations = AssistantConfirmationBroker()
        let tool = UnsubscribeTool(actions: actions, confirmations: confirmations)

        let result = try await tool.call(arguments: UnsubscribeArguments(show: "Radiolab"))

        XCTAssertTrue(actions.unsubscribedPodcastIDs.isEmpty, "must not unsubscribe before confirmation")
        XCTAssertEqual(confirmations.pending, .unsubscribe(podcastID: podcast.id, podcastTitle: podcast.title))
        XCTAssertTrue(result.lowercased().contains("confirm"))

        await confirmations.confirmPending(using: actions)

        XCTAssertEqual(actions.unsubscribedPodcastIDs, [podcast.id])
        XCTAssertNil(confirmations.pending)
    }

    func testUnsubscribeToolReportsWhenNotSubscribed() async throws {
        let actions = FakeAssistantActions()
        let confirmations = AssistantConfirmationBroker()
        let tool = UnsubscribeTool(actions: actions, confirmations: confirmations)

        let result = try await tool.call(arguments: UnsubscribeArguments(show: "Nothing Subscribed"))

        XCTAssertNil(confirmations.pending)
        XCTAssertTrue(result.lowercased().contains("not subscribed"))
    }

    func testClearQueueToolRequestsConfirmationAndDoesNotActUntilConfirmed() async throws {
        let actions = FakeAssistantActions()
        let confirmations = AssistantConfirmationBroker()
        let tool = ClearQueueTool(confirmations: confirmations)

        let result = try await tool.call(arguments: ClearQueueArguments())

        XCTAssertEqual(actions.clearQueueCallCount, 0, "must not clear the queue before confirmation")
        XCTAssertEqual(confirmations.pending, .clearQueue)
        XCTAssertTrue(result.lowercased().contains("confirm"))

        await confirmations.confirmPending(using: actions)

        XCTAssertEqual(actions.clearQueueCallCount, 1)
        XCTAssertNil(confirmations.pending)
    }

    func testSleepTimerToolPassesMinutesOrNilForEndOfEpisode() async throws {
        let actions = FakeAssistantActions()
        let tool = SleepTimerTool(actions: actions)

        _ = try await tool.call(arguments: SleepTimerArguments(minutes: 20))
        _ = try await tool.call(arguments: SleepTimerArguments(minutes: nil))

        XCTAssertEqual(actions.sleepTimerMinutes, [20, nil])
    }

    func testWhatsPlayingToolReportsTheCurrentEpisode() async throws {
        let actions = FakeAssistantActions()
        actions.nowPlayingToReturn = JimmyKit.Episode.fixture(title: "Now Playing Episode")
        let tool = WhatsPlayingTool(actions: actions)

        let result = try await tool.call(arguments: WhatsPlayingArguments())

        XCTAssertTrue(result.contains("Now Playing Episode"))
    }

    func testWhatsPlayingToolReportsNothingPlaying() async throws {
        let actions = FakeAssistantActions()
        let tool = WhatsPlayingTool(actions: actions)

        let result = try await tool.call(arguments: WhatsPlayingArguments())

        XCTAssertTrue(result.lowercased().contains("nothing"))
    }
}
