import JimmyKit
import XCTest
@testable import Jimmy

/// The pure mapping `AppModel+CarPlay.swift` adds for `CarPlayManager`: `queue`/`podcasts` data in,
/// template row titles/subtitles out. No store, no `AppModel` instance — these are plain functions
/// of their arguments.
@MainActor
final class AppModelCarPlayTests: XCTestCase {
    private func makePodcast(title: String = "Show", author: String = "Author") -> JimmyKit.Podcast {
        JimmyKit.Podcast(title: title, cleanTitle: title, author: author, feedURL: URL(string: "https://example.com/\(title).xml")!)
    }

    private func makeEpisode(
        title: String = "Episode",
        podcastID: UUID? = nil,
        duration: TimeInterval? = nil
    ) -> JimmyKit.Episode {
        JimmyKit.Episode(podcastID: podcastID, title: title, duration: duration)
    }

    // MARK: - Queue rows

    func testQueueRowsUseTheEpisodesPodcastTitleAsSubtitle() {
        let podcast = makePodcast(title: "Daily News")
        let episode = makeEpisode(title: "Today", podcastID: podcast.id)

        let rows = AppModel.carPlayQueueRows(queue: [episode], podcasts: [podcast])

        XCTAssertEqual(rows, [AppModel.CarPlayEpisodeRow(episode: episode, title: "Today", subtitle: "Daily News")])
    }

    func testQueueRowSubtitleIsBlankWhenThePodcastIsntInThePodcastsList() {
        let episode = makeEpisode(title: "Orphaned", podcastID: UUID())

        let rows = AppModel.carPlayQueueRows(queue: [episode], podcasts: [])

        XCTAssertEqual(rows, [AppModel.CarPlayEpisodeRow(episode: episode, title: "Orphaned", subtitle: "")])
    }

    func testQueueRowsPreserveQueueOrder() {
        let first = makeEpisode(title: "First")
        let second = makeEpisode(title: "Second")

        let rows = AppModel.carPlayQueueRows(queue: [first, second], podcasts: [])

        XCTAssertEqual(rows.map(\.title), ["First", "Second"])
    }

    // MARK: - Library rows

    func testLibraryRowsUseTitleAndAuthor() {
        let podcast = makePodcast(title: "Tech Talk", author: "Jane Host")

        let rows = AppModel.carPlayLibraryRows(podcasts: [podcast])

        XCTAssertEqual(rows, [AppModel.CarPlayPodcastRow(podcast: podcast, title: "Tech Talk", subtitle: "Jane Host")])
    }

    // MARK: - Episode rows (a podcast's episode list)

    func testEpisodeRowsUseFormattedDurationAsSubtitle() {
        let episode = makeEpisode(title: "Long One", duration: 3_900)

        let rows = AppModel.carPlayEpisodeRows([episode])

        XCTAssertEqual(rows, [AppModel.CarPlayEpisodeRow(episode: episode, title: "Long One", subtitle: "1 hr 5 min")])
    }

    func testEpisodeRowSubtitleIsBlankWithoutADuration() {
        let episode = makeEpisode(title: "No Duration", duration: nil)

        let rows = AppModel.carPlayEpisodeRows([episode])

        XCTAssertEqual(rows.first?.subtitle, "")
    }

    // MARK: - Duration formatting

    func testDurationFormattingUnderAnHour() {
        XCTAssertEqual(AppModel.carPlayDuration(12 * 60), "12 min")
    }

    func testDurationFormattingExactlyOneHour() {
        XCTAssertEqual(AppModel.carPlayDuration(60 * 60), "1 hr 0 min")
    }

    func testDurationFormattingOverAnHour() {
        XCTAssertEqual(AppModel.carPlayDuration(65 * 60), "1 hr 5 min")
    }

    func testDurationFormattingIsBlankForNilOrZero() {
        XCTAssertEqual(AppModel.carPlayDuration(nil), "")
        XCTAssertEqual(AppModel.carPlayDuration(0), "")
    }
}
