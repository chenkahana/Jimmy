import Foundation
import Testing
@testable import JimmyKit

/// Ported from `Tests/JimmyTests/GoogleTakeoutParserTests.swift`, which pinned the app's
/// `GoogleTakeoutParser.parse(data:)` as it behaved before this move. Assertions that the
/// move's deliberate improvements intentionally change are marked `// Changed from today: …`.
struct GoogleTakeoutParserTests {
    @Test func parsing() throws {
        let json = """
        {
            "subscriptions": [{"title":"Show","feedUrl":"https://example.com/feed"}]
        }
        """
        let data = Data(json.utf8)
        let result = try GoogleTakeoutParser.parse(data: data)
        #expect(result.feeds.first?.feedURL.absoluteString == "https://example.com/feed")
    }

    @Test func emptySubscriptionsArrayReturnsEmpty() throws {
        let json = """
        { "subscriptions": [] }
        """
        let data = Data(json.utf8)
        let result = try GoogleTakeoutParser.parse(data: data)
        #expect(result.feeds.isEmpty)
    }

    @Test func malformedJSONThrowsMalformed() {
        let data = Data("{not valid json".utf8)
        // Changed from today: the underlying DecodingError is now wrapped as
        // ImportError.malformed, matching OPMLParser's malformed-document error.
        #expect(throws: ImportError.malformed) {
            try GoogleTakeoutParser.parse(data: data)
        }
    }

    @Test func missingSubscriptionsKeyThrowsMalformed() {
        // "subscriptions" is non-optional on GoogleSubscriptions.
        let data = Data("{}".utf8)
        #expect(throws: ImportError.malformed) {
            try GoogleTakeoutParser.parse(data: data)
        }
    }

    @Test func missingFeedUrlFieldThrowsMalformed() {
        let json = """
        { "subscriptions": [{"title":"Show"}] }
        """
        let data = Data(json.utf8)
        #expect(throws: ImportError.malformed) {
            try GoogleTakeoutParser.parse(data: data)
        }
    }

    @Test func invalidFeedURLIsSkippedInsteadOfVanishing() throws {
        let json = """
        {
            "subscriptions": [
                {"title":"Bad","feedUrl":""},
                {"title":"Good","feedUrl":"https://example.com/feed"}
            ]
        }
        """
        let data = Data(json.utf8)
        let result = try GoogleTakeoutParser.parse(data: data)

        // Changed from today: an entry whose feedUrl fails URL(string:) used to be
        // dropped via compactMap; it's now recorded in `skipped` instead.
        #expect(result.feeds.count == 1)
        #expect(result.feeds.first?.title == "Good")
        #expect(result.skipped.count == 1)
    }

    @Test func duplicateFeedsAreDeduplicated() throws {
        let json = """
        {
            "subscriptions": [
                {"title":"Show","feedUrl":"https://example.com/feed"},
                {"title":"Show","feedUrl":"https://example.com/feed"}
            ]
        }
        """
        let data = Data(json.utf8)
        let result = try GoogleTakeoutParser.parse(data: data)

        // Changed from today: duplicate feeds were not de-duplicated; they now collapse
        // to one, with the duplicate recorded in `skipped`.
        #expect(result.feeds.count == 1)
        #expect(result.skipped.count == 1)
    }
}
