import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

final class ShowFetchSorterTests: XCTestCase {
    func testFetchAndSortOrdersByLatestDate() async {
        // Prepare sample podcasts
        let p1 = Podcast(id: UUID(), title: "A", author: "A", feedURL: URL(string: "https://a")!)
        let p2 = Podcast(id: UUID(), title: "B", author: "B", feedURL: URL(string: "https://b")!)
        let p3 = Podcast(id: UUID(), title: "C", author: "C", feedURL: URL(string: "https://c")!)

        // Pretend network fetcher returning specific dates
        let dates: [UUID: Date] = [
            p1.id: Date(timeIntervalSince1970: 100),
            p2.id: Date(timeIntervalSince1970: 300),
            p3.id: Date(timeIntervalSince1970: 200)
        ]

        var cache: [UUID: Date] = [:]
        let sorted = await ShowFetchSorter.fetchAndSort(podcasts: [p1, p2, p3], cache: &cache, maxConcurrent: 2) { podcast in
            return dates[podcast.id]
        }

        XCTAssertEqual(sorted.map { $0.id }, [p2.id, p3.id, p1.id])
    }

    func testFetchAndSortFallsBackToCache() async {
        let p1 = Podcast(id: UUID(), title: "A", author: "A", feedURL: URL(string: "https://a")!)
        let p2 = Podcast(id: UUID(), title: "B", author: "B", feedURL: URL(string: "https://b")!)

        var cache: [UUID: Date] = [
            p1.id: Date(timeIntervalSince1970: 100)
        ]

        let sorted = await ShowFetchSorter.fetchAndSort(podcasts: [p1, p2], cache: &cache) { podcast in
            // Simulate failure for p1, success for p2
            if podcast.id == p1.id {
                return nil
            }
            return Date(timeIntervalSince1970: 200)
        }

        // p2 should come before p1 because it has newer date
        XCTAssertEqual(sorted.map { $0.id }, [p2.id, p1.id])
        // Cache should still contain dates for both podcasts
        XCTAssertNotNil(cache[p1.id])
        XCTAssertNotNil(cache[p2.id])
    }
}
