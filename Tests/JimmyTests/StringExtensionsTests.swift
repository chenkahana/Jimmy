import XCTest
@testable import JimmyUtilities

final class StringExtensionsTests: XCTestCase {
    func testCleanedEpisodeDescription() {
        let html = "<p>Hello &amp; welcome to <b>the show</b>!\n</p>"
        let cleaned = html.cleanedEpisodeDescription
        XCTAssertEqual(cleaned, "Hello & welcome to the show!")
    }
}
