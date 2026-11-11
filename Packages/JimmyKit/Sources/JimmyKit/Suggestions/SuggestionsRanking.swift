import Foundation

/// One ranked "up next" candidate: an unplayed episode from a subscribed show, plus the signals
/// that produced its score — so a caller (the Suggestions screen) can build a plain-language
/// reason without re-deriving them from `progress` itself.
public nonisolated struct UpNextSuggestion: Sendable, Hashable, Identifiable {
    public var id: UUID { episode.id }
    public let episode: Episode
    public let podcastID: UUID
    public let score: Double
    /// How many episodes of this episode's show the user has finished.
    public let finishedCountForShow: Int
    /// Whether this exact episode already has progress (started, not finished) — "pick up where
    /// you left off" rather than a fresh recommendation.
    public let isInProgress: Bool

    public init(episode: Episode, podcastID: UUID, score: Double, finishedCountForShow: Int, isInProgress: Bool) {
        self.episode = episode
        self.podcastID = podcastID
        self.score = score
        self.finishedCountForShow = finishedCountForShow
        self.isInProgress = isInProgress
    }
}

/// Ranks "up next" and seeds "new shows like the ones you finish" from listening history —
/// `progress`, and (when a row carries one) `listening_stats`'s `podcastID` — never a network
/// call and never touches the clock except through `now`, so both are plain unit-testable
/// functions with no `Store` involved.
public nonisolated enum SuggestionsRanker {
    /// Ranks unplayed episodes from subscribed shows: shows finished most, how recently a show
    /// was last finished, an episode already started (but not finished), and an episode's
    /// duration being close to what the user usually finishes.
    public static func rankUpNext(
        episodes: [Episode],
        podcasts: [Podcast],
        progress: [Progress],
        listeningStats: [ListeningStat] = [],
        excluding excludedEpisodeIDs: Set<UUID> = [],
        now: Date = Date(),
        limit: Int = 10
    ) -> [UpNextSuggestion] {
        guard !episodes.isEmpty else { return [] }

        let signals = ShowSignals(episodes: episodes, progress: progress, listeningStats: listeningStats, now: now)
        let progressByEpisode = Dictionary(uniqueKeysWithValues: progress.map { ($0.episodeID, $0) })

        let candidates = episodes.filter { episode in
            guard episode.podcastID != nil, !excludedEpisodeIDs.contains(episode.id) else { return false }
            return progressByEpisode[episode.id]?.isFinished != true
        }

        let scored: [UpNextSuggestion] = candidates.map { episode in
            let podcastID = episode.podcastID! // filtered above
            let episodeProgress = progressByEpisode[episode.id]
            let isInProgress = (episodeProgress?.position ?? 0) > 0 && episodeProgress?.isFinished != true
            let score = signals.score(podcastID: podcastID, episodeDuration: episode.duration, isInProgress: isInProgress)
            return UpNextSuggestion(
                episode: episode,
                podcastID: podcastID,
                score: score,
                finishedCountForShow: signals.finishedCount(forPodcast: podcastID),
                isInProgress: isInProgress
            )
        }

        return Array(
            scored
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    let lhsDate = lhs.episode.publishedDate ?? .distantPast
                    let rhsDate = rhs.episode.publishedDate ?? .distantPast
                    if lhsDate != rhsDate { return lhsDate > rhsDate }
                    return lhs.episode.title < rhs.episode.title
                }
                .prefix(limit)
        )
    }

    /// Seed queries for "new shows like the ones you finish": the authors of the subscribed shows
    /// the user finishes most (ties broken by how recently), skipping any show with no finished
    /// episode, falling back to the show's own title when its author is blank, and never
    /// repeating the same seed twice.
    public static func seedQueries(
        podcasts: [Podcast],
        episodes: [Episode],
        progress: [Progress],
        limit: Int = 3
    ) -> [String] {
        let signals = ShowSignals(episodes: episodes, progress: progress, listeningStats: [], now: Date())

        let ranked = podcasts
            .map { podcast in
                (podcast: podcast, count: signals.finishedCount(forPodcast: podcast.id), lastFinished: signals.lastFinishedDate(forPodcast: podcast.id))
            }
            .filter { $0.count > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return (lhs.lastFinished ?? .distantPast) > (rhs.lastFinished ?? .distantPast)
            }

        var seen = Set<String>()
        var seeds: [String] = []
        for entry in ranked {
            let author = entry.podcast.author.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = entry.podcast.cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = !author.isEmpty ? author : title
            guard !candidate.isEmpty else { continue }
            let key = candidate.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            seeds.append(candidate)
            if seeds.count == limit { break }
        }
        return seeds
    }
}

