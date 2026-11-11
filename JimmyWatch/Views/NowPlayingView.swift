import SwiftUI

/// Title, show, progress and transport controls for whatever's playing on the phone. Skip
/// forward/back use the watch's own numbered media-skip glyphs rather than custom icons.
struct NowPlayingView: View {
    @Environment(WatchSessionClient.self) private var client

    var body: some View {
        if let nowPlaying = client.state?.nowPlaying {
            VStack(spacing: 8) {
                if let showTitle = nowPlaying.showTitle {
                    Text(showTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(nowPlaying.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                ProgressView(value: nowPlaying.position, total: max(nowPlaying.duration ?? 0, nowPlaying.position, 1))

                HStack(spacing: 24) {
                    Button {
                        client.send(.skipBackward)
                    } label: {
                        Image(systemName: "gobackward.15")
                    }

                    Button {
                        client.send(nowPlaying.isPlaying ? .pause : .play)
                    } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }

                    Button {
                        client.send(.skipForward)
                    } label: {
                        Image(systemName: "goforward.15")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()
        } else {
            ContentUnavailableView("Nothing Playing", systemImage: "play.slash")
        }
    }
}
