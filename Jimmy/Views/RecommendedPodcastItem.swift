import SwiftUI

struct RecommendedPodcastItem: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    let styleIndex: Int

    private var colorPair: (Color, Color) {
        let sets = ColorPalette.gradientPairs
        return sets[styleIndex % sets.count]
    }

    var body: some View {
        VStack(spacing: 8) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 120,
                cornerRadius: 12
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colorPair.0.opacity(0.6), lineWidth: 2)
            )
            .shadow(color: colorPair.0.opacity(0.3), radius: 4, x: 0, y: 2)

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
                        LinearGradient(
                            colors: [colorPair.0, colorPair.1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(isSubscribed ? 0.4 : 1.0)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isSubscribed)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [colorPair.0.opacity(0.15), colorPair.1.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

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
        onSubscribe: {},
        styleIndex: 0
    )
}