/// Precomputed per-podcast listening signals, shared by `rankUpNext` and `seedQueries` so every
/// episode/podcast lookup during ranking is O(1) instead of re-scanning `progress` each time.
private nonisolated struct ShowSignals {
    private let lastFinishedDates: [UUID: Date]
    private let finishedCounts: [UUID: Int]
    private let recentListeningSeconds: [UUID: TimeInterval]
    private let maxFinishedCount: Int
    private let maxRecentSeconds: TimeInterval
    private let averageFinishedDuration: TimeInterval?
    private let now: Date

    /// Listening in the last two weeks counts toward "recently into this show" alongside
    /// `progress`'s own finished dates.
    private static let recentListeningWindow: TimeInterval = 14 * 24 * 60 * 60
    /// A show finished this many days ago or longer no longer gets a recency boost.
    private static let recencyHorizonDays: Double = 30

    init(episodes: [Episode], progress: [Progress], listeningStats: [ListeningStat], now: Date) {
        self.now = now
        let podcastIDByEpisode: [UUID: UUID] = Dictionary(
            uniqueKeysWithValues: episodes.compactMap { episode in episode.podcastID.map { (episode.id, $0) } }
        )

        var finishedCounts: [UUID: Int] = [:]
        var lastFinishedDates: [UUID: Date] = [:]
        var finishedDurations: [TimeInterval] = []

        for entry in progress where entry.isFinished {
            guard let podcastID = podcastIDByEpisode[entry.episodeID] else { continue }
            finishedCounts[podcastID, default: 0] += 1
            lastFinishedDates[podcastID] = max(lastFinishedDates[podcastID] ?? .distantPast, entry.updatedAt)
            if let duration = entry.duration, duration > 0 {
                finishedDurations.append(duration)
            }
        }

        var recentListeningSeconds: [UUID: TimeInterval] = [:]
        for stat in listeningStats {
            guard let podcastID = stat.podcastID, let statDate = Self.dayFormatter.date(from: stat.date) else { continue }
            guard now.timeIntervalSince(statDate) <= Self.recentListeningWindow else { continue }
            recentListeningSeconds[podcastID, default: 0] += stat.seconds
        }

        self.finishedCounts = finishedCounts
        self.lastFinishedDates = lastFinishedDates
        self.recentListeningSeconds = recentListeningSeconds
        self.maxFinishedCount = finishedCounts.values.max() ?? 0
        self.maxRecentSeconds = recentListeningSeconds.values.max() ?? 0
        self.averageFinishedDuration = finishedDurations.isEmpty ? nil : finishedDurations.reduce(0, +) / Double(finishedDurations.count)
    }

    func finishedCount(forPodcast podcastID: UUID) -> Int {
        finishedCounts[podcastID] ?? 0
    }

    func lastFinishedDate(forPodcast podcastID: UUID) -> Date? {
        lastFinishedDates[podcastID]
    }

    /// Weighted sum of every signal; only the relative ordering matters; weights aren't
    /// normalized to any particular range.
    func score(podcastID: UUID, episodeDuration: TimeInterval?, isInProgress: Bool) -> Double {
        let finishedScore = maxFinishedCount > 0 ? Double(finishedCount(forPodcast: podcastID)) / Double(maxFinishedCount) : 0

        let recencyScore: Double
        if let lastFinished = lastFinishedDates[podcastID] {
            let days = max(0, now.timeIntervalSince(lastFinished) / 86_400)
            recencyScore = max(0, 1 - days / Self.recencyHorizonDays)
        } else {
            recencyScore = 0
        }

        let recentListeningScore = maxRecentSeconds > 0 ? (recentListeningSeconds[podcastID] ?? 0) / maxRecentSeconds : 0

        let durationScore: Double
        if let episodeDuration, episodeDuration > 0, let average = averageFinishedDuration, average > 0 {
            durationScore = max(0, 1 - min(1, abs(episodeDuration - average) / average))
        } else {
            // Neutral, rather than penalizing an episode (or a user) with no duration history.
            durationScore = 0.5
        }

        let inProgressBoost = isInProgress ? 1.0 : 0.0

        return (3.0 * finishedScore) + (2.0 * recencyScore) + (1.0 * recentListeningScore) + (1.0 * durationScore) + (5.0 * inProgressBoost)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
