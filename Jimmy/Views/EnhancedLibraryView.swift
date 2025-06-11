import SwiftUI

/// Enhanced LibraryView that integrates with the new episode fetching architecture
/// Provides instant cache display and non-blocking background updates
struct EnhancedLibraryView: View {
    @State private var searchText: String = ""
    @State private var subscribedPodcasts: [Podcast] = []
    @State private var isEditMode: Bool = false
    @State private var selectedViewType: LibraryViewType = .shows
    @State private var showingRefreshAlert: Bool = false
    
    // Enhanced episode controller
    @ObservedObject private var episodeController = EnhancedEpisodeController.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    // Performance optimizations
    @State private var isInitialLoad = true
    @State private var lastRefreshTime: Date?
    
    enum LibraryViewType: String, CaseIterable {
        case shows = "Shows"
        case episodes = "Episodes"
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    // MARK: - Computed Properties
    
    var filteredPodcasts: [Podcast] {
        if searchText.isEmpty {
            return subscribedPodcasts.sorted { podcast1, podcast2 in
                switch (podcast1.lastEpisodeDate, podcast2.lastEpisodeDate) {
                case (let date1?, let date2?):
                    return date1 > date2
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending
                }
            }
        } else {
            return subscribedPodcasts.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.author.localizedCaseInsensitiveContains(searchText) 
            }.sorted { podcast1, podcast2 in
                switch (podcast1.lastEpisodeDate, podcast2.lastEpisodeDate) {
                case (let date1?, let date2?):
                    return date1 > date2
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending
                }
            }
        }
    }
    
