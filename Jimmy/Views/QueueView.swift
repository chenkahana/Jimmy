import SwiftUI

struct QueueView: View {
    @ObservedObject private var viewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    private let podcastService = PodcastService.shared
    @State private var editMode: EditMode = .inactive
    @State private var currentlyOpenEpisodeID: UUID? = nil // Track which episode has swipe actions open
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.queue.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("Your queue is empty")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Add episodes from your podcasts to build your listening queue")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.queue, id: \.id) { episode in
                            let index = viewModel.queue.firstIndex(where: { $0.id == episode.id }) ?? 0
                            
                            QueueEpisodeCardView(
                                episode: episode,
                                podcast: getPodcast(for: episode),
                                isCurrentlyPlaying: currentPlayingEpisode?.id == episode.id,
                                isEditMode: editMode == .active,
                                isSwipeOpen: currentlyOpenEpisodeID == episode.id,
                                onTap: {
                                    if editMode == .inactive {
                                        // Close any open swipe actions first
                                        currentlyOpenEpisodeID = nil
                                        viewModel.playEpisodeFromQueue(at: index)
                                    }
                                },
                                onRemove: {
                                    currentlyOpenEpisodeID = nil
                                    viewModel.removeFromQueue(at: IndexSet(integer: index))
                                },
                                onMoveToEnd: {
                                    currentlyOpenEpisodeID = nil
                                    viewModel.moveToEndOfQueue(at: index)
                                },
                                onSwipeOpen: {
                                    currentlyOpenEpisodeID = episode.id
                                },
                                onSwipeClose: {
                                    if currentlyOpenEpisodeID == episode.id {
                                        currentlyOpenEpisodeID = nil
                                    }
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
                viewModel.syncCurrentEpisodeWithQueue()
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return podcastService.loadPodcasts().first { $0.id == episode.podcastID }
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