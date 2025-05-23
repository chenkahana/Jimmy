import SwiftUI
import AVKit

struct AudioPlayerView: View {
    let url: URL
    let startPosition: TimeInterval
    let onProgressUpdate: (TimeInterval) -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackPosition: Double = 0
    @State private var totalDuration: Double = 0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("Now Playing") // Placeholder title
                .font(.title2)
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
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.seek(to: CMTime(seconds: startPosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { time in
            let currentPosition = CMTimeGetSeconds(time)
            playbackPosition = currentPosition
            onProgressUpdate(currentPosition)
        }
        
        if let duration = player?.currentItem?.asset.duration {
            totalDuration = CMTimeGetSeconds(duration)
        }
        
        // Autoplay if startPosition is 0 or if desired
        if startPosition == 0 {
             player?.play()
             isPlaying = true
        } else {
            // If resuming, you might want to decide if it should autoplay or wait for user action
            // For now, let's not autoplay if there's a startPosition > 0
             isPlaying = false 
        }
    }

    private func stopPlayer() {
        player?.pause()
        // Update final playback position before dismissing if needed
        if let currentTime = player?.currentTime() {
            onProgressUpdate(CMTimeGetSeconds(currentTime))
        }
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
        let newTime = min(totalDuration, currentTime + 15.0)
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
    }

    private func seekBackward() {
        guard let player = player else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = max(0, currentTime - 15.0)
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
    }
    
    private func sliderEditingChanged(editingStarted: Bool) {
        guard let player = player else { return }
        if editingStarted {
            if isPlaying { // Pause only if it was playing
                player.pause()
            }
        } else {
            player.seek(to: CMTime(seconds: playbackPosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))) {
                [weak player, self] _ in // Capture weakly to avoid retain cycles
                if self.isPlaying == true { // Resume playback only if it was playing before scrub
                    player?.play()
                }
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let time = time.isNaN ? 0 : time // Handle NaN case if duration is not yet loaded
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }
}

struct AudioPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        AudioPlayerView(
            url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!,
            startPosition: 10,
            onProgressUpdate: { time in
                print("Current time: \(time)")
            }
        )
    }
} 