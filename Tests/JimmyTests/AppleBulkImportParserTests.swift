import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

final class AppleBulkImportParserTests: XCTestCase {
    func testParsing() throws {
        let json = """
        [
            {"title":"Show","feedUrl":"https://example.com/feed","author":"Me"}
        ]
        """
        let data = json.data(using: .utf8)!
        let podcasts = try AppleBulkImportParser.parse(data: data)
        XCTAssertEqual(podcasts.first?.title, "Show")
    }

    func testEmptyArrayReturnsEmpty() throws {
        let data = "[]".data(using: .utf8)!
        let podcasts = try AppleBulkImportParser.parse(data: data)
        XCTAssertTrue(podcasts.isEmpty)
    }

    func testMalformedJSONThrows() {
        let data = "{not valid json".data(using: .utf8)!
        XCTAssertThrowsError(try AppleBulkImportParser.parse(data: data))
    }

    func testMissingRequiredFeedURLFieldThrows() {
        // "feedUrl" is non-optional on ExportedPodcast, so a missing key fails decoding.
        let json = """
        [{"title":"Show"}]
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try AppleBulkImportParser.parse(data: data))
    }

    func testMissingOptionalAuthorDefaultsToEmptyString() throws {
        let json = """
        [{"title":"Show","feedUrl":"https://example.com/feed"}]
        """
        let data = json.data(using: .utf8)!
        let podcasts = try AppleBulkImportParser.parse(data: data)
        XCTAssertEqual(podcasts.first?.author, "")
    }

    func testInvalidFeedURLIsSilentlyDropped() throws {
        // Today: an entry whose feedUrl fails URL(string:) is dropped via compactMap,
        // rather than causing the whole import to fail.
        let json = """
        [
            {"title":"Bad","feedUrl":"","author":"X"},
            {"title":"Good","feedUrl":"https://example.com/feed","author":"Y"}
        ]
        """
        let data = json.data(using: .utf8)!
        let podcasts = try AppleBulkImportParser.parse(data: data)
        XCTAssertEqual(podcasts.count, 1)
        XCTAssertEqual(podcasts.first?.title, "Good")
    }

    func testDuplicateEntriesAreNotDeduplicated() throws {
        let json = """
        [
            {"title":"Show","feedUrl":"https://example.com/feed","author":"Me"},
            {"title":"Show","feedUrl":"https://example.com/feed","author":"Me"}
        ]
        """
        let data = json.data(using: .utf8)!
        let podcasts = try AppleBulkImportParser.parse(data: data)
        XCTAssertEqual(podcasts.count, 2)
    }
}
