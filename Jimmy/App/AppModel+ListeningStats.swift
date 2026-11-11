import Foundation
import JimmyKit

/// Listening-time tracking and the stats `ListeningStatsView` shows, through `Store`'s
/// `listening_stats` table — replaces `ListeningStatsService`, which polled a 5-second `Timer` to
/// accumulate time into a single on-disk JSON aggregate.
extension AppModel {
    /// Call when `playback.isPlaying` flips to `true` (see `AppModel+Playback.swift`).
    func startListeningSession(podcastID: UUID?) {
        listeningSessionStartedAt = Date()
        listeningSessionPodcastID = podcastID
    }

    /// Logs the current session's elapsed time and clears it. Call when `playback.isPlaying`
    /// flips to `false`, and when the app is about to background while still playing (restarting
    /// the session right after, so a later kill doesn't lose the time played in the background).
    func flushListeningSession() {
        guard let startedAt = listeningSessionStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        listeningSessionStartedAt = nil
        // Matches `ListeningStatsService`'s own sanity check against a clock jump.
        guard elapsed > 0, elapsed < 86_400 else { return }
        let podcastID = listeningSessionPodcastID
        Task { [readyStore] in
            try? await readyStore?.addListeningSeconds(elapsed, podcastID: podcastID)
        }
    }

    /// Everything `ListeningStatsView` shows, computed from `listening_stats` + `progress` rather
    /// than a separately maintained aggregate.
    struct ListeningStatsSummary {
        var totalSeconds: TimeInterval = 0
        var weeklySeconds: TimeInterval = 0
        var currentStreakDays = 0
        var longestStreakDays = 0
        var episodesCompleted = 0
        /// Newest first, one entry per day that has any logged time.
        var dailyLogs: [JimmyKit.ListeningStat] = []
        var topPodcasts: [Store.PodcastListeningTotal] = []
    }

    func listeningStatsSummary() async -> ListeningStatsSummary {
        guard let readyStore else { return ListeningStatsSummary() }

        let dailyLogs = (try? await readyStore.listeningStatsByDay()) ?? []
        let secondsByDay = Dictionary(uniqueKeysWithValues: dailyLogs.map { ($0.date, $0.seconds) })
        let calendar = Calendar.current

        var weekly: TimeInterval = 0
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            weekly += secondsByDay[Store.dayString(date)] ?? 0
        }

        var currentStreak = 0
        var cursor = Date()
        while let seconds = secondsByDay[Store.dayString(cursor)], seconds > 0 {
            currentStreak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        var longestStreak = 0
        if let earliestDay = dailyLogs.map(\.date).min(), let earliestDate = Self.parseDay(earliestDay) {
            var runningStreak = 0
            var day = earliestDate
            let today = calendar.startOfDay(for: Date())
            while day <= today {
                if (secondsByDay[Store.dayString(day)] ?? 0) > 0 {
                    runningStreak += 1
                    longestStreak = max(longestStreak, runningStreak)
                } else {
                    runningStreak = 0
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? today.addingTimeInterval(86_400)
            }
        }

        return ListeningStatsSummary(
            totalSeconds: (try? await readyStore.totalListeningSeconds()) ?? 0,
            weeklySeconds: weekly,
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            episodesCompleted: (try? await readyStore.episodesCompletedCount()) ?? 0,
            dailyLogs: dailyLogs,
            topPodcasts: (try? await readyStore.topPodcastsByListeningTime(limit: 5)) ?? []
        )
    }

    private static func parseDay(_ dayString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.date(from: dayString)
    }
}
