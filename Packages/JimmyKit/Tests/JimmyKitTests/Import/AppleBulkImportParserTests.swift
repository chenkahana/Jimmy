import Foundation
import Testing
@testable import JimmyKit

/// Ported from `Tests/JimmyTests/AppleBulkImportParserTests.swift`, which pinned the app's
/// `AppleBulkImportParser.parse(data:)` as it behaved before this move. Assertions that the
/// move's deliberate improvements intentionally change are marked `// Changed from today: …`.
struct AppleBulkImportParserTests {
    @Test func parsing() throws {
        let json = """
        [
            {"title":"Show","feedUrl":"https://example.com/feed","author":"Me"}
        ]
        """
        let data = Data(json.utf8)
        let result = try AppleBulkImportParser.parse(data: data)
        #expect(result.feeds.first?.title == "Show")
    }

    @Test func emptyArrayReturnsEmpty() throws {
        let data = Data("[]".utf8)
        let result = try AppleBulkImportParser.parse(data: data)
        #expect(result.feeds.isEmpty)
    }

    @Test func malformedJSONThrowsMalformed() {
        let data = Data("{not valid json".utf8)
        // Changed from today: the underlying DecodingError is now wrapped as
        // ImportError.malformed, matching OPMLParser's malformed-document error.
        #expect(throws: ImportError.malformed) {
            try AppleBulkImportParser.parse(data: data)
        }
    }

    @Test func missingRequiredFeedURLFieldThrowsMalformed() {
        // "feedUrl" is non-optional on ExportedPodcast, so a missing key fails decoding.
        let json = """
        [{"title":"Show"}]
        """
        let data = Data(json.utf8)
        #expect(throws: ImportError.malformed) {
            try AppleBulkImportParser.parse(data: data)
        }
    }

    @Test func missingOptionalAuthorDoesNotFailParsing() throws {
        // Today: ExportedPodcast.author is optional, so a missing "author" key still
        // decodes. ImportedFeed carries no author field, so there's nothing to default
        // here — this just confirms the omission doesn't throw.
        let json = """
        [{"title":"Show","feedUrl":"https://example.com/feed"}]
        """
        let data = Data(json.utf8)
        let result = try AppleBulkImportParser.parse(data: data)
        #expect(result.feeds.count == 1)
    }

    @Test func invalidFeedURLIsSkippedInsteadOfVanishing() throws {
        let json = """
        [
            {"title":"Bad","feedUrl":"","author":"X"},
            {"title":"Good","feedUrl":"https://example.com/feed","author":"Y"}
        ]
        """
        let data = Data(json.utf8)
        let result = try AppleBulkImportParser.parse(data: data)

        // Changed from today: an entry whose feedUrl fails URL(string:) used to be
        // dropped via compactMap; it's now recorded in `skipped` instead.
        #expect(result.feeds.count == 1)
        #expect(result.feeds.first?.title == "Good")
        #expect(result.skipped.count == 1)
    }

    @Test func duplicateEntriesAreDeduplicated() throws {
        let json = """
        [
            {"title":"Show","feedUrl":"https://example.com/feed","author":"Me"},
            {"title":"Show","feedUrl":"https://example.com/feed","author":"Me"}
        ]
        """
        let data = Data(json.utf8)
        let result = try AppleBulkImportParser.parse(data: data)

        // Changed from today: duplicate entries were not de-duplicated; they now
        // collapse to one feed, with the duplicate recorded in `skipped`.
        #expect(result.feeds.count == 1)
        #expect(result.skipped.count == 1)
    }
}
