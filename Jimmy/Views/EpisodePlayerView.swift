import SwiftUI
import AVKit

struct EpisodePlayerView: View {
    let episode: Episode
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackPosition: Double = 0
    @State private var totalDuration: Double = 0
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
            AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) {
                $0.resizable()
            } placeholder: {
                ProgressView()
            }
            .aspectRatio(contentMode: .fit)
            .frame(height: 200)
            .cornerRadius(8)
            .padding()

            if player != nil {
                VStack {
                    Slider(value: $playbackPosition, in: 0...totalDuration, onEditingChanged: sliderEditingChanged)
                        .padding()
                    
                    HStack {
                        Text(formatTime(playbackPosition))
                        Spacer()
                        Text(formatTime(totalDuration))
                    }
                    .padding([.leading, .trailing, .bottom])
                    
                    HStack(spacing: 40) {
                        Button(action: seekBackward) {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                        }
                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                        }
                        Button(action: seekForward) {
                            Image(systemName: "goforward.15")
                                .font(.title)
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView("Loading player...")
                    .padding()
            }

            Spacer()
            
            Button("Done") {
                           dismiss()
                       }
                       .padding()
        }
        .onAppear(perform: setupPlayer)
        .onDisappear(perform: stopPlayer)
    }

    private func setupPlayer() {
        guard let url = episode.audioURL else { return }
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { time in
            playbackPosition = CMTimeGetSeconds(time)
        }
        
        if let duration = player?.currentItem?.asset.duration {
            totalDuration = CMTimeGetSeconds(duration)
        }
        
        // Start playing automatically if desired
        // player?.play()
        // isPlaying = true
    }

    private func stopPlayer() {
        player?.pause()
        player = nil
    }

    private func togglePlayPause() {
        guard let player = player else { return }
        isPlaying.toggle()
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    private func seekForward() {
        guard let player = player else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = currentTime + 15.0
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
    }

    private func seekBackward() {
        guard let player = player else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = currentTime - 15.0
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
    }
    
    private func sliderEditingChanged(editingStarted: Bool) {
        guard let player = player else { return }
        if editingStarted {
            player.pause()
        } else {
            player.seek(to: CMTime(seconds: playbackPosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))) {
                _ in
                if isPlaying {
                    player.play()
                }
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