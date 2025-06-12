import SwiftUI

struct QueueView: View {
    @ObservedObject private var viewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var editMode: EditMode = .inactive
    @State private var allPodcasts: [Podcast] = [] // Store loaded podcasts for quick lookup
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }
    
    var body: some View {
        NavigationView {
            queueContent
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.queuedEpisodes.isEmpty {
                        EditButton()
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - View Components
    
    private var queueContent: some View {
        Group {
            if viewModel.queuedEpisodes.isEmpty {
                emptyStateView
            } else {
                queueList
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Your queue is empty")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add episodes from your podcasts to build your listening queue")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var queueList: some View {
        List {
            ForEach(Array(viewModel.queuedEpisodes.enumerated()), id: \.element.id) { index, episode in
                queueEpisodeRow(episode: episode, index: index)
            }
            .onMove(perform: moveEpisodes)
            .onDelete(perform: editMode == .active ? deleteEpisodes : nil)
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }
    
    private func queueEpisodeRow(episode: Episode, index: Int) -> some View {
        QueueEpisodeCardView(
            episode: episode,
            podcast: getPodcast(for: episode),
            isCurrentlyPlaying: currentPlayingEpisode?.id == episode.id,
            isEditMode: editMode == .active,
            isLoading: audioPlayer.isLoading && currentPlayingEpisode?.id == episode.id,
            onTap: {
                if editMode == .inactive {
                    Task {
                        await viewModel.playEpisode(at: index)
                    }
                }
            },
            onRemove: {
                Task {
                    try? await viewModel.removeEpisode(at: index)
                }
            },
            onMoveToEnd: {
                // Move to end by removing and adding to end
                let episode = viewModel.queuedEpisodes[index]
                Task {
                    try? await viewModel.removeEpisode(at: index)
                    try? await viewModel.addEpisode(episode)
                }
            }
        )
        .overlay(queuePositionIndicator(for: episode, at: index))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
    }
    
    private func queuePositionIndicator(for episode: Episode, at index: Int) -> some View {
        VStack {
            if currentPlayingEpisode?.id != episode.id && editMode == .inactive {
                HStack {
                    VStack {
                        Text("\(index + 1)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.gray.opacity(0.7))
                            .clipShape(Circle())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 8)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        // Use preloaded podcasts for fast lookup
        return allPodcasts.first { $0.id == episode.podcastID }
    }
    
    private func moveEpisodes(from source: IndexSet, to destination: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.moveEpisode(from: source, to: destination)
        }
    }
    
    private func deleteEpisodes(at offsets: IndexSet) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            for index in offsets.sorted(by: >) {
                Task {
                    try? await viewModel.removeEpisode(at: index)
                }
            }
        }
    }
}

#Preview {
    QueueView()
} 