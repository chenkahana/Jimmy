import Foundation
import Testing
@testable import JimmyKit

struct OPMLWriterTests {
    @Test func exportThenImportRoundTripsTheSameFeeds() throws {
        let feeds = [
            ImportedFeed(feedURL: URL(string: "https://example.com/feed1.xml")!, title: "Show One"),
            ImportedFeed(feedURL: URL(string: "https://example.com/feed2.xml")!, title: "Show & <Two>"),
            ImportedFeed(feedURL: URL(string: "https://example.com/feed3.xml")!, title: nil),
        ]

        let data = OPMLWriter.write(feeds)
        let result = try OPMLParser.parse(data: data)

        #expect(result.skipped.isEmpty)
        #expect(result.feeds.count == feeds.count)
        #expect(result.feeds[0].feedURL == feeds[0].feedURL)
        #expect(result.feeds[0].title == feeds[0].title)
        #expect(result.feeds[1].feedURL == feeds[1].feedURL)
        #expect(result.feeds[1].title == feeds[1].title)
        #expect(result.feeds[2].feedURL == feeds[2].feedURL)
        // A nil title falls back to the feed URL when writing, since OPML outlines
        // require a name; parsing it back therefore yields that URL string as the title.
        #expect(result.feeds[2].title == feeds[2].feedURL.absoluteString)
    }

    @Test func writeProducesNoOutlinesForEmptyInput() throws {
        let data = OPMLWriter.write([])
        let result = try OPMLParser.parse(data: data)
        #expect(result.feeds.isEmpty)
        #expect(result.skipped.isEmpty)
    }
}
