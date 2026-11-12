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
    ///   - states: history entries for one show.
    ///   - episodes: that show's episodes, as stored after subscribing.
    public static func make(states: [ImportedEpisodeState], episodes: [Episode], now: Date = Date()) -> HistoryPlan {
        var plan = HistoryPlan()
        var seen = Set<UUID>()
        var queued: [QueueCandidate] = []

        for state in states {
            guard let episode = EpisodeMatcher.match(state, in: episodes) else {
                plan.unmatchedCount += 1
                continue
            }
            guard seen.insert(episode.id).inserted else { continue }

            let position = state.position ?? 0
            let finished = state.isPlayed || Progress.isFinished(position: position, duration: episode.duration)
            if finished {
                plan.actions.append(.markPlayed(episode.id))
                plan.playedCount += 1
                continue
            }
            if position > 0 {
                plan.actions.append(.saveProgress(Progress(
                    episodeID: episode.id,
                    position: position,
                    duration: episode.duration,
                    updatedAt: state.updatedAt ?? now
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
