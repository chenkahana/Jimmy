import SwiftUI

struct DiscoverGenreSectionView: View {
    let genre: String
    let results: [PodcastSearchResult]
    let isSubscribed: (PodcastSearchResult) -> Bool
    let onSubscribe: (PodcastSearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(genre)
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(results) { result in
                        NavigationLink(destination: PodcastDetailView(podcast: result.toPodcast())) {
                            LargeRecommendedPodcastItem(
                                result: result,
                                isSubscribed: isSubscribed(result),
                                onSubscribe: { onSubscribe(result) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    DiscoverGenreSectionView(
        genre: "News",
        results: [
            PodcastSearchResult(
                id: 1,
                title: "Sample Podcast",
                author: "Author",
                feedURL: URL(string: "https://example.com/feed")!,
                artworkURL: nil,
                description: "",
                genre: "News",
                trackCount: 0
            )
        ],
        isSubscribed: { _ in false },
        onSubscribe: { _ in }
    )
}
