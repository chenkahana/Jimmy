import SwiftUI

struct EpisodeListView: View {
    let podcast: Podcast
    let episodes: [Episode]
    let isLoading: Bool
    let onEpisodeTap: (Episode) -> Void
    
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @ObservedObject private var episodeViewModel = EpisodeViewModel.shared
    @ObservedObject private var queueViewModel = QueueViewModel.shared
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading episodes...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if episodes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No Episodes Found")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("This podcast doesn't have any episodes yet")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(episodes) { episode in
                            EpisodeRowView(
                                episode: episode,
                                podcast: podcast,
                                isCurrentlyPlaying: currentPlayingEpisode?.id == episode.id,
                                onTap: {
                                    onEpisodeTap(episode)
                                },
                                onPlayNext: { episode in
                                    handlePlayNext(episode)
                                },
                                onMarkAsPlayed: { episode, played in
                                    episodeViewModel.markEpisodeAsPlayed(episode, played: played)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(podcast.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            markAllAsPlayed()
                        }) {
                            Label("Mark All as Played", systemImage: "checkmark.circle")
                        }
                        
                        Button(action: {
                            markAllAsUnplayed()
                        }) {
                            Label("Mark All as Unplayed", systemImage: "circle")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            addAllToQueue()
                        }) {
                            Label("Add All to Queue", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handlePlayNext(_ episode: Episode) {
        // Insert episode at the beginning of the queue for "play next"
        queueViewModel.queue.insert(episode, at: 0)
        queueViewModel.saveQueue()
        
        // Show success feedback
        FeedbackManager.shared.playNext()
        
        // Optional: Show a toast or some visual feedback
        showPlayNextFeedback(for: episode)
    }
    
    private func markAllAsPlayed() {
        episodeViewModel.markAllEpisodesAsPlayed(for: podcast.id)
        
        // Show haptic feedback
        FeedbackManager.shared.success()
    }
    
    private func markAllAsUnplayed() {
        episodeViewModel.markAllEpisodesAsUnplayed(for: podcast.id)
        
        // Show haptic feedback
        FeedbackManager.shared.success()
    }
    
    private func addAllToQueue() {
        // Add episodes that aren't already in the queue
        let currentQueueIDs = Set(queueViewModel.queue.map { $0.id })
        let episodesToAdd = episodes.filter { !currentQueueIDs.contains($0.id) }
        
        for episode in episodesToAdd {
            queueViewModel.addToQueue(episode)
        }
        
        // Show haptic feedback
        FeedbackManager.shared.success()
        
        // Optional: Show feedback about how many episodes were added
        showAddToQueueFeedback(count: episodesToAdd.count)
    }
    
    private func showPlayNextFeedback(for episode: Episode) {
        // This could show a temporary toast or banner
        // For now, we'll just use the haptic feedback
        // You could implement a toast notification system here
    }
    
    private func showAddToQueueFeedback(count: Int) {
        // This could show a temporary toast showing how many episodes were added
        // For now, we'll just use the haptic feedback
        // You could implement a toast notification system here
    }
}

#Preview {
    let samplePodcast = Podcast(
        id: UUID(),
        title: "Sample Podcast",
        author: "Author",
        description: "This is a sample podcast description.",
        feedURL: URL(string: "https://example.com/feed.xml")!,
        artworkURL: nil
    )
    
    let sampleEpisodes = [
        Episode(
            id: UUID(),
            title: "Episode 1: Introduction to Swift",
            artworkURL: nil,
            audioURL: nil,
            description: "In this episode we discuss the basics of Swift programming language and how to get started with iOS development.",
            played: false,
            podcastID: samplePodcast.id,
            publishedDate: Date(),
            localFileURL: nil,
            playbackPosition: 0
        ),
        Episode(
            id: UUID(),
            title: "Episode 2: Advanced Swift Concepts",
            artworkURL: nil,
            audioURL: nil,
            description: "Deep dive into advanced Swift concepts including generics, protocols, and memory management.",
            played: true,
            podcastID: samplePodcast.id,
            publishedDate: Date().addingTimeInterval(-86400),
            localFileURL: nil,
            playbackPosition: 1245
        ),
        Episode(
            id: UUID(),
            title: "Episode 3: SwiftUI Fundamentals",
            artworkURL: nil,
            audioURL: nil,
            description: "Learn the fundamentals of SwiftUI and how to create beautiful user interfaces.",
            played: false,
            podcastID: samplePodcast.id,
            publishedDate: Date().addingTimeInterval(-172800),
            localFileURL: nil,
            playbackPosition: 567
        )
    ]
    
    NavigationView {
        EpisodeListView(
            podcast: samplePodcast,
            episodes: sampleEpisodes,
            isLoading: false,
            onEpisodeTap: { _ in }
        )
    }
} 