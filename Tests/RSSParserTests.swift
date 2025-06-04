import XCTest
@testable import Jimmy

final class RSSParserTests: XCTestCase {
    func testParserReturnsEpisodes() {
        let sampleRSS = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <rss version=\"2.0\">
            <channel>
                <title>Test Podcast</title>
                <item>
                    <title>Episode 1</title>
                    <enclosure url=\"http://example.com/audio.mp3\" length=\"12345\" type=\"audio/mpeg\"/>
                    <pubDate>Sun, 12 May 2024 15:00:00 GMT</pubDate>
                    <description>Test Episode</description>
                </item>
            </channel>
        </rss>
        """
        let data = Data(sampleRSS.utf8)
        let parser = RSSParser()
        let episodes = parser.parseRSS(data: data, podcastID: UUID())
        XCTAssertFalse(episodes.isEmpty, "Parser should return at least one episode")
    }
}
