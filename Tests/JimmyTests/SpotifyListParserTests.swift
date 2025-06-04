import XCTest
@testable import JimmyUtilities

final class SpotifyListParserTests: XCTestCase {
    func testParseReturnsURLs() {
        let content = """
        https://open.spotify.com/show/123
        https://open.spotify.com/show/456
        not a url
        """
        let data = Data(content.utf8)
        let urls = SpotifyListParser.parse(data: data)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].absoluteString, "https://open.spotify.com/show/123")
        XCTAssertEqual(urls[1].absoluteString, "https://open.spotify.com/show/456")
    }
}
