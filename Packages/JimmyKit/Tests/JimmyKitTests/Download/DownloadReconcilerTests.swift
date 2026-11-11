import Foundation
import Testing
@testable import JimmyKit

struct DownloadReconcilerTests {
    private let now = Date()

    private func makeDownload(state: DownloadState) -> Download {
        Download(episodeID: UUID(), relativePath: "Downloads/x.mp3", state: state, updatedAt: Date.distantPast)
    }

    @Test func downloadingRecordWithNoRunningTaskBecomesFailed() {
        let record = makeDownload(state: .downloading)

        let outcome = DownloadReconciler.reconcile(
            records: [record],
            runningEpisodeIDs: [],
            fileExists: { _ in false },
            now: now
        )

        #expect(outcome.toSave.map(\.episodeID) == [record.episodeID])
        #expect(outcome.toSave.first?.state == .failed)
        #expect(outcome.toSave.first?.updatedAt == now)
        #expect(outcome.toDelete.isEmpty)
    }

    @Test func downloadingRecordWithARunningTaskIsLeftAlone() {
        let record = makeDownload(state: .downloading)

        let outcome = DownloadReconciler.reconcile(
            records: [record],
            runningEpisodeIDs: [record.episodeID],
            fileExists: { _ in false },
            now: now
        )

        #expect(outcome.toSave.isEmpty)
        #expect(outcome.toDelete.isEmpty)
    }

    @Test func queuedRecordWithNoRunningTaskBecomesFailed() {
        let record = makeDownload(state: .queued)

        let outcome = DownloadReconciler.reconcile(
            records: [record],
            runningEpisodeIDs: [],
            fileExists: { _ in false },
            now: now
        )

        #expect(outcome.toSave.first?.state == .failed)
    }

    @Test func doneRecordWhoseFileIsGoneIsDeleted() {
        let record = makeDownload(state: .done)

        let outcome = DownloadReconciler.reconcile(
            records: [record],
            runningEpisodeIDs: [],
            fileExists: { _ in false },
            now: now
        )

        #expect(outcome.toDelete == [record.episodeID])
        #expect(outcome.toSave.isEmpty)
    }

    @Test func doneRecordWhoseFileExistsIsLeftAlone() {
        let record = makeDownload(state: .done)

        let outcome = DownloadReconciler.reconcile(
            records: [record],
            runningEpisodeIDs: [],
            fileExists: { _ in true },
            now: now
        )

        #expect(outcome.toDelete.isEmpty)
        #expect(outcome.toSave.isEmpty)
    }

    @Test func failedRecordIsLeftAlone() {
        let record = makeDownload(state: .failed)

        let outcome = DownloadReconciler.reconcile(
            records: [record],
            runningEpisodeIDs: [],
            fileExists: { _ in false },
            now: now
        )

        #expect(outcome.toDelete.isEmpty)
        #expect(outcome.toSave.isEmpty)
    }
}
