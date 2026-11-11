import Foundation
import Observation

/// Downloads episode audio in the background and keeps it in sync with a `DownloadRecords`
/// store, mirroring today's app `DownloadManager` (same `URLSession` background identifier,
/// same `Downloads/<episodeID>.mp3` file naming) so in-flight and existing downloads carry over.
///
/// Collaborators are protocols/injectable values (`DownloadRecords`, `baseDirectory`,
/// `sessionConfiguration`) so this type can be driven by fakes/stubs in tests, with no real
/// filesystem location or background session involved.
@Observable
public final class Downloads {
    /// The identifier today's app's `DownloadManager` already uses; kept so tasks started
    /// before an app update keep running and get reconciled rather than orphaned.
    public static let sessionIdentifier = "com.chenkahana.Jimmy.downloads"

    // MARK: - Observable state

    /// Download progress per episode, 0...1. Absent for episodes with no in-flight download.
    public private(set) var progress: [UUID: Double] = [:]
    /// Lifecycle state per episode, mirroring the persisted `Download.state`.
    public private(set) var states: [UUID: DownloadState] = [:]

    // MARK: - Collaborators

    private let store: DownloadRecords
    private let baseDirectory: URL
    private var session: URLSession!

    // MARK: - Private state

    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var recordsByEpisode: [UUID: Download] = [:]
    private var backgroundEventsCompletion: (@Sendable () -> Void)?
    private var pendingWrite: Task<Void, Never>?

    private var downloadsDirectory: URL {
        baseDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    public init(
        store: DownloadRecords,
        baseDirectory: URL,
        sessionConfiguration: URLSessionConfiguration = .background(withIdentifier: Downloads.sessionIdentifier)
    ) {
        self.store = store
        self.baseDirectory = baseDirectory

        let delegate = DownloadSessionDelegate(
            downloadsDirectory: baseDirectory.appendingPathComponent("Downloads", isDirectory: true),
            onProgress: { [weak self] episodeID, fraction in
                Task { @MainActor in self?.progress[episodeID] = fraction }
            },
            onFinished: { [weak self] finished in
                Task { @MainActor in await self?.handleFinished(finished) }
            },
            onFailed: { [weak self] episodeID in
                Task { @MainActor in await self?.handleFailed(episodeID) }
            },
            onBackgroundEventsFinished: { [weak self] in
                Task { @MainActor in self?.completeBackgroundEvents() }
            }
        )
        session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)

        // The first entry in the write queue, so every later save or delete waits until the
        // records on disk have been read and reconciled.
        pendingWrite = Task { [weak self] in await self?.reconcileAtLaunch() }
    }

    // MARK: - Public API

    /// Starts (or resumes queuing) a background download for `episode`. A no-op if the episode
    /// has no audio URL, is already downloading, or is already downloaded.
    public func download(_ episode: Episode) {
        guard let url = episode.audioURL else { return }
        guard activeTasks[episode.id] == nil else { return }
        if states[episode.id] == .done { return }

        let task = session.downloadTask(with: url)
        task.taskDescription = episode.id.uuidString
        activeTasks[episode.id] = task
        progress[episode.id] = 0
        states[episode.id] = .downloading

        let record = Download(
            episodeID: episode.id,
            relativePath: Self.relativePath(for: episode.id),
            state: .downloading,
            updatedAt: Date()
        )
        recordsByEpisode[episode.id] = record
        task.resume()
        write { [store] in try? await store.saveDownload(record) }
    }

    /// Cancels an in-flight download and forgets it (no file was ever completed, so there's
    /// nothing to delete from disk — use `delete(_:)` for a completed download).
    public func cancel(_ episodeID: UUID) {
        activeTasks.removeValue(forKey: episodeID)?.cancel()
        progress.removeValue(forKey: episodeID)
        states.removeValue(forKey: episodeID)
        recordsByEpisode.removeValue(forKey: episodeID)
        write { [store] in try? await store.deleteDownload(episodeID) }
    }

    /// Removes a downloaded (or in-flight) episode's file and record.
    public func delete(_ episodeID: UUID) {
        activeTasks.removeValue(forKey: episodeID)?.cancel()
        if let url = fileURL(for: episodeID) {
            try? FileManager.default.removeItem(at: url)
        }
        progress.removeValue(forKey: episodeID)
        states.removeValue(forKey: episodeID)
        recordsByEpisode.removeValue(forKey: episodeID)
        write { [store] in try? await store.deleteDownload(episodeID) }
    }

