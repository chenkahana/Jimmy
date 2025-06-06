import XCTest
@testable import JimmyUtilities

final class AppleBulkImportParserTests: XCTestCase {
    func testParseValidJSON() throws {
        let json = """
        [
            {"title": "Show1", "feedUrl": "https://example.com/1.xml", "author": "A"},
            {"title": "Show2", "feedUrl": "https://example.com/2.xml"}
        ]
        """
        let data = Data(json.utf8)
        let podcasts = try AppleBulkImportParser.parse(data: data)
        XCTAssertEqual(podcasts.count, 2)
        XCTAssertEqual(podcasts[0].title, "Show1")
        XCTAssertEqual(podcasts[1].author, "")
    }
}
