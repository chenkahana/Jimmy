import SwiftUI

struct LibraryView: View {
    @ObservedObject private var libraryController = LibraryController.shared
    @ObservedObject private var episodeController = UnifiedEpisodeController.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // View Type Picker
                viewTypePicker
                
                // Search Bar
                searchBar
                
                // Main Content
                mainContent
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        libraryController.toggleEditMode()
                    }
                }
            }
        }
        .refreshable {
            libraryController.refreshData()
        }
        .onAppear {
            // Debug: Check what data we actually have
            print("📱 LibraryView.onAppear - Podcasts: \(libraryController.subscribedPodcasts.count), Filtered: \(libraryController.filteredPodcasts.count)")
            print("📱 LibraryView.onAppear - Loading: \(libraryController.isLoading), Error: \(libraryController.errorMessage ?? "none")")
        }
    }
    
    // MARK: - View Components
    
    private var viewTypePicker: some View {
        Picker("View Type", selection: $libraryController.selectedViewType) {
            ForEach(LibraryController.LibraryViewType.allCases, id: \.self) { viewType in
                Text(viewType.displayName).tag(viewType)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search podcasts and episodes", text: $libraryController.searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !libraryController.searchText.isEmpty {
                Button("Clear") {
                    libraryController.clearSearch()
                }
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if libraryController.isLoading {
            loadingView
        } else if libraryController.filteredPodcasts.isEmpty && libraryController.selectedViewType != .episodes {
            emptyStateView
        } else {
            switch libraryController.selectedViewType {
            case .shows:
                podcastsView
            case .grid:
                podcastsGridView
            case .episodes:
                episodesView
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading Library...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Podcasts Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your subscribed podcasts will appear here. Go to Discover to find and subscribe to podcasts.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(spacing: 8) {
                Text("Debug Info:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Subscribed: \(libraryController.subscribedPodcasts.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Filtered: \(libraryController.filteredPodcasts.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Loading: \(libraryController.isLoading ? "Yes" : "No")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var podcastsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(libraryController.filteredPodcasts, id: \.id) { podcast in
                    NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                        PodcastRowView(
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
            .padding(.horizontal)
        }
    }
    
    private var podcastsGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 16) {
                ForEach(libraryController.filteredPodcasts, id: \.id) { podcast in
                    NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                        PodcastGridItemView(
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
            .padding(.horizontal)
        }
    }
    
    private var episodesView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(libraryController.filteredEpisodes, id: \.id) { episode in
                    EpisodeRowView(
                        episode: episode,
                        podcast: libraryController.getPodcast(for: episode) ?? Podcast(title: "Unknown", author: "", description: "", feedURL: URL(string: "https://example.com")!, artworkURL: nil),
                        isCurrentlyPlaying: audioPlayer.currentEpisode?.id == episode.id,
                        onTap: {
                            audioPlayer.loadEpisode(episode)
                            audioPlayer.play()
                        },
                        onPlayNext: { episode in
                            // Add to queue next
                        },
                        onMarkAsPlayed: { episode, played in
                            episodeController.markEpisodeAsPlayed(episode, played: played)
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

}

// MARK: - Supporting Views

struct PodcastGridItemView: View {
    let podcast: Podcast
    let episodeCount: Int
    let unplayedCount: Int
    let isEditMode: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Podcast Artwork (Square)
                AsyncImage(url: podcast.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "mic.circle.fill")
                                .foregroundColor(.gray)
                                .font(.title)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                // Edit Mode Delete Button
                if isEditMode {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .background(Color.white)
                            .clipShape(Circle())
                            .font(.title2)
                    }
                    .offset(x: 8, y: -8)
                }
                
                // Unplayed Count Badge
                if unplayedCount > 0 && !isEditMode {
                    Text("\(unplayedCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -8)
                }
            }
            
            // Podcast Info
            VStack(spacing: 2) {
                Text(podcast.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                if episodeCount > 0 {
                    Text("\(episodeCount) episodes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct PodcastRowView: View {
    let podcast: Podcast
    let episodeCount: Int
    let unplayedCount: Int
    let isEditMode: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
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
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Podcast Info
            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Text("\(episodeCount) episodes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if unplayedCount > 0 {
                        Text("• \(unplayedCount) new")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            // Edit Mode Controls
            if isEditMode {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                // Navigate to podcast detail
            }
        }
    }
}

// MARK: - Preview

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
} 