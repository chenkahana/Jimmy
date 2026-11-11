import Foundation
import Synchronization
@testable import JimmyKit

/// An in-memory `DownloadRecords` for tests. A `Mutex`-guarded class rather than an actor:
/// the actor form trips a compiler error on the `nonisolated` protocol conformance.
final class FakeDownloadRecords: DownloadRecords {
    private let storage: Mutex<[UUID: Download]>

    init(_ initial: [Download] = []) {
        storage = Mutex(Dictionary(uniqueKeysWithValues: initial.map { ($0.episodeID, $0) }))
    }

    func loadDownloads() async throws -> [Download] {
        storage.withLock { Array($0.values) }
    }

    func saveDownload(_ download: Download) async throws {
        storage.withLock { $0[download.episodeID] = download }
    }

    func deleteDownload(_ episodeID: UUID) async throws {
        _ = storage.withLock { $0.removeValue(forKey: episodeID) }
    }

    func record(for episodeID: UUID) async -> Download? {
        storage.withLock { $0[episodeID] }
    }

    func all() async -> [Download] {
        storage.withLock { Array($0.values) }
    }
}
