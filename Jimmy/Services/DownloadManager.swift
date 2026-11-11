import Foundation
import Combine
import os.log

// MARK: - Download State

enum DownloadState: Equatable {
    case notDownloaded
    case queued
    case downloading(progress: Double)
    case downloaded(localURL: URL)
    case failed(error: String)

    var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }

    var isActive: Bool {
        switch self {
        case .queued, .downloading: return true
        default: return false
        }
    }

    static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.queued, .queued): return true
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.downloaded(let a), .downloaded(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Download Manager

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    // MARK: - Published State

    @Published private(set) var downloadStates: [UUID: DownloadState] = [:]
    @Published private(set) var totalStorageUsed: Int64 = 0

    // MARK: - Private

    private var urlSession: URLSession!
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var resumeData: [UUID: Data] = [:]
    private var pendingQueue: [Episode] = []
    private let maxConcurrent = 3
    private let queue = DispatchQueue(label: "com.jimmy.downloadmanager", qos: .utility)
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "DownloadManager")

    private var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.chenkahana.Jimmy.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        Task.detached(priority: .utility) { [weak self] in
            await self?.restoreDownloadedFiles()
        }
    }

    // MARK: - Public API

    func downloadState(for episode: Episode) -> DownloadState {
        downloadStates[episode.id] ?? .notDownloaded
    }

    func download(_ episode: Episode) {
        queue.async { [weak self] in
            guard let self else { return }
            guard episode.audioURL != nil else { return }
            let state = self.downloadStates[episode.id] ?? .notDownloaded
            guard !state.isActive && !state.isDownloaded else { return }

            DispatchQueue.main.async {
                self.downloadStates[episode.id] = .queued
            }
            self.pendingQueue.append(episode)
            self.drainQueue()
        }
    }

    func cancelDownload(for episode: Episode) {
        queue.async { [weak self] in
            guard let self else { return }
            if let task = self.activeTasks[episode.id] {
                task.cancel { resumeData in
                    self.queue.async {
                        if let data = resumeData {
                            self.resumeData[episode.id] = data
                        }
                        self.activeTasks.removeValue(forKey: episode.id)
                        DispatchQueue.main.async {
                            self.downloadStates[episode.id] = .notDownloaded
                        }
                        self.drainQueue()
                    }
                }
            } else {
                self.pendingQueue.removeAll { $0.id == episode.id }
                DispatchQueue.main.async {
                    self.downloadStates[episode.id] = .notDownloaded
                }
            }
        }
    }

    func deleteDownload(for episode: Episode) {
        queue.async { [weak self] in
            guard let self else { return }
            cancelDownload(for: episode)
            let localURL = localFileURL(for: episode)
            try? FileManager.default.removeItem(at: localURL)
            DispatchQueue.main.async {
                self.downloadStates[episode.id] = .notDownloaded
                self.recalculateStorage()
            }
        }
    }

    func localFileURL(for episode: Episode) -> URL {
        downloadsDirectory.appendingPathComponent("\(episode.id.uuidString).mp3")
    }

    func isDownloaded(_ episode: Episode) -> Bool {
        downloadStates[episode.id]?.isDownloaded ?? false
    }

    /// Returns local URL if available, otherwise the remote URL
    func effectiveURL(for episode: Episode) -> URL? {
        effectiveURL(forEpisodeID: episode.id, remoteURL: episode.audioURL)
    }

    /// Same lookup as `effectiveURL(for:)`, keyed by id directly — for callers (e.g. `AppModel`,
    /// playing a `JimmyKit.Episode`) that don't have the old, richer `Episode` type on hand.
    func effectiveURL(forEpisodeID id: UUID, remoteURL: URL?) -> URL? {
        if case .downloaded(let url) = downloadStates[id] {
            return url
        }
        return remoteURL
    }

    // MARK: - Private Helpers

    private func drainQueue() {
        let activeCount = activeTasks.count
        guard activeCount < maxConcurrent, !pendingQueue.isEmpty else { return }

        let slotsAvailable = maxConcurrent - activeCount
        let toStart = Array(pendingQueue.prefix(slotsAvailable))
        pendingQueue.removeFirst(min(slotsAvailable, pendingQueue.count))

        for episode in toStart {
            startDownload(for: episode)
        }
    }

    private func startDownload(for episode: Episode) {
        guard let url = episode.audioURL else { return }

        let task: URLSessionDownloadTask
        if let data = resumeData[episode.id] {
            task = urlSession.downloadTask(withResumeData: data)
            resumeData.removeValue(forKey: episode.id)
        } else {
            task = urlSession.downloadTask(with: url)
        }
        task.taskDescription = episode.id.uuidString
        activeTasks[episode.id] = task
        DispatchQueue.main.async {
            self.downloadStates[episode.id] = .downloading(progress: 0)
        }
        task.resume()
        logger.info("Started download for episode: \(episode.title)")
    }

    private func restoreDownloadedFiles() async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return }

        var states: [UUID: DownloadState] = [:]
        var total: Int64 = 0

        for file in files where file.pathExtension == "mp3" {
            let name = file.deletingPathExtension().lastPathComponent
            if let uuid = UUID(uuidString: name) {
                states[uuid] = .downloaded(localURL: file)
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }

        await MainActor.run {
            for (id, state) in states {
                self.downloadStates[id] = state
            }
            self.totalStorageUsed = total
        }
    }

    private func recalculateStorage() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            totalStorageUsed = 0
            return
        }
        var total: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        totalStorageUsed = total
    }

    private func episodeID(from task: URLSessionTask) -> UUID? {
        guard let desc = task.taskDescription else { return nil }
        return UUID(uuidString: desc)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let episodeID = episodeID(from: downloadTask) else { return }
        let destination = downloadsDirectory.appendingPathComponent("\(episodeID.uuidString).mp3")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            queue.async { [weak self] in
                guard let self else { return }
                self.activeTasks.removeValue(forKey: episodeID)
                DispatchQueue.main.async {
                    self.downloadStates[episodeID] = .downloaded(localURL: destination)
                    self.recalculateStorage()
                }
                self.drainQueue()
            }
            logger.info("Download completed for episode \(episodeID.uuidString)")
        } catch {
            logger.error("Failed to move downloaded file: \(error.localizedDescription)")
            queue.async { [weak self] in
                guard let self else { return }
                self.activeTasks.removeValue(forKey: episodeID)
                DispatchQueue.main.async {
                    self.downloadStates[episodeID] = .failed(error: error.localizedDescription)
                }
                self.drainQueue()
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let episodeID = episodeID(from: downloadTask) else { return }
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0
        }
        DispatchQueue.main.async {
            self.downloadStates[episodeID] = .downloading(progress: progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        guard let episodeID = episodeID(from: task) else { return }
        let nsError = error as NSError
        queue.async { [weak self] in
            guard let self else { return }
            // Store resume data if available
            if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                self.resumeData[episodeID] = data
            }
            self.activeTasks.removeValue(forKey: episodeID)
            DispatchQueue.main.async {
                // Only mark as failed if not cancelled (cancelled == user intent)
                if nsError.code != NSURLErrorCancelled {
                    self.downloadStates[episodeID] = .failed(error: error.localizedDescription)
                }
            }
            self.drainQueue()
        }
    }
}