    var filteredEpisodes: [Episode] {
        let subscribedPodcastIDs = Set(subscribedPodcasts.map { $0.id })
        let episodes = episodeController.episodes.filter { episode in
            guard let podcastID = episode.podcastID else { return false }
            return subscribedPodcastIDs.contains(podcastID)
        }
        
        if searchText.isEmpty {
            return episodes.sorted { 
                ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) 
            }
        } else {
            return episodes.filter { episode in
                let podcast = getPodcast(for: episode)
                return episode.title.localizedCaseInsensitiveContains(searchText) ||
                       (episode.description?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                       podcast?.title.localizedCaseInsensitiveContains(searchText) == true ||
                       podcast?.author.localizedCaseInsensitiveContains(searchText) == true
            }.sorted { 
                ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) 
            }
        }
    }

    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with cache status
                headerView
                
                // Segmented Control
                Picker("View Type", selection: $selectedViewType) {
                    ForEach(LibraryViewType.allCases, id: \.self) { viewType in
                        Text(viewType.rawValue).tag(viewType)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Search Bar
                LibrarySearchComponent(searchText: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // Main Content
                mainContentView
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarContent
                }
            }
            .refreshable {
                await refreshContent()
            }
        }
        .onAppear {
            Task {
                await handleViewAppear()
            }
        }
        .alert("Refresh Episodes", isPresented: $showingRefreshAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Refresh") {
                Task {
                    await forceRefreshEpisodes()
                }
            }
        } message: {
            Text("This will fetch the latest episodes from all your subscribed podcasts.")
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerView: some View {
        if selectedViewType == .episodes {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(episodeController.cacheStatus.displayText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if episodeController.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else if episodeController.isRefreshing {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .rotationEffect(.degrees(episodeController.isRefreshing ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: episodeController.isRefreshing)
                        }
                    }
                    
                    if let lastUpdate = episodeController.lastUpdateTime {
                        Text("Updated \(lastUpdate, style: .relative) ago")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Text("\(episodeController.episodeCount) episodes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        if selectedViewType == .shows {
            showsView
        } else {
            episodesView
        }
    }
    
    @ViewBuilder
    private var showsView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                PodcastGridComponent(
                    podcasts: filteredPodcasts,
                    isLoading: false,
                    onPodcastTap: { podcast in
                        // Handle podcast tap - navigate to podcast detail
                    },
                    onPodcastLongPress: isEditMode ? { podcast in
                        deletePodcast(podcast)
                    } : nil
                )
                
                Spacer(minLength: 50)
            }
            .padding(.top, 16)
        }
    }
    
    @ViewBuilder
    private var episodesView: some View {
        Group {
            if episodeController.episodes.isEmpty && episodeController.isLoading {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading episodes...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEpisodes.isEmpty && !subscribedPodcasts.isEmpty {
                // Empty state with actions
                emptyEpisodesView
            } else {
                // Episodes list
                EnhancedEpisodesListView(
                    episodes: filteredEpisodes,
                    searchText: searchText,
                    getPodcast: getPodcast,
                    onEpisodeTap: { episode in
                        // Handle episode tap
                        QueueViewModel.shared.playEpisodeFromLibrary(episode)
                    },
                    onMarkAsPlayed: { episode, played in
                        Task {
                            await episodeController.markEpisodeAsPlayed(episode, played: played)
                        }
                    }
                )
                .padding(.top, 16)
            }
        }
    }
    
    @ViewBuilder
    private var emptyEpisodesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Episodes Found")
                    .font(.title2)
                    .fontWeight(.medium)
                
                if episodeController.errorMessage != nil {
                    Text("There was an error loading episodes")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else if episodeController.cacheStatus.needsRefresh {
                    Text("Episodes are being loaded in the background")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Your subscribed podcasts don't have any episodes yet")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if episodeController.errorMessage != nil || episodeController.cacheStatus.needsRefresh {
                Button("Refresh Episodes") {
                    Task {
                        await refreshContent()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        HStack(spacing: 12) {
            if selectedViewType == .episodes {
                // Refresh button
                Button(action: {
                    showingRefreshAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                        Text("Refresh")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .disabled(episodeController.isRefreshing)
            }
            
            // Edit button (only for shows)
            if selectedViewType == .shows {
                Button(isEditMode ? "Done" : "Edit") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditMode.toggle()
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        guard let podcastID = episode.podcastID else { return nil }
        return subscribedPodcasts.first { $0.id == podcastID }
    }
    
    private func deletePodcast(_ podcast: Podcast) {
        withAnimation(.easeInOut(duration: 0.3)) {
            subscribedPodcasts.removeAll { $0.id == podcast.id }
            PodcastService.shared.savePodcasts(subscribedPodcasts)
        }
    }
    
    // MARK: - Async Methods
    
    private func handleViewAppear() async {
        if isInitialLoad {
            isInitialLoad = false
            
            // Load podcasts immediately
            subscribedPodcasts = PodcastService.shared.loadPodcasts()
            
            // Load episodes (non-blocking)
            await episodeController.loadEpisodes()
        } else {
            // Subsequent appearances - just refresh if needed
            let needsRefresh = await EpisodeRepository.shared.needsRefresh()
            if needsRefresh {
                await episodeController.loadEpisodes()
            }
        }
    }
    
    private func refreshContent() async {
        lastRefreshTime = Date()
        
        // Refresh podcasts
        subscribedPodcasts = PodcastService.shared.loadPodcasts()
        
        // Refresh episodes
        await episodeController.refreshEpisodes()
    }
    
    private func forceRefreshEpisodes() async {
        await episodeController.refreshEpisodes()
        await episodeController.processQueuedRequests()
    }
}

// MARK: - Enhanced Episodes List View

struct EnhancedEpisodesListView: View {
    let episodes: [Episode]
    let searchText: String
    let getPodcast: (Episode) -> Podcast?
    let onEpisodeTap: (Episode) -> Void
    let onMarkAsPlayed: (Episode, Bool) -> Void
    
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(episodes) { episode in
                    EnhancedEpisodeRowView(
                        episode: episode,
                        podcast: getPodcast(episode),
                        isCurrentlyPlaying: audioPlayer.currentEpisode?.id == episode.id,
                        onTap: { onEpisodeTap(episode) },
                        onMarkAsPlayed: { played in
                            onMarkAsPlayed(episode, played)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Enhanced Episode Row View

struct EnhancedEpisodeRowView: View {
    let episode: Episode
    let podcast: Podcast?
    let isCurrentlyPlaying: Bool
    let onTap: () -> Void
    let onMarkAsPlayed: (Bool) -> Void
    
    @State private var showingContextMenu = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Episode artwork or podcast artwork
            AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "waveform")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Episode info
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(isCurrentlyPlaying ? .accentColor : .primary)
                
                if let podcast = podcast {
                    Text(podcast.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Text(episode.publishedDate ?? Date(), style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let duration = episode.duration, duration > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if episode.played {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            // Play/Pause button
            Button(action: onTap) {
                Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button(action: {
                onMarkAsPlayed(!episode.played)
            }) {
                Label(episode.played ? "Mark as Unplayed" : "Mark as Played", 
                      systemImage: episode.played ? "circle" : "checkmark.circle")
            }
            
            Button(action: {
                QueueViewModel.shared.addToTopOfQueue(episode)
            }) {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            
            Button(action: {
                QueueViewModel.shared.addToQueue(episode)
            }) {
                Label("Add to Queue", systemImage: "plus")
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct EnhancedLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedLibraryView()
    }
}
#endif 