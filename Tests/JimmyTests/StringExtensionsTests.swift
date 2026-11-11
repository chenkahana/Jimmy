import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

final class StringExtensionsTests: XCTestCase {
    func testCleanedEpisodeDescription() {
        let raw = "<p>Hello &amp; welcome</p>"
        XCTAssertEqual(raw.cleanedEpisodeDescription, "Hello & welcome")
    }

    func testDateFromRFC822() {
        let dateString = "Wed, 02 Oct 2002 13:00:00 GMT"
        let date = String.date(fromRFC822: dateString)
        XCTAssertNotNil(date)
    }
}
