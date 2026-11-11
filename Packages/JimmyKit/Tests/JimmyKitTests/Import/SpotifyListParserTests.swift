import Foundation
import Testing
@testable import JimmyKit

/// Ported from `Tests/JimmyTests/SpotifyListParserTests.swift`, which pinned the app's
/// `SpotifyListParser.parse(data:)` as it behaved before this move. Assertions that the
/// move's deliberate improvements intentionally change are marked `// Changed from today: …`.
struct SpotifyListParserTests {
    @Test func parsingURLs() {
        let text = "https://example.com/feed1\nhttps://example.com/feed2\n"
        let data = Data(text.utf8)
        let result = SpotifyListParser.parse(data: data)
        #expect(result.feeds.count == 2)
        #expect(result.feeds[0].feedURL.absoluteString == "https://example.com/feed1")
        #expect(result.feeds[0].title == nil)
    }

    @Test func emptyInputReturnsEmptyResult() {
        let result = SpotifyListParser.parse(data: Data())
        #expect(result.feeds.isEmpty)
        #expect(result.skipped.isEmpty)
    }

    @Test func blankAndWhitespaceOnlyLinesAreSkipped() {
        let text = "https://example.com/feed1\n\n   \nhttps://example.com/feed2\n"
        let result = SpotifyListParser.parse(data: Data(text.utf8))
        #expect(result.feeds.count == 2)
    }

    @Test func linesThatFailURLParsingAreRecordedAsSkipped() {
        // Today: URL(string:) is lenient about plain text, but a malformed scheme plus a
        // space still fails to parse.
        let text = "ht!tp://exa mple.com\nhttps://example.com/feed1\n"
        let result = SpotifyListParser.parse(data: Data(text.utf8))

        // Changed from today: that line used to be silently dropped via compactMap; it's
        // now recorded in `skipped` instead.
        #expect(result.feeds.count == 1)
        #expect(result.feeds[0].feedURL.absoluteString == "https://example.com/feed1")
        #expect(result.skipped.count == 1)
    }

    @Test func duplicateLinesAreDeduplicated() {
        let text = "https://example.com/feed1\nhttps://example.com/feed1\n"
        let result = SpotifyListParser.parse(data: Data(text.utf8))

        // Changed from today: duplicate lines were not de-duplicated; they now collapse
        // to one feed, with the duplicate recorded in `skipped`.
        #expect(result.feeds.count == 1)
        #expect(result.skipped.count == 1)
    }
}
