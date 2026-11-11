import SwiftUI

/// A compact sticky header that appears when the main header collapses
/// Contains small artwork thumbnail, title, author, and navigation controls
public struct StickyCompactHeader: View {
    // MARK: - Input
    public let podcast: Podcast
    public let onDismiss: () -> Void
    public let onShowAbout: () -> Void
    public let filterOption: PodcastDetailViewModel.EpisodeFilter
    public let sortOrder: PodcastDetailViewModel.EpisodeSortOrder
    public let onFilterChange: (PodcastDetailViewModel.EpisodeFilter) -> Void
    public let onSortChange: (PodcastDetailViewModel.EpisodeSortOrder) -> Void
    public let isSubscribed: Bool
    public let isProcessingSubscription: Bool
    public let onSubscribe: () -> Void
    public let onUnsubscribe: () -> Void
    
    private let headerHeight: CGFloat = 80
    
    public init(
        podcast: Podcast,
        onDismiss: @escaping () -> Void,
        onShowAbout: @escaping () -> Void,
        filterOption: PodcastDetailViewModel.EpisodeFilter,
        sortOrder: PodcastDetailViewModel.EpisodeSortOrder,
        onFilterChange: @escaping (PodcastDetailViewModel.EpisodeFilter) -> Void,
        onSortChange: @escaping (PodcastDetailViewModel.EpisodeSortOrder) -> Void,
        isSubscribed: Bool = false,
        isProcessingSubscription: Bool = false,
        onSubscribe: @escaping () -> Void = {},
        onUnsubscribe: @escaping () -> Void = {}
    ) {
        self.podcast = podcast
        self.onDismiss = onDismiss
        self.onShowAbout = onShowAbout
        self.filterOption = filterOption
        self.sortOrder = sortOrder
        self.onFilterChange = onFilterChange
        self.onSortChange = onSortChange
        self.isSubscribed = isSubscribed
        self.isProcessingSubscription = isProcessingSubscription
        self.onSubscribe = onSubscribe
        self.onUnsubscribe = onUnsubscribe
    }
    
    // MARK: - Body
    public var body: some View {
        ZStack {
            // Background with glass effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: headerHeight)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            
            // Content
            VStack(spacing: 8) {
                // Navigation controls
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Menu {
                        // Filter options
                        Menu("Filter Episodes") {
                            Button(action: { onFilterChange(.all) }) {
                                Label("All Episodes", systemImage: filterOption == .all ? "checkmark" : "")
                            }
                            Button(action: { onFilterChange(.unplayed) }) {
                                Label("Unplayed", systemImage: filterOption == .unplayed ? "checkmark" : "")
                            }
                            Button(action: { onFilterChange(.played) }) {
                                Label("Played", systemImage: filterOption == .played ? "checkmark" : "")
                            }
                        }
                        
                        // Sort options
                        Menu("Sort Episodes") {
                            Button(action: { onSortChange(.newestFirst) }) {
                                Label("Newest First", systemImage: sortOrder == .newestFirst ? "checkmark" : "")
                            }
                            Button(action: { onSortChange(.oldestFirst) }) {
                                Label("Oldest First", systemImage: sortOrder == .oldestFirst ? "checkmark" : "")
                            }
                        }
                        
                        // Subscribe/Unsubscribe option
                        if isSubscribed {
                            Button(action: onUnsubscribe) {
                                Label("Unsubscribe", systemImage: "minus.circle")
                            }
                            .disabled(isProcessingSubscription)
                        } else {
                            Button(action: onSubscribe) {
                                Label(isProcessingSubscription ? "Subscribing..." : "Subscribe", systemImage: "plus.circle")
                            }
                            .disabled(isProcessingSubscription)
                        }
                        
                        // "About" button
                        if !podcast.description.isEmpty {
                            Button(action: onShowAbout) {
                                Label("About", systemImage: "info.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 20)
                
                // Compact podcast info
                HStack(spacing: 12) {
                    BulletproofAsyncImage(url: podcast.artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "mic.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            )
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(podcast.cleanTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        Text(podcast.author)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}

// MARK: - Preview
#if DEBUG
struct StickyCompactHeader_Previews: PreviewProvider {
    static var previews: some View {
        StickyCompactHeader(
            podcast: Podcast(
                id: UUID(),
                title: "Sample Podcast",
                author: "Sample Author",
                description: "",
                feedURL: URL(string: "https://example.com/feed.rss")!,
                artworkURL: URL(string: "https://example.com/artwork.jpg")!
            ),
            onDismiss: {},
            onShowAbout: {},
            filterOption: .all,
            sortOrder: .newestFirst,
            onFilterChange: { _ in },
            onSortChange: { _ in }
        )
    }
}
#endif 