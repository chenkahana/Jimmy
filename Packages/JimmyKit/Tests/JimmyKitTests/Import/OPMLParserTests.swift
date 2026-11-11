import Foundation
import Testing
@testable import JimmyKit

/// Ported from `Tests/JimmyTests/OPMLParserTests.swift`, which pinned the app's
/// `OPMLParser.parse(_:)` as it behaved before this move. Assertions that the move's
/// deliberate improvements intentionally change are marked `// Changed from today: …`.
struct OPMLParserTests {
    @Test func validOPMLWithNestedOutlinesAndMixedAttributes() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
            <body>
                <outline text="Folder">
                    <outline text="Nested Show" xmlUrl="https://example.com/nested.xml" author="Nested Author" />
                </outline>
                <outline title="Title Attr Show" xmlUrl="https://example.com/titleattr.xml" />
                <outline text="URL Attr Show" url="https://example.com/urlattr.xml" />
                <outline xmlUrl="https://example.com/notitle.xml" />
            </body>
        </opml>
        """
        let result = try OPMLParser.parse(data: Data(opml.utf8))

        // Today: a folder outline with no xmlUrl is skipped, but its nested child is still
        // visited (XMLParser fires didStartElement for every <outline>, nesting or not).
        // Today: an outline using "title" instead of "text" falls back to "title" for the name.
        // Changed from today: an outline using "url" instead of "xmlUrl" used to be silently
        // dropped; OPMLParser now accepts "url" as well.
        // Today: an outline with xmlUrl but no text/title is still silently dropped.
        #expect(result.feeds.count == 3)

        #expect(result.feeds[0].title == "Nested Show")
        #expect(result.feeds[0].feedURL.absoluteString == "https://example.com/nested.xml")

        #expect(result.feeds[1].title == "Title Attr Show")
        #expect(result.feeds[1].feedURL.absoluteString == "https://example.com/titleattr.xml")

        #expect(result.feeds[2].title == "URL Attr Show")
        #expect(result.feeds[2].feedURL.absoluteString == "https://example.com/urlattr.xml")
    }

    @Test func emptyFileThrowsMalformed() {
        // Changed from today: an empty document used to return an empty array silently.
        // XMLParser.parse() reports failure for an empty document, so OPMLParser now
        // surfaces that as ImportError.malformed instead of swallowing it.
        #expect(throws: ImportError.malformed) {
            try OPMLParser.parse(data: Data())
        }
    }

    @Test func malformedXMLThrowsMalformedInsteadOfPartialResult() {
        // Mismatched closing tag: </body> arrives while <outline> is still open.
        let malformed = """
        <opml><body><outline text="Good" xmlUrl="https://example.com/good.xml"></body></opml>
        """
        // Changed from today: parse(_:) used to return whatever outlines were collected
        // before the error (one podcast, "Good") instead of surfacing the failure.
        #expect(throws: ImportError.malformed) {
            try OPMLParser.parse(data: Data(malformed.utf8))
        }
    }

    @Test func completelyInvalidDataThrowsMalformed() {
        // Changed from today: unparseable, non-XML content used to yield an empty array
        // silently; XMLParser still fails to parse it, so it's now reported as malformed.
        #expect(throws: ImportError.malformed) {
            try OPMLParser.parse(data: Data("not xml at all".utf8))
        }
    }

    @Test func nonOPMLXMLReturnsEmptyResult() throws {
        // Today: well-formed XML with no recognizable <outline> elements parses
        // successfully and simply yields nothing — this is not a malformed document.
        let xml = "<root><item>Hello</item></root>"
        let result = try OPMLParser.parse(data: Data(xml.utf8))
        #expect(result.feeds.isEmpty)
        #expect(result.skipped.isEmpty)
    }

    @Test func duplicateFeedsAreDeduplicated() throws {
        let opml = """
        <opml><body>
            <outline text="Dup Show" xmlUrl="https://example.com/dup.xml" />
            <outline text="Dup Show" xmlUrl="https://example.com/dup.xml" />
        </body></opml>
        """
        let result = try OPMLParser.parse(data: Data(opml.utf8))

        // Changed from today: OPMLParser performed no de-duplication; duplicate feed URLs
        // are now collapsed to one, with the duplicate recorded in `skipped`.
        #expect(result.feeds.count == 1)
        #expect(result.feeds[0].feedURL.absoluteString == "https://example.com/dup.xml")
        #expect(result.skipped.count == 1)
    }

    @Test func duplicateDetectionNormalizesSchemeHostAndTrailingSlash() throws {
        // Covers the de-duplication improvement's normalization rules directly:
        // lowercase scheme/host, a dropped trailing slash, and feed:// treated as https://.
        let opml = """
        <opml><body>
            <outline text="A" xmlUrl="https://Example.com/show/" />
            <outline text="B" xmlUrl="FEED://example.com/show" />
        </body></opml>
        """
        let result = try OPMLParser.parse(data: Data(opml.utf8))
        #expect(result.feeds.count == 1)
        #expect(result.skipped.count == 1)
    }

    @Test func subscribeSchemesBecomeHTTPS() throws {
        // Changed from today: feed://, itpc:// and pcast:// URLs come out as https:// so they can be fetched.
        let opml = """
        <opml><body>
            <outline text="A" xmlUrl="feed://example.com/a.xml" />
            <outline text="B" xmlUrl="itpc://example.com/b.xml?x=1" />
            <outline text="C" xmlUrl="pcast://example.com/c.xml" />
        </body></opml>
        """
        let result = try OPMLParser.parse(data: Data(opml.utf8))
        #expect(result.feeds.map(\.feedURL.absoluteString) == [
            "https://example.com/a.xml", "https://example.com/b.xml?x=1", "https://example.com/c.xml",
        ])
    }

    @Test func invalidFeedURLIsSkippedInsteadOfVanishing() throws {
        let opml = """
        <opml><body>
            <outline text="Bad" xmlUrl="ht!tp://exa mple.com" />
            <outline text="Good" xmlUrl="https://example.com/good.xml" />
        </body></opml>
        """
        let result = try OPMLParser.parse(data: Data(opml.utf8))

        // Changed from today: an outline whose xmlUrl fails to parse as a URL used to be
        // silently dropped; it's now recorded in `skipped` instead.
        #expect(result.feeds.count == 1)
        #expect(result.feeds[0].title == "Good")
        #expect(result.skipped.count == 1)
    }
}
