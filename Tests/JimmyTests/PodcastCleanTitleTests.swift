import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

final class PodcastCleanTitleTests: XCTestCase {
    func testDuplicateRemoval() {
        let title = "The Joe Rogan Experience The Joe Rogan Experience"
        let clean = Podcast.processCleanTitle(from: title)
        XCTAssertEqual(clean, "The Joe Rogan Experience")
    }
}
