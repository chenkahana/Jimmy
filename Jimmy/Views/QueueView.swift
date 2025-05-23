import SwiftUI

struct QueueView: View {
    @ObservedObject private var viewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var selectedEpisode: Episode?
    private let podcastService = PodcastService.shared
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }
    
    var body: some View {
        NavigationView {
            // Episode Queue List
            List {
                ForEach(viewModel.queue) { episode in
                    QueueRowView(
                        episode: episode,
                        podcast: getPodcast(for: episode),
                        isCurrentlyPlaying: currentPlayingEpisode?.id == episode.id,
                        onTap: {
                            // Load and play the episode
                            audioPlayer.loadEpisode(episode)
                            audioPlayer.play()
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .onDelete(perform: viewModel.removeFromQueue)
                .onMove(perform: viewModel.moveQueue)
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active)) // Always allow dragging
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedEpisode) { episode in
                let playbackURL: URL? = {
                    if podcastService.isEpisodeDownloaded(episode) {
                        let fileManager = FileManager.default
                        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        if let audioURL = episode.audioURL {
                            let localURL = docs.appendingPathComponent(audioURL.lastPathComponent)
                            return localURL
                        } else {
                            return nil
                        }
                    } else {
                        return episode.audioURL
                    }
                }()
                
                if let url = playbackURL {
                    AudioPlayerView(url: url, startPosition: episode.playbackPosition) { position in
                        // Update episode progress
                        if let idx = viewModel.queue.firstIndex(where: { $0.id == episode.id }) {
                            viewModel.queue[idx].playbackPosition = position
                            viewModel.saveQueue()
                        }
                    }
                }
            }
        }
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return podcastService.loadPodcasts().first { $0.id == episode.podcastID }
    }
}

// MARK: - Supporting Views

struct QueueRowView: View {
    let episode: Episode
    let podcast: Podcast?
    let isCurrentlyPlaying: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Episode Picture
                AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "play.circle")
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    // Playing indicator
                    isCurrentlyPlaying ? 
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange, lineWidth: 2)
                    : nil
                )
                
                // Episode Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.headline)
                        .foregroundColor(isCurrentlyPlaying ? .orange : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let podcast = podcast {
                        Text(podcast.title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Currently playing indicator or drag handle
                if isCurrentlyPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                        .frame(width: 30, height: 50)
                } else {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .frame(width: 30, height: 50)
                }
            }
            .padding(.vertical, 4)
            .background(isCurrentlyPlaying ? Color.orange.opacity(0.1) : Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QueueView()
} 