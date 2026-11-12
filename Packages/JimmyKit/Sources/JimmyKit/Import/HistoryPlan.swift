import Foundation

/// What to write for one imported episode once it's matched to a feed episode.
public nonisolated enum HistoryAction: Sendable, Hashable {
    case markPlayed(UUID)
    case saveProgress(Progress)
}

/// An episode the Queue should get, and when the listener last touched it.
public nonisolated struct QueueCandidate: Sendable, Hashable {
    public let episodeID: UUID
    public let date: Date
}

/// Turns another app's listening history into writes against the store, plus the Queue it
/// implies: episodes started there, and episodes saved for later, most recent first.
public nonisolated struct HistoryPlan: Sendable, Hashable {
    public var actions: [HistoryAction] = []
    /// Most recent first.
    public var queue: [QueueCandidate] = []
    public var playedCount = 0
    public var inProgressCount = 0
    public var unmatchedCount = 0

    public init() {}

    /// - Parameters:
    ///   - states: history entries for one show. Several entries for one episode (a saved
    ///     episode plus its streaming history, say) are combined.
    ///   - episodes: that show's episodes, as stored after subscribing.
    ///   - existing: progress Jimmy already has. A finished episode, or one Jimmy touched
    ///     more recently than the other app, is left alone.
    public static func make(
        states: [ImportedEpisodeState],
        episodes: [Episode],
        existing: [UUID: Progress] = [:],
        now: Date = Date()
    ) -> HistoryPlan {
        var plan = HistoryPlan()
        var merged: [UUID: ImportedEpisodeState] = [:]
        var order: [Episode] = []

        for state in states {
            guard let episode = EpisodeMatcher.match(state, in: episodes) else {
                plan.unmatchedCount += 1
                continue
            }
            if let earlier = merged[episode.id] {
                merged[episode.id] = earlier.combined(with: state)
            } else {
                merged[episode.id] = state
                order.append(episode)
            }
        }

        var queued: [QueueCandidate] = []
        for episode in order {
            guard let state = merged[episode.id] else { continue }
            let importedDate = state.updatedAt ?? now
            if let current = existing[episode.id],
               current.isFinished || (current.position > 0 && current.updatedAt >= importedDate) {
                continue
            }

            let position = state.position ?? 0
            if state.isPlayed || Progress.isFinished(position: position, duration: episode.duration) {
                plan.actions.append(.markPlayed(episode.id))
                plan.playedCount += 1
                continue
            }
            if position > 0 {
                plan.actions.append(.saveProgress(Progress(
                    episodeID: episode.id,
                    position: position,
                    duration: episode.duration,
                    updatedAt: importedDate
                )))
                plan.inProgressCount += 1
            }
            if position > 0 || state.isQueued {
                queued.append(QueueCandidate(episodeID: episode.id, date: state.updatedAt ?? episode.publishedDate ?? .distantPast))
            }
        }

        plan.queue = queued.sorted { $0.date > $1.date }
        return plan
    }
}

nonisolated extension ImportedEpisodeState {
    /// Two entries for the same episode as one: played or queued if either says so, the
    /// furthest position, the latest touch.
    func combined(with other: ImportedEpisodeState) -> ImportedEpisodeState {
        var result = self
        result.isPlayed = isPlayed || other.isPlayed
        result.isQueued = isQueued || other.isQueued
        result.position = [position, other.position].compactMap(\.self).max()
        result.updatedAt = [updatedAt, other.updatedAt].compactMap(\.self).max()
        result.enclosureURL = enclosureURL ?? other.enclosureURL
        result.publishedDate = publishedDate ?? other.publishedDate
        return result
    }
}
