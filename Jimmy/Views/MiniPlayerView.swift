import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    let onTap: () -> Void
    
    var body: some View {
        if let currentEpisode = audioPlayer.currentEpisode {
            VStack(spacing: 0) {
                // Thin progress bar
                ProgressView(value: audioPlayer.playbackPosition, total: audioPlayer.duration)
                    .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                    .frame(height: 2)
                
                // Mini player content
                HStack(spacing: 12) {
                    // Episode artwork
                    AsyncImage(url: currentEpisode.artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            )
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    // Episode info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentEpisode.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if let podcast = getPodcast(for: currentEpisode) {
                            Text(podcast.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Play/pause button
                    Button(action: {
                        audioPlayer.togglePlayPause()
                    }) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    // Forward button
                    Button(action: {
                        audioPlayer.seekForward()
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .onTapGesture {
                    onTap()
                }
            }
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: -2)
        }
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
}

#Preview {
    VStack {
        Spacer()
        Text("Main Content")
            .font(.title)
        Spacer()
        MiniPlayerView(onTap: {})
    }
} 