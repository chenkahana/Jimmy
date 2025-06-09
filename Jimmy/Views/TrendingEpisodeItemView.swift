import SwiftUI

struct TrendingEpisodeItemView: View {
    let episode: TrendingEpisode
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PodcastArtworkView(
                artworkURL: episode.artworkURL,
                size: 160,
                cornerRadius: 12
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)

            Text(episode.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundColor(.primary)
                .frame(width: 160, alignment: .leading)

            Text(episode.podcastName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            Button(action: onSubscribe) {
                Text("Subscribe")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
        }
        .padding(8)
    }
}

#Preview {
    TrendingEpisodeItemView(
        episode: TrendingEpisode(
            id: 1,
            title: "Sample Episode",
            podcastName: "Podcast Name",
            feedURL: URL(string: "https://example.com/feed")!,
            artworkURL: nil
        ),
        onSubscribe: {}
    )
}
