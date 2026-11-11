import SwiftUI
import Charts
import JimmyKit

/// Dashboard showing listening statistics with weekly chart, streaks, and favorites — computed
/// from `AppModel.listeningStatsSummary()` (`Store`'s `listening_stats`/`progress` tables) rather
/// than a separately maintained JSON aggregate.
struct ListeningStatsView: View {
    @State private var summary = AppModel.ListeningStatsSummary()

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

                    Text(formatDuration(summary.totalSeconds) + " total listening time")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)

                // Summary Cards
                HStack(spacing: 16) {
                    StatCard(title: "Streak", value: "\(summary.currentStreakDays)", unit: "days", icon: "flame.fill", color: .orange)
                    StatCard(title: "This Week", value: formatShort(summary.weeklySeconds), unit: "", icon: "calendar", color: .blue)
                    StatCard(title: "Completed", value: "\(summary.episodesCompleted)", unit: "episodes", icon: "checkmark.circle.fill", color: .green)
                }

                // Weekly Chart
                if !summary.dailyLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last 7 Days")
                            .font(.headline)

                        Chart(last7Days()) { log in
                            BarMark(
                                x: .value("Day", shortDayLabel(log.date)),
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
                if summary.longestStreakDays > 0 {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                        Text("Longest streak: \(summary.longestStreakDays) days")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                // Top Podcasts
                if !summary.topPodcasts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Most Listened")
                            .font(.headline)

                        ForEach(summary.topPodcasts, id: \.podcastID) { item in
                            HStack {
                                Text(podcastName(for: item.podcastID))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatDuration(item.seconds))
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
        .task { summary = await AppModel.current?.listeningStatsSummary() ?? summary }
        .refreshable { summary = await AppModel.current?.listeningStatsSummary() ?? summary }
    }

    // MARK: - Helpers

    private func last7Days() -> [JimmyKit.ListeningStat] {
        let calendar = Calendar.current
        let logMap = Dictionary(uniqueKeysWithValues: summary.dailyLogs.map { ($0.date, $0.seconds) })

        var result: [JimmyKit.ListeningStat] = []
        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
            let dayString = Store.dayString(date)
            result.append(JimmyKit.ListeningStat(date: dayString, seconds: logMap[dayString] ?? 0))
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

    private func podcastName(for id: UUID) -> String {
        if let podcast = AppModel.current?.podcasts.first(where: { $0.id == id }) {
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
