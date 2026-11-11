import SwiftUI

/// Title, podcast name, time labels
struct MiniPlayerInfoStack: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @Environment(\.nowPlayingNamespace) private var namespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let currentEpisode = audioPlayer.currentEpisode {
                // Episode title only (single line)
                Text(currentEpisode.title)
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .accessibilityLabel("Episode: \(currentEpisode.title)")
                    .if(namespace != nil) { view in
                        view.matchedGeometryEffect(id: NowPlayingGeometryID.title, in: namespace!)
                    }
            } else {
                // Placeholder content
                Text("No Episode Playing")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
} 