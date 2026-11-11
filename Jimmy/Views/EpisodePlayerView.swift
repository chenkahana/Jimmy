import SwiftUI
import AVKit

struct EpisodePlayerView: View {
    @ObservedObject private var audioService = AudioPlayerService.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            if let episode = audioService.currentEpisode {
                Text(episode.title)
                    .font(.title)
                    .padding()
                
                BulletproofAsyncImage(url: episode.artworkURL) { image in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)
                .cornerRadius(8)
                .padding()
                
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
                            Image(systemName: "gobackward.15").font(.title)
                        }
                        Button(action: { audioService.togglePlayPause() }) {
                            Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                        }
                        Button(action: { audioService.seekForward() }) {
                            Image(systemName: "goforward.15").font(.title)
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
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }
}

struct EpisodePlayerView_Previews: PreviewProvider {
    static var previews: some View {
        EpisodePlayerView()
    }
} 