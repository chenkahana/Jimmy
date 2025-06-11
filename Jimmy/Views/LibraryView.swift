import SwiftUI

struct LibraryView: View {
    @ObservedObject private var libraryController = LibraryController.shared
    @ObservedObject private var episodeController = UnifiedEpisodeController.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @EnvironmentObject private var uiUpdateService: UIUpdateService
    
    @State private var selectedTab: LibraryTab = .shows
    @State private var isRefreshing: Bool = false
    
    enum LibraryTab: String, CaseIterable {
        case shows = "Shows"
        case episodes = "Episodes"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Enhanced Segmented Control
                enhancedSegmentedControl
                
                // Search Bar
                searchBar
                
                // Content
                if libraryController.isLoading || isRefreshing {
                    Spacer()
                    ProgressView("Loading...")
                        .scaleEffect(1.2)
                    Spacer()
                } else {
                    switch selectedTab {
                    case .shows:
                        showsContent
                    case .episodes:
                        episodesContent
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        libraryController.toggleEditMode()
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
        .refreshable {
            await performRefresh()
        }
        .onAppear {
            libraryController.loadData()
        }
    }
    
    // MARK: - Enhanced UI Components
    
    private var enhancedSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField(selectedTab == .shows ? "Search podcasts" : "Search episodes", text: $libraryController.searchText)
                    .font(.system(size: 16))
                
                if !libraryController.searchText.isEmpty {
                    Button("Clear") {
                        libraryController.clearSearch()
                    }
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .medium))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemBackground))
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var showsContent: some View {
        if libraryController.filteredPodcasts.isEmpty {
            emptyShowsState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Subscribed Shows")
                                .font(.title2.bold())
                                .foregroundColor(.primary)
                            
                            Text("Sorted by latest update")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Enhanced Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 20) {
                        ForEach(libraryController.filteredPodcasts.sorted { podcast1, podcast2 in
                            let date1 = libraryController.getLatestEpisodeDate(for: podcast1) ?? Date.distantPast
                            let date2 = libraryController.getLatestEpisodeDate(for: podcast2) ?? Date.distantPast
                            return date1 > date2
                        }, id: \.id) { podcast in
                            NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                                EnhancedPodcastCard(
                                    podcast: podcast,
                                    episodeCount: libraryController.getEpisodesCount(for: podcast),
                                    unplayedCount: libraryController.getUnplayedEpisodesCount(for: podcast),
                                    isEditMode: libraryController.isEditMode,
                                    onDelete: {
                                        libraryController.deletePodcast(podcast)
                                    }
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(libraryController.isEditMode)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100) // Space for mini player
                }
            }
        }
    }
    
    @ViewBuilder
    private var episodesContent: some View {
        if libraryController.filteredEpisodes.isEmpty {
            emptyEpisodesState
        } else {
            List {
                ForEach(libraryController.filteredEpisodes.sorted { episode1, episode2 in
                    let date1 = episode1.publishedDate ?? Date.distantPast
                    let date2 = episode2.publishedDate ?? Date.distantPast
                    return date1 > date2
                }, id: \.id) { episode in
                    NavigationLink(destination: EpisodeDetailView(
                        episode: episode,
                        podcast: libraryController.getPodcast(for: episode) ?? Podcast(title: "Unknown", author: "", description: "", feedURL: URL(string: "https://example.com")!, artworkURL: nil)
                    )) {
                        EnhancedEpisodeRow(
                            episode: episode,
                            podcast: libraryController.getPodcast(for: episode)
                        )
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
    }
    
    private var emptyShowsState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Podcasts Yet")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Text("Your subscribed podcasts will appear here.\nGo to Discover to find and subscribe to podcasts.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
    
    private var emptyEpisodesState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "list.bullet")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Episodes Yet")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Text("Episodes from your subscribed podcasts will appear here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
    
    // MARK: - Helper Methods
    
    private func performRefresh() async {
        await MainActor.run {
            isRefreshing = true
        }
        
        await libraryController.refreshAllData()
        
        await MainActor.run {
            isRefreshing = false
        }
    }
}

// MARK: - Enhanced Components

struct EnhancedPodcastCard: View {
    let podcast: Podcast
    let episodeCount: Int
    let unplayedCount: Int
    let isEditMode: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                // Podcast Artwork
                AsyncImage(url: podcast.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Podcast")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                // Edit Mode Delete Button
                if isEditMode {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                            .background(
                                Circle()
                                    .fill(Color.white)
                                    .shadow(radius: 2)
                            )
                    }
                    .offset(x: 8, y: -8)
                }
                
                // Unplayed Count Badge
                if unplayedCount > 0 && !isEditMode {
                    Text("\(unplayedCount)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                        .offset(x: 8, y: -8)
                }
            }
            
            // Podcast Info
            VStack(spacing: 6) {
                Text(podcast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .frame(minHeight: 36)
                
                if episodeCount > 0 {
                    Text("\(episodeCount) episodes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )
                } else {
                    Text("No episodes")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .scaleEffect(isEditMode ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isEditMode)
    }
}

struct EnhancedEpisodeRow: View {
    let episode: Episode
    let podcast: Podcast?
    
    var body: some View {
        HStack(spacing: 12) {
            // Episode/Podcast Artwork
            AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                if let podcast = podcast {
                    Text(podcast.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    if let publishedDate = episode.publishedDate {
                        Text(publishedDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if episode.played {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if episode.playbackPosition > 0 {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
} 