    /// The on-disk location of `episodeID`'s downloaded file, resolved against `baseDirectory`,
    /// or `nil` if there's no record for it or its file is missing.
    public func fileURL(for episodeID: UUID) -> URL? {
        guard let record = recordsByEpisode[episodeID] else { return nil }
        let url = baseDirectory.appendingPathComponent(record.relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Stores `completion` to be called once the background session's queued delegate callbacks
    /// have all been delivered — wire this up from
    /// `UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    public func handleBackgroundEvents(identifier: String, completion: @escaping @Sendable () -> Void) {
        guard identifier == Self.sessionIdentifier else { return }
        backgroundEventsCompletion = completion
    }

    /// Runs store writes one after another, in call order. Unordered writes let a fast download's
    /// earlier `.downloading` save land after its `.done` one, or a cancel's delete come before
    /// the save it was meant to undo.
    private func write(_ operation: @escaping @MainActor () async -> Void) {
        let previous = pendingWrite
        pendingWrite = Task {
            await previous?.value
            await operation()
        }
    }

    /// Internal, for tests: waits for every store write queued so far.
    func pendingWritesFinished() async {
        await pendingWrite?.value
    }

    // MARK: - Delegate callbacks (already hopped to the main actor)

    private func handleFinished(_ finished: DownloadSessionDelegate.FinishedDownload) async {
        activeTasks.removeValue(forKey: finished.episodeID)
        progress[finished.episodeID] = 1
        states[finished.episodeID] = .done
        let record = Download(
            episodeID: finished.episodeID,
            relativePath: finished.relativePath,
            byteCount: finished.byteCount,
            state: .done,
            updatedAt: Date()
        )
        recordsByEpisode[finished.episodeID] = record
        write { [store] in try? await store.saveDownload(record) }
    }

    private func handleFailed(_ episodeID: UUID) async {
        // A task that `cancel` or `delete` already dropped reports a cancellation error here; that
        // isn't a failure, and recording one would bring back the record the user just removed.
        guard activeTasks.removeValue(forKey: episodeID) != nil else { return }
        states[episodeID] = .failed
        var record = recordsByEpisode[episodeID] ?? Download(
            episodeID: episodeID,
            relativePath: Self.relativePath(for: episodeID),
            state: .failed,
            updatedAt: Date()
        )
        record.state = .failed
        record.updatedAt = Date()
        recordsByEpisode[episodeID] = record
        write { [store] in try? await store.saveDownload(record) }
    }

    /// Internal (not `private`) so tests can simulate `urlSessionDidFinishEvents` firing,
    /// without needing a real background session to deliver it.
    func completeBackgroundEvents() {
        let completion = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        completion?()
    }

    // MARK: - Relaunch reconciliation

    private func reconcileAtLaunch() async {
        guard let existing = try? await store.loadDownloads() else { return }
        for record in existing {
            recordsByEpisode[record.episodeID] = record
            states[record.episodeID] = record.state
        }

        let tasksNow = await allTasks()
        var runningIDs: Set<UUID> = []
        for task in tasksNow {
            guard let episodeID = task.taskDescription.flatMap(UUID.init(uuidString:)) else { continue }
            runningIDs.insert(episodeID)
            // `allTasks()` is a snapshot from before the await: skip a task cancelled since then.
            if let downloadTask = task as? URLSessionDownloadTask, downloadTask.state == .running {
                activeTasks[episodeID] = downloadTask
            }
        }

        let baseDirectory = baseDirectory
        let outcome = DownloadReconciler.reconcile(
            records: existing,
            runningEpisodeIDs: runningIDs,
            fileExists: { record in
                FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent(record.relativePath).path)
            },
            now: Date()
        )

        for updated in outcome.toSave {
            recordsByEpisode[updated.episodeID] = updated
            states[updated.episodeID] = updated.state
            try? await store.saveDownload(updated)
        }
        for deletedID in outcome.toDelete {
            recordsByEpisode.removeValue(forKey: deletedID)
            states.removeValue(forKey: deletedID)
            try? await store.deleteDownload(deletedID)
        }
    }

    private func allTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    private static func relativePath(for episodeID: UUID) -> String {
        "Downloads/\(episodeID.uuidString).mp3"
    }
}
