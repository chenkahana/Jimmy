import SwiftUI
import Charts
import JimmyKit

/// Listening statistics as a list: totals, streaks, a weekly chart and most-listened shows — computed
/// from `AppModel.listeningStatsSummary()` (`Store`'s `listening_stats`/`progress` tables) rather
/// than a separately maintained JSON aggregate.
struct ListeningStatsView: View {
    @State private var summary = AppModel.ListeningStatsSummary()

    var body: some View {
        List {
            Section {
                LabeledContent("Total Listening", value: formatDuration(summary.totalSeconds))
                LabeledContent("This Week", value: formatDuration(summary.weeklySeconds))
                LabeledContent("Current Streak", value: days(summary.currentStreakDays))
                LabeledContent("Longest Streak", value: days(summary.longestStreakDays))
                LabeledContent("Episodes Completed", value: "\(summary.episodesCompleted)")
            }
            .monospacedDigit()

            if !summary.dailyLogs.isEmpty {
                Section("Last 7 Days") {
                    Chart(last7Days()) { log in
                        BarMark(
                            x: .value("Day", shortDayLabel(log.date)),
                            y: .value("Minutes", log.seconds / 60)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .chartYAxisLabel("Minutes")
                    .frame(minHeight: 180)
                    .padding(.vertical, 8)
                }
            }

            if !summary.topPodcasts.isEmpty {
                Section("Most Listened") {
                    ForEach(summary.topPodcasts, id: \.podcastID) { item in
                        LabeledContent(podcastName(for: item.podcastID), value: formatDuration(item.seconds))
                            .monospacedDigit()
                    }
                }
            }
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

    private func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        }
        return "\(minutes) min"
    }
}
