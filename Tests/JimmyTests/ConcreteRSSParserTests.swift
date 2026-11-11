import XCTest
@testable import Jimmy

final class ConcreteRSSParserTests: XCTestCase {
    /// Bad XML used to resume the continuation twice (once from `parseErrorOccurred`, once after
    /// `parse()` returned false) and crash the app.
    func testMalformedFeedThrowsInsteadOfCrashing() async {
        let data = Data("<rss><channel><item><title>Unclosed".utf8)
        do {
            _ = try await ConcreteRSSParser().parse(
                data: data,
                podcastID: UUID(),
                feedURL: URL(fileURLWithPath: "/feed.xml")
            )
            XCTFail("Expected a parse error")
        } catch {
            // Expected.
        }
    }
}
