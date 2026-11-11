import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

final class GoogleTakeoutParserTests: XCTestCase {
    func testParsing() throws {
        let json = """
        {
            "subscriptions": [{"title":"Show","feedUrl":"https://example.com/feed"}]
        }
        """
        let data = json.data(using: .utf8)!
        let podcasts = try GoogleTakeoutParser.parse(data: data)
        XCTAssertEqual(podcasts.first?.feedURL.absoluteString, "https://example.com/feed")
    }

    func testEmptySubscriptionsArrayReturnsEmpty() throws {
        let json = """
        { "subscriptions": [] }
        """
        let data = json.data(using: .utf8)!
        let podcasts = try GoogleTakeoutParser.parse(data: data)
        XCTAssertTrue(podcasts.isEmpty)
    }

    func testMalformedJSONThrows() {
        let data = "{not valid json".data(using: .utf8)!
        XCTAssertThrowsError(try GoogleTakeoutParser.parse(data: data))
    }

    func testMissingSubscriptionsKeyThrows() {
        // "subscriptions" is non-optional on GoogleSubscriptions.
        let json = "{}"
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try GoogleTakeoutParser.parse(data: data))
    }

    func testMissingFeedUrlFieldThrows() {
        let json = """
        { "subscriptions": [{"title":"Show"}] }
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try GoogleTakeoutParser.parse(data: data))
    }

    func testInvalidFeedURLIsSilentlyDropped() throws {
        let json = """
        {
            "subscriptions": [
                {"title":"Bad","feedUrl":""},
                {"title":"Good","feedUrl":"https://example.com/feed"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let podcasts = try GoogleTakeoutParser.parse(data: data)
        XCTAssertEqual(podcasts.count, 1)
        XCTAssertEqual(podcasts.first?.title, "Good")
    }

    func testDuplicateFeedsAreNotDeduplicated() throws {
        let json = """
        {
            "subscriptions": [
                {"title":"Show","feedUrl":"https://example.com/feed"},
                {"title":"Show","feedUrl":"https://example.com/feed"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let podcasts = try GoogleTakeoutParser.parse(data: data)
        XCTAssertEqual(podcasts.count, 2)
    }
}
