import Foundation
import GRDB
import Testing
@testable import JimmyKit

struct StoreDownloadRecordsTests {
    @Test func savesLoadsAndDeletesDownloads() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-downloads-\(UUID().uuidString).sqlite").path
        let store = try Store(path: path)
        let records: any DownloadRecords = store
        let episodeID = UUID()
        let podcastID = UUID()
        let pool = try DatabasePool(path: path)
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle) VALUES (?, 'S', 'A', '', 'https://example.com/f.xml', 'S')",
                arguments: [podcastID.uuidString]
            )
            try db.execute(
                sql: "INSERT INTO episodes (id, podcastID, title) VALUES (?, ?, 'E')",
                arguments: [episodeID.uuidString, podcastID.uuidString]
            )
        }
        try pool.close()

        try await records.saveDownload(Download(episodeID: episodeID, relativePath: "Downloads/\(episodeID.uuidString).mp3", byteCount: 42, state: .done, updatedAt: Date()))
        #expect(try await records.loadDownloads().map(\.episodeID) == [episodeID])

        try await records.deleteDownload(episodeID)
        #expect(try await records.loadDownloads().isEmpty)
    }
}
