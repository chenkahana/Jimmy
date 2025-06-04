import SwiftUI

struct RecommendedPodcastItem: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 120,
                cornerRadius: 12
            )
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

            Text(result.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)

            Button(action: onSubscribe) {
                Text(isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isSubscribed ? Color.green : Color.blue)
                            .opacity(0.2)
                    )
                    .foregroundColor(isSubscribed ? .green : .blue)
                    .cornerRadius(8)
            }
            .disabled(isSubscribed)
        }
    }
}

#if canImport(SwiftUI) && DEBUG
#Preview {
    RecommendedPodcastItem(
        result: PodcastSearchResult(
            id: 1,
            title: "Sample Podcast",
            author: "Author",
            feedURL: URL(string: "https://example.com/feed")!,
            artworkURL: nil,
            description: "",
            genre: "",
            trackCount: 0
        ),
        isSubscribed: false,
        onSubscribe: {}
    )
}
#endif
