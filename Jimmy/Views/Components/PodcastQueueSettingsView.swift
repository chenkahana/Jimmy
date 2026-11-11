import SwiftUI
import os

/// Per-podcast settings for auto-adding new episodes to queue
struct PodcastQueueSettingsView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PodcastQueueSettingsView")
    let podcast: Podcast
    @State private var autoAddToQueue: Bool
    @Environment(\.dismiss) private var dismiss

    init(podcast: Podcast) {
        self.podcast = podcast
        self._autoAddToQueue = State(initialValue: podcast.autoAddToQueue)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Auto-Add New Episodes to Queue", isOn: $autoAddToQueue)
                    .onChange(of: autoAddToQueue) { newValue in
                        saveAutoAddSetting(newValue)
                    }
            } header: {
                Text("Queue Settings")
            } footer: {
                Text("When enabled, new episodes from this podcast will automatically be added to the end of your queue during background refresh.")
            }
        }
        .navigationTitle("Queue Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveAutoAddSetting(_ enabled: Bool) {
        Task {
            var updatedPodcast = podcast
            updatedPodcast.autoAddToQueue = enabled
            do {
                try await DIContainer.shared.podcastRepository.updatePodcast(updatedPodcast)
            } catch {
                logger.error("Failed to update autoAddToQueue: \(error)")
            }
        }
    }
}
