import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct DownloadsTests {
    private func makeEpisode(url: URL? = URL(string: "https://example.com/\(UUID().uuidString).mp3")) -> Episode {
        Episode(title: "Test Episode", audioURL: url)
    }

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func stubbedConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DownloadStubURLProtocol.self]
        return config
    }

    private func makeSUT(
        initialRecords: [Download] = []
    ) -> (downloads: Downloads, store: FakeDownloadRecords, baseDirectory: URL) {
        let store = FakeDownloadRecords(initialRecords)
        let baseDirectory = makeTempDirectory()
        let downloads = Downloads(store: store, baseDirectory: baseDirectory, sessionConfiguration: stubbedConfiguration())
        return (downloads, store, baseDirectory)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () async -> Bool) async {
        let start = Date()
        while await !condition() {
            if Date().timeIntervalSince(start) > timeout { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Success

    @Test func successfulDownloadRecordsPathAndSizeAndWritesTheFile() async {
        let (downloads, store, baseDirectory) = makeSUT()
        let episode = makeEpisode()
        let data = Data(repeating: 0x42, count: 4_096)
        DownloadStubURLProtocol.stub(url: episode.audioURL!, data: data)
        defer { DownloadStubURLProtocol.removeStub(url: episode.audioURL!) }

        downloads.download(episode)
        await waitUntil { downloads.states[episode.id] == .done }
        await downloads.pendingWritesFinished()

        #expect(downloads.states[episode.id] == .done)
        #expect(downloads.progress[episode.id] == 1)

        let record = await store.record(for: episode.id)
        #expect(record?.state == .done)
        #expect(record?.byteCount == Int64(data.count))
        #expect(record?.relativePath == "Downloads/\(episode.id.uuidString).mp3")

        let fileURL = baseDirectory.appendingPathComponent("Downloads/\(episode.id.uuidString).mp3")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(downloads.fileURL(for: episode.id) == fileURL)
    }

    // MARK: - Failure

    @Test func failedDownloadRecordsFailedState() async {
        let (downloads, store, _) = makeSUT()
        let episode = makeEpisode()
        DownloadStubURLProtocol.stub(url: episode.audioURL!, error: URLError(.notConnectedToInternet))
        defer { DownloadStubURLProtocol.removeStub(url: episode.audioURL!) }

        downloads.download(episode)
        await waitUntil { downloads.states[episode.id] == .failed }
        await downloads.pendingWritesFinished()

        #expect(downloads.states[episode.id] == .failed)
        let record = await store.record(for: episode.id)
        #expect(record?.state == .failed)
    }

    // MARK: - Cancel

    @Test func cancelRemovesStateAndRecordWithoutLeavingAFile() async {
        let (downloads, store, baseDirectory) = makeSUT()
        let episode = makeEpisode()
        // No stub configured; the request will just never resolve during this test.

        downloads.download(episode)
        #expect(downloads.states[episode.id] == .downloading)

        downloads.cancel(episode.id)

        #expect(downloads.states[episode.id] == nil)
        #expect(downloads.progress[episode.id] == nil)
        await downloads.pendingWritesFinished()
        let record = await store.record(for: episode.id)
        #expect(record == nil)

        let fileURL = baseDirectory.appendingPathComponent("Downloads/\(episode.id.uuidString).mp3")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Delete

    @Test func deleteRemovesFileAndRecordAfterCompletion() async {
        let (downloads, store, baseDirectory) = makeSUT()
        let episode = makeEpisode()
        let data = Data(repeating: 0x1, count: 128)
        DownloadStubURLProtocol.stub(url: episode.audioURL!, data: data)
        defer { DownloadStubURLProtocol.removeStub(url: episode.audioURL!) }

        downloads.download(episode)
        await waitUntil { downloads.states[episode.id] == .done }

        downloads.delete(episode.id)

        #expect(downloads.states[episode.id] == nil)
        #expect(downloads.fileURL(for: episode.id) == nil)
        let fileURL = baseDirectory.appendingPathComponent("Downloads/\(episode.id.uuidString).mp3")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        await downloads.pendingWritesFinished()
        let record = await store.record(for: episode.id)
        #expect(record == nil)
    }

    // MARK: - fileURL

    @Test func fileURLIsNilWhenThereIsNoRecord() {
        let (downloads, _, _) = makeSUT()
        #expect(downloads.fileURL(for: UUID()) == nil)
    }

    @Test func fileURLIsNilWhenTheRecordedFileIsMissing() async {
        let episodeID = UUID()
        // `.failed` so the relaunch reconciler (tested separately below) leaves this record
        // alone — this test is only about `fileURL` resolving a path to a missing file.
        let record = Download(episodeID: episodeID, relativePath: "Downloads/\(episodeID.uuidString).mp3", state: .failed, updatedAt: Date())
        let store = FakeDownloadRecords([record])
        let baseDirectory = makeTempDirectory()
        let downloads = Downloads(store: store, baseDirectory: baseDirectory, sessionConfiguration: stubbedConfiguration())

        await waitUntil { downloads.states[episodeID] != nil }

        #expect(downloads.fileURL(for: episodeID) == nil)
    }

    // MARK: - Relaunch reconciliation

    @Test func reconcileMarksADanglingDownloadingRecordAsFailed() async {
        let episodeID = UUID()
        let record = Download(episodeID: episodeID, relativePath: "Downloads/\(episodeID.uuidString).mp3", state: .downloading, updatedAt: Date.distantPast)
        let store = FakeDownloadRecords([record])
        let baseDirectory = makeTempDirectory()
        let downloads = Downloads(store: store, baseDirectory: baseDirectory, sessionConfiguration: stubbedConfiguration())

        await waitUntil { downloads.states[episodeID] == .failed }

        #expect(downloads.states[episodeID] == .failed)
        let updated = await store.record(for: episodeID)
        #expect(updated?.state == .failed)
    }

    @Test func reconcileDeletesADoneRecordWhoseFileIsGone() async {
        let episodeID = UUID()
        let record = Download(episodeID: episodeID, relativePath: "Downloads/\(episodeID.uuidString).mp3", state: .done, updatedAt: Date())
        let store = FakeDownloadRecords([record])
        let baseDirectory = makeTempDirectory()
        let downloads = Downloads(store: store, baseDirectory: baseDirectory, sessionConfiguration: stubbedConfiguration())

        // `states[episodeID]` starts out `nil` (the key is simply absent) before the async
        // reconcile pass has even run, so wait on the store — which starts non-empty — instead.
        await waitUntil { await store.record(for: episodeID) == nil }

        #expect(downloads.states[episodeID] == nil)
        let updated = await store.record(for: episodeID)
        #expect(updated == nil)
    }

    @Test func reconcileLeavesADoneRecordAloneWhenItsFileIsStillThere() async {
        let episodeID = UUID()
        let relativePath = "Downloads/\(episodeID.uuidString).mp3"
        let record = Download(episodeID: episodeID, relativePath: relativePath, state: .done, updatedAt: Date())
        let store = FakeDownloadRecords([record])
        let baseDirectory = makeTempDirectory()
        let downloadsDir = baseDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: baseDirectory.appendingPathComponent(relativePath).path, contents: Data([0x1]))

        let downloads = Downloads(store: store, baseDirectory: baseDirectory, sessionConfiguration: stubbedConfiguration())

        await waitUntil { downloads.states[episodeID] != nil }
        // Give the async reconcile pass a further moment to run (it would, incorrectly, remove
        // this record if it mis-detected the file as missing).
        try? await Task.sleep(nanoseconds: 150_000_000)

        #expect(downloads.states[episodeID] == .done)
        let stillThere = await store.record(for: episodeID)
        #expect(stillThere != nil)
    }

    // MARK: - Background events

    @Test func backgroundEventsCompletionIsCalledExactlyOnce() async {
        let (downloads, _, _) = makeSUT()
        let counter = CallCounter()

        downloads.handleBackgroundEvents(identifier: Downloads.sessionIdentifier) {
            Task { await counter.increment() }
        }
        downloads.completeBackgroundEvents()
        downloads.completeBackgroundEvents()

        try? await Task.sleep(nanoseconds: 100_000_000) // let the above Tasks get a chance to run

        #expect(await counter.count == 1)
    }

    @Test func backgroundEventsWithAnUnrecognizedIdentifierIsIgnored() async {
        let (downloads, _, _) = makeSUT()
        let counter = CallCounter()

        downloads.handleBackgroundEvents(identifier: "some.other.session") {
            Task { await counter.increment() }
        }
        downloads.completeBackgroundEvents()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(await counter.count == 0)
    }
}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
