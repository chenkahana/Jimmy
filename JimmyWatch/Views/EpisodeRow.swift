import JimmyKit
import SwiftUI

/// One row in `QueueView`/`RecentView`.
struct EpisodeRow: View {
    let episode: WatchEpisodeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(episode.title)
                .font(.body)
                .lineLimit(2)
            if let showTitle = episode.showTitle {
                Text(showTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
