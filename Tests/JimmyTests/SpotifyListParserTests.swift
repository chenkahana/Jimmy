import XCTest
@testable import JimmyUtilities

final class SpotifyListParserTests: XCTestCase {
    func testParseURLs() throws {
        let text = "https://open.spotify.com/show/1\nhttps://open.spotify.com/show/2\n" // trailing newline
        let data = Data(text.utf8)
        let urls = SpotifyListParser.parse(data: data)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].absoluteString, "https://open.spotify.com/show/1")
        XCTAssertEqual(urls[1].absoluteString, "https://open.spotify.com/show/2")
    }
}
