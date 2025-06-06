#if !os(Linux)
import XCTest
@testable import Jimmy

final class EpisodeCacheMigrationTests: XCTestCase {
    override func setUp() async throws {
        // Clean state
        FileStorage.shared.delete("episodeCache.json")
        UserDefaults.standard.removeObject(forKey: "episodeCacheData")
    }

    func testMigratesLegacyCacheToFile() throws {
        // Prepare legacy UserDefaults data
        let podcastID = UUID()
        let episode = Episode(id: UUID(), title: "Legacy", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: podcastID, publishedDate: nil, localFileURL: nil)
        let data = try JSONEncoder().encode([episode])
        let base64 = data.base64EncodedString()
        let oldEntry: [String: Any] = [
            "episodes": base64,
            "timestamp": Date().timeIntervalSince1970,
            "lastModified": "test"
        ]
        UserDefaults.standard.set([podcastID.uuidString: oldEntry], forKey: "episodeCacheData")

        // Trigger migration
        EpisodeCacheService.shared.migrateLegacyCacheIfNeeded()

        // Verify file created and UserDefaults cleared
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppData/episodeCache.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(UserDefaults.standard.object(forKey: "episodeCacheData"))
    }
}
#endif
