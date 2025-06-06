import SwiftUI
import AVKit

struct AudioPlayerView: View {
    let url: URL
    let startPosition: TimeInterval
    let onProgressUpdate: (TimeInterval) -> Void

    @ObservedObject private var audioService = AudioPlayerService.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("Now Playing") // Placeholder title
                .font(.title2)
                .padding()

            if audioService.currentEpisode != nil {
                VStack {
                    Slider(value: Binding(
                        get: { 
                            let position = audioService.playbackPosition
                            onProgressUpdate(position) // Update progress as user views
                            return position
                        },
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
            // Create a temporary episode for the URL and load it
            let tempEpisode = Episode(
                id: UUID(),
                title: "Audio Player",
                artworkURL: nil,
                audioURL: url,
                description: "",
                played: false,
                podcastID: UUID(),
                publishedDate: Date(),
                localFileURL: nil,
                playbackPosition: startPosition
            )
            audioService.loadEpisode(tempEpisode)
        }
        .onDisappear {
            // Report final progress when leaving
            onProgressUpdate(audioService.playbackPosition)
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