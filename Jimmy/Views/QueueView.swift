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
            Group {
                if viewModel.queue.isEmpty {
                    UnifiedEmptyStateView(
                        icon: "list.bullet",
                        title: "Your queue is empty",
                        subtitle: "Add episodes from your podcasts to build your listening queue"
                    )
                } else {
                    List {
                        ForEach(viewModel.queue, id: \.id) { episode in
                            let index = viewModel.queue.firstIndex(where: { $0.id == episode.id }) ?? 0
                            
                            QueueEpisodeCardView(
                                episode: episode,
                                podcast: getPodcast(for: episode),
                                isCurrentlyPlaying: currentPlayingEpisode?.id == episode.id,
                                isEditMode: editMode == .active,
                                isLoading: viewModel.loadingEpisodeID == episode.id || audioPlayer.isLoading && currentPlayingEpisode?.id == episode.id,
                                onTap: {
                                    if editMode == .inactive {
                                        viewModel.playEpisodeFromQueue(at: index)
                                    }
                                },
                                onRemove: {
                                    viewModel.removeFromQueue(at: IndexSet(integer: index))
                                },
                                onMoveToEnd: {
                                    viewModel.moveToEndOfQueue(at: index)
                                }
                            )
                            .overlay(
                                // Show queue position indicator for non-playing episodes
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
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveEpisodes)
                        .onDelete(perform: editMode == .active ? deleteEpisodes : nil)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, $editMode)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.queue.isEmpty {
                        EditButton()
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
            .onAppear {
                // WORLD-CLASS NAVIGATION: Instant display with immediate podcast loading for artwork
                
                // IMMEDIATE: Load podcasts immediately for artwork display
                Task {
                    let podcasts = await PodcastService.shared.loadPodcastsAsync()
                    // CRITICAL FIX: Use asyncAfter to prevent \"Publishing changes from within view updates\"
                    DispatchQueue.main.async {
                        self.allPodcasts = podcasts
                    }
                }
                        
                // DEFERRED: Heavy operations moved to background with delays
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    DispatchQueue.global(qos: .background).async {
                        // Sync and preload (low priority)
                        // CRITICAL FIX: Use asyncAfter to prevent \"Publishing changes from within view updates\"
                        DispatchQueue.main.async {
                            viewModel.syncCurrentEpisodeWithQueue()
                            
                            if !viewModel.queue.isEmpty {
                                AudioPlayerService.shared.preloadEpisodes(Array(viewModel.queue.prefix(3)))
                            }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        // Use preloaded podcasts for fast lookup
        return allPodcasts.first { $0.id == episode.podcastID }
    }
    
    private func moveEpisodes(from source: IndexSet, to destination: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.moveQueue(from: source, to: destination)
        }
    }
    
    private func deleteEpisodes(at offsets: IndexSet) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.removeFromQueue(at: offsets)
        }
    }
}

#Preview {
    QueueView()
} 