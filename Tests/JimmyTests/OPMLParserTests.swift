import XCTest
@testable import JimmyUtilities

final class OPMLParserTests: XCTestCase {
    func testParseOPMLFile() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.1">
            <body>
                <outline text="Show1" xmlUrl="https://example.com/1.xml" />
                <outline text="Show2" xmlUrl="https://example.com/2.xml" author="Author" />
            </body>
        </opml>
        """
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test.opml")
        try opml.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let parser = OPMLParser()
        let podcasts = parser.parseOPML(from: fileURL)
        XCTAssertEqual(podcasts.count, 2)
        XCTAssertEqual(podcasts[0].title, "Show1")
        XCTAssertEqual(podcasts[1].author, "Author")
    }
}
