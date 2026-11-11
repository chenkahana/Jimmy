import Foundation
@testable import JimmyKit

/// An in-memory `DownloadRecords`, standing in for `Store` until it conforms.
actor FakeDownloadRecords: DownloadRecords {
    private var storage: [UUID: Download]

    init(_ initial: [Download] = []) {
        storage = Dictionary(uniqueKeysWithValues: initial.map { ($0.episodeID, $0) })
    }

    func loadDownloads() async throws -> [Download] {
        Array(storage.values)
    }

    func saveDownload(_ download: Download) async throws {
        storage[download.episodeID] = download
    }

    func deleteDownload(_ episodeID: UUID) async throws {
        storage.removeValue(forKey: episodeID)
    }

    func record(for episodeID: UUID) -> Download? {
        storage[episodeID]
    }

    func all() -> [Download] {
        Array(storage.values)
    }
}
