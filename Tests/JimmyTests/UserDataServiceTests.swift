import XCTest
@testable import JimmyUtilities

final class UserDataServiceTests: XCTestCase {
    func testSaveAndLoadUserData() throws {
        let podcast = PodcastInfo(title: "Test Show", feedURL: URL(string: "https://example.com/feed")!)
        let episodeID = UUID()
        let data = UserData(subscriptions: [podcast], listenedEpisodeIDs: [episodeID])
        let userID = "user_test"

        // Ensure clean state
        _ = FileStorage.shared.delete("user_\(userID)_data.json")

        XCTAssertTrue(UserDataService.shared.save(data, for: userID))
        let loaded = UserDataService.shared.load(for: userID)
        XCTAssertEqual(loaded?.subscriptions.first?.title, "Test Show")
        XCTAssertEqual(loaded?.listenedEpisodeIDs.first, episodeID)

        // Clean up
        _ = FileStorage.shared.delete("user_\(userID)_data.json")
    }
}
