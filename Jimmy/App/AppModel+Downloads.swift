import Foundation
import JimmyKit

/// Downloads, backed by JimmyKit's `Downloads` against the same `Store` and the same background
/// `URLSession` identifier (`com.chenkahana.Jimmy.downloads`, under `Documents/Downloads/`) the
/// old `DownloadManager` used, so any file it already downloaded on a real device carries over.
extension AppModel {
    /// The one `Downloads`, or `nil` while `launchState` isn't `.ready`.
    var downloads: Downloads? {
        guard case .ready(let ready) = launchState else { return nil }
        return ready.downloads
    }

    /// `episodeID`'s download lifecycle state, or `nil` if nothing has ever started downloading it.
    func downloadState(for episodeID: UUID) -> JimmyKit.DownloadState? {
        downloads?.states[episodeID]
    }

    /// Whether `episodeID` has a completed download on disk.
    func isDownloaded(_ episodeID: UUID) -> Bool {
        downloadState(for: episodeID) == .done
    }

    func download(_ episode: JimmyKit.Episode) {
        downloads?.download(episode)
    }

    func cancelDownload(_ episodeID: UUID) {
        downloads?.cancel(episodeID)
    }

    func deleteDownload(_ episodeID: UUID) {
        downloads?.delete(episodeID)
    }

    /// Builds the `Downloads` for `open(databasePath:legacyInput:)`: a real background session in
    /// the app, or — while hosted under XCTest (`make test`, which `JimmyApp`'s own
    /// `isRunningUnitTests` checks the same way) — an ephemeral one, so the many `AppModel`
    /// instances separate test functions create in one process never fight over a single
    /// background session identifier.
    static func makeDownloads(store: Store, databasePath: String) -> Downloads {
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let baseDirectory = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
        let configuration: URLSessionConfiguration = isRunningUnitTests
            ? .ephemeral
            : .background(withIdentifier: Downloads.sessionIdentifier)
        return Downloads(store: store, baseDirectory: baseDirectory, sessionConfiguration: configuration)
    }
}
