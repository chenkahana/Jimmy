import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

/// Characterization tests for OPMLParser.parse(_:) as it behaves TODAY.
///
/// Today's parser never throws: `parse(_:)` returns `[Podcast]` and silently returns
/// whatever outlines were collected before (or regardless of) any XML parse failure.
/// Closed PR #116 proposed a throwing API with explicit error cases; these tests pin
/// the current, non-throwing behavior using similar input shapes.
final class OPMLParserTests: XCTestCase {
    func testValidOPMLWithNestedOutlinesAndMixedAttributes() {
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
        let podcasts = OPMLParser().parse(Data(opml.utf8))

        // Today: a folder outline with no xmlUrl is skipped, but its nested child is still
        // visited (XMLParser fires didStartElement for every <outline>, nesting or not).
        // Today: an outline using "title" instead of "text" falls back to "title" for the name.
        // Today: an outline using "url" instead of "xmlUrl" is silently dropped — only "xmlUrl"
        // is recognized.
        // Today: an outline with xmlUrl but no text/title is silently dropped.
        XCTAssertEqual(podcasts.count, 2)

        XCTAssertEqual(podcasts[0].title, "Nested Show")
        XCTAssertEqual(podcasts[0].author, "Nested Author")
        XCTAssertEqual(podcasts[0].feedURL.absoluteString, "https://example.com/nested.xml")

        XCTAssertEqual(podcasts[1].title, "Title Attr Show")
        XCTAssertEqual(podcasts[1].author, "")
        XCTAssertEqual(podcasts[1].feedURL.absoluteString, "https://example.com/titleattr.xml")
    }

    func testEmptyFileReturnsEmptyArray() {
        let podcasts = OPMLParser().parse(Data())
        XCTAssertTrue(podcasts.isEmpty)
    }

    func testMalformedXMLReturnsWhateverWasParsedBeforeTheError() {
        // Mismatched closing tag: </body> arrives while <outline> is still open.
        let malformed = """
        <opml><body><outline text="Good" xmlUrl="https://example.com/good.xml"></body></opml>
        """
        let podcasts = OPMLParser().parse(Data(malformed.utf8))

        // Today: parse(_:) does not check XMLParser's return value or report the error —
        // it returns the outlines collected up to the point of failure, not an empty array.
        XCTAssertEqual(podcasts.count, 1)
        XCTAssertEqual(podcasts[0].title, "Good")
    }

    func testCompletelyInvalidDataReturnsEmptyArray() {
        let podcasts = OPMLParser().parse(Data("not xml at all".utf8))
        // Today: no error is surfaced; an unparseable document just yields no podcasts.
        XCTAssertTrue(podcasts.isEmpty)
    }

    func testNonOPMLXMLReturnsEmptyArray() {
        let xml = "<root><item>Hello</item></root>"
        let podcasts = OPMLParser().parse(Data(xml.utf8))
        XCTAssertTrue(podcasts.isEmpty)
    }

    func testDuplicateFeedsAreNotDeduplicated() {
        let opml = """
        <opml><body>
            <outline text="Dup Show" xmlUrl="https://example.com/dup.xml" />
            <outline text="Dup Show" xmlUrl="https://example.com/dup.xml" />
        </body></opml>
        """
        let podcasts = OPMLParser().parse(Data(opml.utf8))

        // Today: OPMLParser performs no deduplication by feed URL or title.
        XCTAssertEqual(podcasts.count, 2)
        XCTAssertEqual(podcasts[0].feedURL, podcasts[1].feedURL)
    }
}
