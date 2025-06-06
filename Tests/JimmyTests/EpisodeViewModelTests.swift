#if !os(Linux)
import XCTest
@testable import Jimmy

final class EpisodeViewModelTests: XCTestCase {
    override func setUp() async throws {
        EpisodeViewModel.shared.clearAllEpisodes()
    }

    func testAddEpisodesDeduplicatesByTitle() {
        let podcastID = UUID()
        let e1 = Episode(id: UUID(), title: "Ep", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: podcastID, publishedDate: nil, localFileURL: nil)
        let e2 = Episode(id: UUID(), title: "Ep", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: podcastID, publishedDate: nil, localFileURL: nil)

        EpisodeViewModel.shared.addEpisodes([e1])
        EpisodeViewModel.shared.addEpisodes([e2])

        let episodes = EpisodeViewModel.shared.getEpisodes(for: podcastID)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.id, e1.id)
    }

    func testMarkAllEpisodesAsPlayed() {
        let podcastID = UUID()
        let e1 = Episode(id: UUID(), title: "A", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: podcastID, publishedDate: nil, localFileURL: nil)
        let e2 = Episode(id: UUID(), title: "B", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: podcastID, publishedDate: nil, localFileURL: nil)

        EpisodeViewModel.shared.addEpisodes([e1, e2])
        EpisodeViewModel.shared.markAllEpisodesAsPlayed(for: podcastID)

        let playedCount = EpisodeViewModel.shared.getPlayedEpisodesCount(for: podcastID)
        XCTAssertEqual(playedCount, 2)
    }
}
#endif
