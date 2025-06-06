#if !os(Linux)
import XCTest
@testable import Jimmy

final class EpisodeCacheStatsTests: XCTestCase {
    override func setUp() async throws {
        EpisodeCacheService.shared.clearAllCache()
    }

    func testGetCacheStatsCountsEntries() {
        let podcastID = UUID()
        let episode = Episode(id: UUID(), title: "Test", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: podcastID, publishedDate: nil, localFileURL: nil)
        EpisodeCacheService.shared.insertCache(episodes: [episode], for: podcastID)
        let stats = EpisodeCacheService.shared.getCacheStats()
        XCTAssertEqual(stats.totalPodcasts, 1)
        XCTAssertEqual(stats.freshEntries, 1)
        XCTAssertEqual(stats.expiredEntries, 0)
    }
}
#endif
