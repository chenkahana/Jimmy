import SwiftUI
import Charts

/// Dashboard showing listening statistics with weekly chart, streaks, and favorites
struct ListeningStatsView: View {
    @State private var stats: ListeningStats

    init() {
        _stats = State(initialValue: ListeningStatsService.shared.stats)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "headphones.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)

                    Text("Listening Stats")
                        .font(.title2.bold())

                    Text(formatDuration(stats.totalListeningTime) + " total listening time")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)

                // Summary Cards
                HStack(spacing: 16) {
                    StatCard(title: "Streak", value: "\(stats.currentStreakDays)", unit: "days", icon: "flame.fill", color: .orange)
                    StatCard(title: "This Week", value: formatShort(stats.weeklyTotal), unit: "", icon: "calendar", color: .blue)
                    StatCard(title: "Completed", value: "\(stats.episodesCompleted)", unit: "episodes", icon: "checkmark.circle.fill", color: .green)
                }

                // Weekly Chart
                if !stats.dailyLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last 7 Days")
                            .font(.headline)

                        Chart(last7Days()) { log in
                            BarMark(
                                x: .value("Day", shortDayLabel(log.dateString)),
                                y: .value("Minutes", log.seconds / 60)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 180)
                        .chartYAxisLabel("Minutes")
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                }

                // Longest Streak
                if stats.longestStreakDays > 0 {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                        Text("Longest streak: \(stats.longestStreakDays) days")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                // Top Podcasts
                if !stats.topPodcasts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Most Listened")
                            .font(.headline)

                        ForEach(stats.topPodcasts, id: \.podcastID) { item in
                            HStack {
                                Text(podcastName(for: item.podcastID))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatDuration(item.time))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                }

                Color.clear.frame(height: 80) // Tab bar spacing
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Listening Stats")
        .onAppear {
            stats = ListeningStatsService.shared.stats
        }
    }

    // MARK: - Helpers

    private func last7Days() -> [ListeningStats.DailyLog] {
        let calendar = Calendar.current
        var result: [ListeningStats.DailyLog] = []
        let logMap = Dictionary(uniqueKeysWithValues: stats.dailyLogs.map { ($0.dateString, $0.seconds) })

        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
            let ds = ListeningStats.dateString(for: date)
            result.append(.init(dateString: ds, seconds: logMap[ds] ?? 0))
        }
        return result
    }

    private func shortDayLabel(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateString) else { return dateString }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        return dayFormatter.string(from: date)
    }

    private func podcastName(for id: String) -> String {
        let podcasts = PodcastService.shared.loadPodcasts()
        if let uuid = UUID(uuidString: id),
           let podcast = podcasts.first(where: { $0.id == uuid }) {
            return podcast.cleanTitle
        }
        return "Unknown Podcast"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatShort(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
