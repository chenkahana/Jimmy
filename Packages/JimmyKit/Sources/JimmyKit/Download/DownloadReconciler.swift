import Foundation

/// Pure reconciliation logic for `Download` records against the background session's live
/// tasks, run once at launch to detect state that diverged while the app wasn't running (a
/// download that was in flight when the app was killed, or a file removed from under us).
/// Kept separate from `Downloads`/`URLSessionDownloadDelegate` so it can be unit tested without
/// a real `URLSession`.
nonisolated enum DownloadReconciler {
    struct Outcome {
        /// Records to persist (and to reflect in observable state) because they diverged.
        var toSave: [Download] = []
        /// Episode IDs whose record should be deleted entirely (file is gone).
        var toDelete: [UUID] = []
    }

    /// - Parameters:
    ///   - records: every persisted `Download`, as of launch.
    ///   - runningEpisodeIDs: episode IDs with a live task in the background session right now.
    ///   - fileExists: whether `record`'s file is present on disk.
    ///   - now: injected so tests don't depend on wall-clock time.
    static func reconcile(
        records: [Download],
        runningEpisodeIDs: Set<UUID>,
        fileExists: (Download) -> Bool,
        now: Date
    ) -> Outcome {
        var outcome = Outcome()
        for record in records {
            switch record.state {
            case .downloading, .queued:
                guard !runningEpisodeIDs.contains(record.episodeID) else { continue }
                var failed = record
                failed.state = .failed
                failed.updatedAt = now
                outcome.toSave.append(failed)

            case .done:
                guard !fileExists(record) else { continue }
                outcome.toDelete.append(record.episodeID)

            case .failed:
                continue
            }
        }
        return outcome
    }
}
