import SwiftUI

struct EpisodeListView: View {
    let podcast: Podcast
    let episodes: [Episode]
    let isLoading: Bool
    let onEpisodeTap: (Episode) -> Void

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading episodes...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if episodes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No Episodes Found")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("This podcast doesn't have any episodes yet")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(episodes) { episode in
                            EpisodeRowView(
                                episode: episode,
                                podcast: podcast,
                                onTap: {
                                    onEpisodeTap(episode)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(podcast.title)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct EpisodeRowView: View {
    let episode: Episode
    let podcast: Podcast
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Episode Picture (or podcast fallback)
                AsyncImage(url: episode.artworkURL ?? podcast.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "play.circle")
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Episode Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let description = episode.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Publication date
                    if let date = episode.publishedDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Play indicator
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .frame(width: 30, height: 50)
            }
            .padding(.vertical, 4)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let samplePodcast = Podcast(
        id: UUID(),
        title: "Sample Podcast",
        author: "Author",
        feedURL: URL(string: "https://example.com/feed.xml")!,
        artworkURL: nil
    )
    
    let sampleEpisodes = [
        Episode(
            id: UUID(),
            title: "Episode 1: Introduction to Swift",
            artworkURL: nil,
            audioURL: nil,
            description: "In this episode we discuss the basics of Swift programming language and how to get started with iOS development.",
            played: false,
            podcastID: samplePodcast.id,
            publishedDate: Date(),
            localFileURL: nil,
            playbackPosition: 0
        ),
        Episode(
            id: UUID(),
            title: "Episode 2: Advanced Swift Concepts",
            artworkURL: nil,
            audioURL: nil,
            description: "Deep dive into advanced Swift concepts including generics, protocols, and memory management.",
            played: false,
            podcastID: samplePodcast.id,
            publishedDate: Date().addingTimeInterval(-86400),
            localFileURL: nil,
            playbackPosition: 0
        )
    ]
    
    NavigationView {
        EpisodeListView(
            podcast: samplePodcast,
            episodes: sampleEpisodes,
            isLoading: false,
            onEpisodeTap: { _ in }
        )
    }
} 