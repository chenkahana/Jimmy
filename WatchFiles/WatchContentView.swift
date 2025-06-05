import SwiftUI

struct WatchContentView: View {
    @ObservedObject private var player = WatchPlayerManager.shared

    var body: some View {
        VStack(spacing: 8) {
            if let episode = player.currentEpisode {
                Text(episode.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("No Episode")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Button(action: { player.seekBackward() }) {
                    Image(systemName: "gobackward.15")
                }
                Button(action: { player.playPause() }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: { player.seekForward() }) {
                    Image(systemName: "goforward.15")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    WatchContentView()
}
