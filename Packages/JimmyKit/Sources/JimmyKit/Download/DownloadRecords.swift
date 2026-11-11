import Foundation

/// Loads and saves `Download` records. Backed by the (parallel-authored) Store module in the
/// real app; `Downloads` only depends on this protocol so it doesn't need to wait on that work.
///
/// `Store` already has `downloads()` / `saveDownload(_:)` (see `Store.swift`); it does not yet
/// have a way to remove a record, so `deleteDownload(_:)` here is new surface `Store` will need
/// to grow in a later PR.
public nonisolated protocol DownloadRecords: Sendable {
    func loadDownloads() async throws -> [Download]
    func saveDownload(_ download: Download) async throws
    func deleteDownload(_ episodeID: UUID) async throws
}
