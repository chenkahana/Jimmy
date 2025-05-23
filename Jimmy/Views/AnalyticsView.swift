import SwiftUI

struct AnalyticsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var analytics = AnalyticsHelper.getAnalytics()
    
    var body: some View {
        NavigationView {
            List {
                Section("Listening Stats") {
                    HStack {
                        Text("Total Listening Time")
                        Spacer()
                        Text(formatTime(analytics.totalListeningTime))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Episodes Played")
                        Spacer()
                        Text("\(analytics.episodesPlayed)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Podcasts Subscribed")
                        Spacer()
                        Text("\(analytics.podcastsSubscribed)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Most Played Podcasts") {
                    ForEach(analytics.mostPlayedPodcasts, id: \.title) { podcast in
                        HStack {
                            Text(podcast.title)
                            Spacer()
                            Text("\(podcast.playCount) episodes")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct PodcastAnalytics {
    let title: String
    let playCount: Int
}

struct Analytics {
    let totalListeningTime: Double
    let episodesPlayed: Int
    let podcastsSubscribed: Int
    let mostPlayedPodcasts: [PodcastAnalytics]
}

class AnalyticsHelper {
    static func getAnalytics() -> Analytics {
        let podcasts = PodcastService.shared.loadPodcasts()
        let queue = QueueViewModel.shared.queue
        
        let playedEpisodes = queue.filter { $0.played }
        let totalListeningTime = queue.reduce(into: 0.0) { $0 += $1.playbackPosition }
        
        // Group episodes by podcast for most played
        var podcastPlayCounts: [UUID: Int] = [:]
        for episode in playedEpisodes {
            if let podcastID = episode.podcastID {
                podcastPlayCounts[podcastID, default: 0] += 1
            }
        }
        
        let mostPlayedPodcasts = podcastPlayCounts.compactMap { (podcastID, count) in
            if let podcast = podcasts.first(where: { $0.id == podcastID }) {
                return PodcastAnalytics(title: podcast.title, playCount: count)
            }
            return nil
        }.sorted { $0.playCount > $1.playCount }.prefix(5)
        
        return Analytics(
            totalListeningTime: totalListeningTime,
            episodesPlayed: playedEpisodes.count,
            podcastsSubscribed: podcasts.count,
            mostPlayedPodcasts: Array(mostPlayedPodcasts)
        )
    }
} 