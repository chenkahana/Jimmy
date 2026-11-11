import Foundation

/// Lifecycle state of a downloaded episode file.
public enum DownloadState: String, Sendable, Hashable, Codable {
    case queued
    case downloading
    case done
    case failed
}

/// A downloaded (or in-flight) episode file, stored relative to the app's downloads directory.
public nonisolated struct Download: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID { episodeID }
    public var episodeID: UUID
    /// Path relative to the downloads directory; never an absolute URL, which can move between launches.
    public var relativePath: String
    public var byteCount: Int64?
    public var state: DownloadState
    public var updatedAt: Date

    public init(
        episodeID: UUID,
        relativePath: String,
        byteCount: Int64? = nil,
        state: DownloadState = .queued,
        updatedAt: Date = Date()
    ) {
        self.episodeID = episodeID
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.state = state
        self.updatedAt = updatedAt
    }
}
