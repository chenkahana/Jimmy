import SwiftUI

/// Reusable podcast grid component following the Background Data Synchronization Plan
/// Provides consistent podcast display across Library and Discover views
struct PodcastGridComponent: View {
    let podcasts: [Podcast]
    let isLoading: Bool
    let onPodcastTap: (Podcast) -> Void
    let onPodcastLongPress: ((Podcast) -> Void)?
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    init(
        podcasts: [Podcast],
        isLoading: Bool = false,
        onPodcastTap: @escaping (Podcast) -> Void,
        onPodcastLongPress: ((Podcast) -> Void)? = nil
    ) {
        self.podcasts = podcasts
        self.isLoading = isLoading
        self.onPodcastTap = onPodcastTap
        self.onPodcastLongPress = onPodcastLongPress
    }
    
    var body: some View {
        Group {
            if isLoading && podcasts.isEmpty {
                loadingView
            } else if podcasts.isEmpty {
                emptyStateView
            } else {
                podcastGrid
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading Podcasts...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Podcasts")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("Your subscribed podcasts will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Podcast Grid
    
    private var podcastGrid: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(podcasts, id: \.id) { podcast in
                PodcastCardComponent(
                    podcast: podcast,
                    onTap: { onPodcastTap(podcast) },
                    onLongPress: onPodcastLongPress != nil ? { onPodcastLongPress?(podcast) } : nil
                )
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Podcast Card Component

struct PodcastCardComponent: View {
    let podcast: Podcast
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    
    @State private var showingPodcastDetail = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Podcast Artwork
            podcastArtwork
            
            // Podcast Info
            podcastInfo
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress?()
        }
        .sheet(isPresented: $showingPodcastDetail) {
            PodcastDetailView(podcast: podcast)
        }
    }
    
    // MARK: - Podcast Artwork
    
    private var podcastArtwork: some View {
        AsyncImage(url: podcast.artworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                )
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Podcast Info
    
    private var podcastInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Podcast Title
            Text(podcast.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)
            
            // Author
            if !podcast.author.isEmpty {
                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Metadata
            podcastMetadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var podcastMetadata: some View {
        HStack(spacing: 8) {
            // Last Episode Date
            if let lastEpisodeDate = podcast.lastEpisodeDate {
                Text(RelativeDateTimeFormatter().localizedString(for: lastEpisodeDate, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Large Podcast Card Component

struct LargePodcastCardComponent: View {
    let podcast: Podcast
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    
    @State private var showingPodcastDetail = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Podcast Artwork
            AsyncImage(url: podcast.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Podcast Info
            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if !podcast.description.isEmpty {
                    Text(podcast.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    if let lastEpisodeDate = podcast.lastEpisodeDate {
                        Text(RelativeDateTimeFormatter().localizedString(for: lastEpisodeDate, relativeTo: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress?()
        }
        .sheet(isPresented: $showingPodcastDetail) {
            PodcastDetailView(podcast: podcast)
        }
    }
}

// MARK: - Preview

struct PodcastGridComponent_Previews: PreviewProvider {
    static var previews: some View {
        PodcastGridComponent(
            podcasts: [],
            onPodcastTap: { _ in }
        )
    }
} 