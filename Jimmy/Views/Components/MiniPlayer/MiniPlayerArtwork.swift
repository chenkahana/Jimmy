import SwiftUI

/// Square artwork with caching & rounded corners (8pt)
struct MiniPlayerArtwork: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @Environment(\.nowPlayingNamespace) private var namespace
    
    var body: some View {
        Group {
            if let currentEpisode = audioPlayer.currentEpisode {
                BulletproofAsyncImage(url: artworkURL(for: currentEpisode)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    artworkPlaceholder
                }
                .transition(.opacity.combined(with: .scale))
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(
            Group {
                if audioPlayer.isPlaying {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.3))
                        AnimatedWaveformBars(barCount: 3, color: .white, size: 16)
                    }
                }
            }
        )
        .accessibilityLabel({
            if let episode = audioPlayer.currentEpisode {
                return "Artwork for \(episode.title)"
            }
            return "No episode playing"
        }())
        .accessibilityAddTraits(.isImage)
        .if(namespace != nil) { view in
            view.matchedGeometryEffect(id: NowPlayingGeometryID.artwork, in: namespace!)
        }
    }
    
    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.6),
                        Color.accentColor.opacity(0.4),
                        Color.accentColor.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "waveform.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                    .shadow(color: .accentColor.opacity(0.5), radius: 2, x: 0, y: 1)
            )
    }
    
    private func artworkURL(for episode: Episode) -> URL? {
        episode.artworkURL ?? getPodcast(for: episode)?.artworkURL
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        // TODO: This should be optimized to use a cached podcast reference
        // For now, using the same logic as the original mini-player
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
} 