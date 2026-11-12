import XCTest
#if canImport(JimmyUtilities)
@testable import JimmyUtilities
#else
@testable import Jimmy
#endif

@MainActor
final class UserDataServiceTests: XCTestCase {
    func testSaveAndLoadUserData() throws {
        let service = UserDataService.shared
        let testUser = "test-user"
        let data = UserData(subscriptions: [PodcastInfo(title: "Test", feedURL: URL(string: "https://example.com/feed")!)], listenedEpisodeIDs: [])

        XCTAssertTrue(service.save(data, for: testUser))
        let loaded = service.load(for: testUser)
        XCTAssertEqual(loaded, data)
        // clean up
        _ = FileStorage.shared.delete("user_\(testUser)_data.json")
    }

    func testInvalidUserIDIsRejected() {
        let service = UserDataService.shared
        let invalidUser = ""
        let data = UserData()

        XCTAssertFalse(service.save(data, for: invalidUser))
        XCTAssertNil(service.load(for: invalidUser))
    }
}
