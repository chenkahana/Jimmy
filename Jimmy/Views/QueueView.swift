import SwiftUI

struct QueueView: View {
    @ObservedObject private var viewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    private let podcastService = PodcastService.shared
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }
    
    var body: some View {
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
            HStack(spacing: 16) {
                // Episode Picture - Enhanced design
                AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: isCurrentlyPlaying ? 
                                    [Color.orange.opacity(0.3), Color.orange.opacity(0.1)] :
                                    [Color(.systemGray5), Color(.systemGray4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: isCurrentlyPlaying ? "speaker.wave.2.fill" : "waveform.circle")
                                .foregroundColor(isCurrentlyPlaying ? .orange : .gray)
                                .font(.title2)
                        )
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    // Enhanced playing indicator
                    isCurrentlyPlaying ? 
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange, Color.orange.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), 
                            lineWidth: 3
                        )
                        .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                    : nil
                )
                .shadow(color: .black.opacity(0.1), radius: isCurrentlyPlaying ? 6 : 2, x: 0, y: 2)
                
                // Episode Name Section - Better typography
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title)
                        .font(.system(.body, design: .rounded, weight: isCurrentlyPlaying ? .semibold : .medium))
                        .foregroundColor(isCurrentlyPlaying ? .orange : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let podcast = podcast {
                        Text(podcast.title)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Current episode progress indicator
                    if isCurrentlyPlaying {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Now Playing")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
                
                // Right side controls
                VStack(spacing: 8) {
                    // Play/pause or drag handle
                    if isCurrentlyPlaying {
                        // Play/pause button for current episode
                        Button(action: {
                            AudioPlayerService.shared.togglePlayPause()
                        }) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: AudioPlayerService.shared.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(.callout, weight: .semibold))
                                        .foregroundColor(.white)
                                        .offset(x: AudioPlayerService.shared.isPlaying ? 0 : 1)
                                )
                                .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    } else {
                        // Drag handle for non-playing episodes
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                // Enhanced background for current episode
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isCurrentlyPlaying ? 
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.15),
                                Color.orange.opacity(0.08),
                                Color.orange.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color(.systemBackground)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        // Subtle border for current episode
                        isCurrentlyPlaying ?
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        : nil
                    )
            )
            .scaleEffect(isCurrentlyPlaying ? 1.02 : 1.0)
            .shadow(
                color: isCurrentlyPlaying ? .orange.opacity(0.2) : .black.opacity(0.05),
                radius: isCurrentlyPlaying ? 8 : 2,
                x: 0,
                y: isCurrentlyPlaying ? 4 : 1
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCurrentlyPlaying)
    }
}

#Preview {
    QueueView()
} 