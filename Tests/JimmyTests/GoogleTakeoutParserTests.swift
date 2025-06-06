import XCTest
@testable import JimmyUtilities

final class GoogleTakeoutParserTests: XCTestCase {
    func testParseSubscriptions() throws {
        let json = """
        {"subscriptions": [
            {"title": "Show1", "feedUrl": "https://example.com/1.xml"},
            {"title": "Show2", "feedUrl": "https://example.com/2.xml"}
        ]}
        """
        let data = Data(json.utf8)
        let podcasts = try GoogleTakeoutParser.parse(data: data)
        XCTAssertEqual(podcasts.count, 2)
        XCTAssertEqual(podcasts.first?.title, "Show1")
    }
}
