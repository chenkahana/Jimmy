import Foundation
import GRDB
import Synchronization
import Testing
@testable import JimmyKit

/// From PR 15 on, the legacy app's own `DatabaseManager` pool and `Store`'s pool both write
/// `jimmy.db` concurrently. `Store.init` sets `busyMode = .timeout(5)` so a `Store` write waits
/// out another connection's write transaction instead of immediately failing with `SQLITE_BUSY`
/// (GRDB's default, `.immediateError`, would fail it right away).
struct BusyTimeoutTests {
    private func makeTempDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jimmykit-busy-timeout-\(UUID().uuidString).sqlite")
            .path
    }

    @Test func storeWriteWaitsOutAnotherPoolsBriefWriteTransactionInsteadOfFailing() async throws {
        let path = makeTempDatabasePath()
        let store = try Store(path: path)

        let podcastID = UUID()
        let episodeID = UUID()
        let setupPool = try DatabasePool(path: path)
        try await setupPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO podcasts (id, title, author, description, feedURL, cleanTitle)
                    VALUES (?, 'S', 'A', '', 'https://example.com/f.xml', 'S')
                    """,
                arguments: [podcastID.uuidString]
            )
            try db.execute(
                sql: "INSERT INTO episodes (id, podcastID, title) VALUES (?, ?, 'E')",
                arguments: [episodeID.uuidString, podcastID.uuidString]
            )
        }
        try setupPool.close()

        // A second, independent connection to the same file — standing in for the legacy app's
        // own `DatabaseManager` pool.
        let otherPool = try DatabasePool(path: path)
        let holderHoldsTheWriteLock = Mutex(false)

        let holderTask = Task.detached {
            try otherPool.write { db in
                // GRDB's default transaction kind is `.deferred`, so the write lock isn't taken
                // until the first write statement actually runs — signal only after this one has.
                try db.execute(sql: "UPDATE episodes SET title = 'Held' WHERE id = ?", arguments: [episodeID.uuidString])
                holderHoldsTheWriteLock.withLock { $0 = true }
                Thread.sleep(forTimeInterval: 1.0)
            }
        }

        while !holderHoldsTheWriteLock.withLock({ $0 }) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Would throw SQLITE_BUSY immediately without `busyMode`; instead this waits for
        // `otherPool`'s transaction to commit and then succeeds.
        try await store.saveProgress(
            Progress(episodeID: episodeID, position: 10, duration: nil, isFinished: false, updatedAt: Date())
        )

        try await holderTask.value
    }
}
