import Foundation

/// Aggregate listening statistics — persisted as JSON via FileStorage
struct ListeningStats: Codable {
    var totalListeningTime: TimeInterval = 0
    var dailyLogs: [DailyLog] = []
    var perPodcast: [String: TimeInterval] = [:]  // podcastID -> seconds
    var currentStreakDays: Int = 0
    var longestStreakDays: Int = 0
    var lastListenedDate: Date?
    var episodesCompleted: Int = 0

    struct DailyLog: Codable, Identifiable {
        var id: String { dateString }
        let dateString: String  // "yyyy-MM-dd"
        var seconds: TimeInterval
    }

    // MARK: - Computed

    var todayLog: DailyLog? {
        dailyLogs.first { $0.dateString == Self.todayString() }
    }

    var weeklyTotal: TimeInterval {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        let cutoff = Self.dateString(for: sevenDaysAgo)
        return dailyLogs.filter { $0.dateString >= cutoff }.reduce(0) { $0 + $1.seconds }
    }

    var topPodcasts: [(podcastID: String, time: TimeInterval)] {
        perPodcast.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    // MARK: - Mutation

    mutating func addListeningTime(_ seconds: TimeInterval, podcastID: String?) {
        totalListeningTime += seconds

        // Update daily log
        let today = Self.todayString()
        if let index = dailyLogs.firstIndex(where: { $0.dateString == today }) {
            dailyLogs[index].seconds += seconds
        } else {
            dailyLogs.append(DailyLog(dateString: today, seconds: seconds))
        }

        // Trim to last 90 days
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let cutoff = Self.dateString(for: cutoffDate)
        dailyLogs.removeAll { $0.dateString < cutoff }

        // Per-podcast tracking
        if let pid = podcastID {
            perPodcast[pid, default: 0] += seconds
        }

        // Streak calculation
        updateStreak()
    }

    mutating func markEpisodeCompleted() {
        episodesCompleted += 1
    }

    // MARK: - Streak

    private mutating func updateStreak() {
        let today = Self.todayString()
        let calendar = Calendar.current
        let listenDates = Set(dailyLogs.map { $0.dateString })

        var streak = 0
        var date = Date()
        while listenDates.contains(Self.dateString(for: date)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }

        currentStreakDays = streak
        longestStreakDays = max(longestStreakDays, streak)
        lastListenedDate = Date()
    }

    // MARK: - Helpers

    static func todayString() -> String {
        dateString(for: Date())
    }

    static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
