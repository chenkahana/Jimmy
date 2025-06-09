import SwiftUI

struct TopChartRowView: View {
    let index: Int
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.title3.bold())
                .frame(width: 30, alignment: .center)
                .foregroundColor(.secondary)

            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 60,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onSubscribe) {
                Text(isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isSubscribed ? Color.green : Color.blue).opacity(0.2))
                    .foregroundColor(isSubscribed ? .green : .blue)
                    .cornerRadius(8)
            }
            .disabled(isSubscribed)
        }
        .padding(.horizontal)
    }
}

#Preview {
    TopChartRowView(
        index: 1,
        result: PodcastSearchResult(
            id: 1,
            title: "Sample Podcast",
            author: "Author",
            feedURL: URL(string: "https://example.com/feed")!,
            artworkURL: nil,
            description: nil,
            genre: "News",
            trackCount: 0
        ),
        isSubscribed: false,
        onSubscribe: {}
    )
}
