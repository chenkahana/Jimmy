import SwiftUI
import AVKit

struct EpisodePlayerView: View {
    let episode: Episode
    @ObservedObject private var audioService = AudioPlayerService.shared
    @Environment(\.dismiss) var dismiss
    
    // Get podcast for fallback artwork
    private var podcast: Podcast? {
        PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }

    var body: some View {
        VStack {
            Text(episode.title)
                .font(.title)
                .padding()
            
            // Use episode artwork first, then podcast artwork as fallback
            CachedAsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) {
                $0.resizable()
            } placeholder: {
                ProgressView()
            }
            .transition(.opacity.combined(with: .scale))
            .aspectRatio(contentMode: .fit)
            .frame(height: 200)
            .cornerRadius(8)
            .padding()

            if audioService.currentEpisode != nil {
                VStack {
                    Slider(value: Binding(
                        get: { audioService.playbackPosition },
                        set: { audioService.seek(to: $0) }
                    ), in: 0...audioService.duration)
                        .padding()
                    
                    HStack {
                        Text(formatTime(audioService.playbackPosition))
                        Spacer()
                        Text(formatTime(audioService.duration))
                    }
                    .padding([.leading, .trailing, .bottom])
                    
                    HStack(spacing: 40) {
                        Button(action: { audioService.seekBackward() }) {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                        }
                        Button(action: { audioService.togglePlayPause() }) {
                            Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                        }
                        Button(action: { audioService.seekForward() }) {
                            Image(systemName: "goforward.15")
                                .font(.title)
                        }
                    }
                    .padding()
                }
            } else if audioService.isLoading {
                ProgressView("Loading player...")
                    .padding()
            }

            Spacer()
            
            Button("Done") {
                           dismiss()
                       }
                       .padding()
        }
        .onAppear {
            // Load episode into the shared audio service if not already loaded
            if audioService.currentEpisode?.id != episode.id {
                audioService.loadEpisode(episode)
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }
}

struct EpisodePlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleEpisode = Episode(
            id: UUID(),
            title: "Sample Episode Title - A Very Long Title to Test Text Wrapping",
            artworkURL: URL(string: "https://picsum.photos/seed/picsum/200/200"), // Placeholder image
            audioURL: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"), // Sample audio
            description: "This is a sample episode description. It can be quite long and provide details about the episode content.",
            played: false,
            podcastID: UUID(),
            publishedDate: Date(),
            localFileURL: nil,
            playbackPosition: 30 // Start 30 seconds in
        )
        
        EpisodePlayerView(episode: sampleEpisode)
    }
} 