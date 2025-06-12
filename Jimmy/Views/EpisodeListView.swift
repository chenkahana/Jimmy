import SwiftUI

struct EpisodeListView: View {
    let podcast: Podcast
    let onEpisodeTap: (Episode) -> Void
    
    @StateObject private var viewModel = EpisodeListViewModel()
    @StateObject private var queueViewModel = QueueViewModel.shared
    @StateObject private var audioPlayer = AudioPlayerService.shared
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.episodes.isEmpty {
                    emptyStateView
                } else {
                    episodeListView
                }
            }
            .navigationTitle(podcast.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    episodeMenuButton
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadEpisodes(for: podcast.id)
            }
        }
        .overlay(toastOverlay)
    }
    
    // MARK: - View Components
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading episodes...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
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
    }
    
    private var episodeListView: some View {
        List {
            ForEach(viewModel.episodes) { episode in
                EpisodeRowView(episode: episode, podcast: podcast)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEpisodeTap(episode)
                    }
                    .contextMenu {
                        episodeContextMenu(for: episode)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .animation(.proMotionEaseInOut(duration: 0.2), value: viewModel.episodes.count)
    }
    
    private var episodeMenuButton: some View {
        Menu {
            Button(action: markAllAsPlayed) {
                Label("Mark All as Played", systemImage: "checkmark.circle")
            }
            
            Button(action: markAllAsUnplayed) {
                Label("Mark All as Unplayed", systemImage: "circle")
            }
            
            Divider()
            
            Button(action: addAllToQueue) {
                Label("Add All to Queue", systemImage: "plus.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }
    
    @ViewBuilder
    private func episodeContextMenu(for episode: Episode) -> some View {
        Button(action: { handlePlayNext(episode) }) {
            Label("Play Next", systemImage: "play.circle")
        }
        
        Button(action: { 
            viewModel.markEpisodeAsPlayed(episode, played: !episode.played)
        }) {
            Label(episode.played ? "Mark as Unplayed" : "Mark as Played", 
                  systemImage: episode.played ? "circle" : "checkmark.circle")
        }
    }
    
    private var toastOverlay: some View {
        VStack {
            Spacer()
            
            if showingToast {
                HStack {
                    Image(systemName: toastIcon)
                        .foregroundColor(.white)
                    Text(toastMessage)
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 20)
        .animation(.proMotionEaseInOut(duration: 0.3), value: showingToast)
    }
    
    // MARK: - Actions
    
    private func handlePlayNext(_ episode: Episode) {
        Task {
            try? await queueViewModel.addEpisode(episode)
        }
        
        FeedbackManager.shared.playNext()
        showPlayNextFeedback(for: episode)
    }
    
    private func markAllAsPlayed() {
        viewModel.markAllEpisodesAsPlayed(for: podcast.id)
        FeedbackManager.shared.success()
    }
    
    private func markAllAsUnplayed() {
        viewModel.markAllEpisodesAsUnplayed(for: podcast.id)
        FeedbackManager.shared.success()
    }
    
    private func addAllToQueue() {
        let currentQueueIDs = Set(queueViewModel.queuedEpisodes.map { $0.id })
        let episodesToAdd = viewModel.episodes.filter { !currentQueueIDs.contains($0.id) }
        
        Task {
            for episode in episodesToAdd {
                try? await queueViewModel.addEpisode(episode)
            }
        }
        
        FeedbackManager.shared.success()
        showAddToQueueFeedback(count: episodesToAdd.count)
    }
    
    private func showPlayNextFeedback(for episode: Episode) {
        let message = "Added \"\(episode.title)\" to play next"
        showToast(message: message, systemImage: "play.circle.fill")
    }
    
    private func showAddToQueueFeedback(count: Int) {
        let message = count == 1 ? "Added 1 episode to queue" : "Added \(count) episodes to queue"
        showToast(message: message, systemImage: "plus.circle.fill")
    }
    
    // MARK: - Toast State
    
    @State private var toastMessage: String = ""
    @State private var toastIcon: String = ""
    @State private var showingToast: Bool = false
    
    private func showToast(message: String, systemImage: String) {
        toastMessage = message
        toastIcon = systemImage
        showingToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.proMotionEaseInOut(duration: 0.3)) {
                showingToast = false
            }
        }
    }
}

// MARK: - Preview
#Preview {
    let sampleEpisodes = [
        Episode(
            id: UUID(),
            title: "Sample Episode 1",
            artworkURL: nil,
            audioURL: nil,
            description: "This is a sample episode description.",
            played: false,
            podcastID: UUID(),
            publishedDate: Date(),
            localFileURL: nil,
            playbackPosition: 0,
            duration: 3600
        ),
        Episode(
            id: UUID(),
            title: "Sample Episode 2",
            artworkURL: nil,
            audioURL: nil,
            description: "Another sample episode description.",
            played: true,
            podcastID: UUID(),
            publishedDate: Date().addingTimeInterval(-86400),
            localFileURL: nil,
            playbackPosition: 0,
            duration: 2400
        )
    ]
    
    EpisodeListView(
        podcast: Podcast(
            id: UUID(),
            title: "Sample Podcast",
            author: "Sample Author",
            description: "A sample podcast description",
            feedURL: URL(string: "https://example.com/feed.xml")!,
            artworkURL: nil
        ),
        onEpisodeTap: { _ in }
    )
} 