import Foundation

/// Translates `URLSessionDownloadDelegate` callbacks — which arrive off the main actor, on a
/// queue owned by `URLSession` — into plain data, doing the one thing that must happen
/// synchronously (moving the finished file out of the tmp location `URLSession` will delete the
/// moment the callback returns) before handing off to `Downloads` on the main actor.
///
/// `nonisolated` so it opts out of this module's default main-actor isolation: its methods must
/// run on whatever thread `URLSession` calls them on, not hop to the main actor first.
nonisolated final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    struct FinishedDownload: Sendable {
        let episodeID: UUID
        let relativePath: String
        let byteCount: Int64
    }

    private let downloadsDirectory: URL
    private let onProgress: @Sendable (UUID, Double) -> Void
    private let onFinished: @Sendable (FinishedDownload) -> Void
    private let onFailed: @Sendable (UUID) -> Void
    private let onBackgroundEventsFinished: @Sendable () -> Void

    init(
        downloadsDirectory: URL,
        onProgress: @escaping @Sendable (UUID, Double) -> Void,
        onFinished: @escaping @Sendable (FinishedDownload) -> Void,
        onFailed: @escaping @Sendable (UUID) -> Void,
        onBackgroundEventsFinished: @escaping @Sendable () -> Void
    ) {
        self.downloadsDirectory = downloadsDirectory
        self.onProgress = onProgress
        self.onFinished = onFinished
        self.onFailed = onFailed
        self.onBackgroundEventsFinished = onBackgroundEventsFinished
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let episodeID = Self.episodeID(from: downloadTask) else { return }
        let fileName = "\(episodeID.uuidString).mp3"
        let destination = downloadsDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            // Must happen synchronously, before this method returns: URLSession deletes the
            // tmp file at `location` right after the delegate callback completes.
            try FileManager.default.moveItem(at: location, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
            onFinished(FinishedDownload(
                episodeID: episodeID,
                relativePath: "Downloads/\(fileName)",
                byteCount: Int64(size)
            ))
        } catch {
            onFailed(episodeID)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let episodeID = Self.episodeID(from: downloadTask), totalBytesExpectedToWrite > 0 else { return }
        onProgress(episodeID, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let episodeID = Self.episodeID(from: task) else { return }
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        onFailed(episodeID)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onBackgroundEventsFinished()
    }

    private static func episodeID(from task: URLSessionTask) -> UUID? {
        task.taskDescription.flatMap(UUID.init(uuidString:))
    }
}
