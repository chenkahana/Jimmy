import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

final class SpotifyListParserTests: XCTestCase {
    func testParsingURLs() {
        let text = "https://example.com/feed1\nhttps://example.com/feed2\n"
        let data = text.data(using: .utf8)!
        let urls = SpotifyListParser.parse(data: data)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].absoluteString, "https://example.com/feed1")
    }

    func testEmptyInputReturnsEmptyArray() {
        let urls = SpotifyListParser.parse(data: Data())
        XCTAssertTrue(urls.isEmpty)
    }

    func testBlankAndWhitespaceOnlyLinesAreSkipped() {
        let text = "https://example.com/feed1\n\n   \nhttps://example.com/feed2\n"
        let urls = SpotifyListParser.parse(data: Data(text.utf8))
        XCTAssertEqual(urls.count, 2)
    }

    func testLinesThatFailURLParsingAreDropped() {
        // Today: URL(string:) is lenient about plain text (e.g. unescaped spaces get
        // percent-encoded rather than rejected), but a malformed scheme plus a space still
        // fails to parse, and that line is silently dropped via compactMap rather than
        // causing a failure for the whole list.
        let text = "ht!tp://exa mple.com\nhttps://example.com/feed1\n"
        let urls = SpotifyListParser.parse(data: Data(text.utf8))
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].absoluteString, "https://example.com/feed1")
    }

    func testDuplicateLinesAreNotDeduplicated() {
        let text = "https://example.com/feed1\nhttps://example.com/feed1\n"
        let urls = SpotifyListParser.parse(data: Data(text.utf8))
        XCTAssertEqual(urls.count, 2)
    }
}
