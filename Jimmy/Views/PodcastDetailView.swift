import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast
    @State private var episodes: [Episode] = []
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @ObservedObject private var episodeCacheService = EpisodeCacheService.shared
    @Environment(\.dismiss) private var dismiss
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }
    
    var isLoading: Bool {
        episodeCacheService.isLoadingEpisodes[podcast.id] ?? false
    }
    
    var loadingError: String? {
        episodeCacheService.loadingErrors[podcast.id]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Content
            ScrollView {
                VStack(spacing: 0) {
                    // Podcast Header - Show Picture + Details
                    PodcastDetailHeaderView(podcast: podcast)
                    
                    // Episodes List
                    PodcastEpisodesListView(
                        episodes: episodes,
                        isLoading: isLoading,
                        loadingError: loadingError,
                        podcast: podcast,
                        currentPlayingEpisode: currentPlayingEpisode,
                        onRetry: {
                            loadEpisodes(forceRefresh: true)
                        },
                        onRefresh: {
                            loadEpisodes(forceRefresh: true)
                        }
                    )
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Library")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    loadEpisodes(forceRefresh: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .disabled(isLoading)
            }
        }
        .onAppear {
            loadEpisodes()
        }
        .refreshable {
            await withCheckedContinuation { continuation in
                loadEpisodes(forceRefresh: true) {
                    continuation.resume()
                }
            }
        }
    }
    
    private func loadEpisodes(forceRefresh: Bool = false, completion: (() -> Void)? = nil) {
        // Always clear episodes first to prevent any potential duplication
        episodes = []
        
        // Try to load from cache immediately if available and not force refreshing
        if !forceRefresh, let cachedEpisodes = episodeCacheService.getCachedEpisodes(for: podcast.id) {
            episodes = cachedEpisodes
            
            // Debug logging for cached episodes
            print("📱 Loaded \(cachedEpisodes.count) cached episodes for \(podcast.title)")
            print("📱 First 3 cached episode titles:")
            for (index, episode) in cachedEpisodes.prefix(3).enumerated() {
                print("   \(index + 1). \(episode.title) (ID: \(episode.id))")
            }
            
            completion?()
            return
        }
        
        // Fetch episodes using cache service
        episodeCacheService.getEpisodes(for: podcast, forceRefresh: forceRefresh) { fetchedEpisodes in
            // Debug logging for fetched episodes
            print("📱 Fetched \(fetchedEpisodes.count) episodes from network for \(podcast.title)")
            print("📱 First 3 fetched episode titles:")
            for (index, episode) in fetchedEpisodes.prefix(3).enumerated() {
                print("   \(index + 1). \(episode.title) (ID: \(episode.id))")
            }
            
            // Check for potential title-based duplicates
            let titleCounts = Dictionary(grouping: fetchedEpisodes, by: { $0.title }).mapValues { $0.count }
            let duplicateTitles = titleCounts.filter { $0.value > 1 }
            if !duplicateTitles.isEmpty {
                print("⚠️ Found episodes with duplicate titles:")
                for (title, count) in duplicateTitles {
                    print("   '\(title)' appears \(count) times")
                }
            }
            
            // Deduplicate episodes by ID AND by podcast name + episode title
            var episodeDict: [UUID: Episode] = [:]
            var titlePodcastDict: [String: Episode] = [:]
            
            for episode in fetchedEpisodes {
                guard let podcastID = episode.podcastID else { continue }
                let titleKey = "\(podcastID.uuidString)_\(episode.title)"
                
                // Skip if we already have this episode by ID
                if episodeDict[episode.id] != nil {
                    continue
                }
                
                // Skip if we already have an episode with the same title for this podcast
                if let existingEpisode = titlePodcastDict[titleKey] {
                    // Keep the one with the more recent published date, or first one if dates are equal
                    switch (episode.publishedDate, existingEpisode.publishedDate) {
                    case (let newDate?, let existingDate?):
                        if newDate > existingDate {
                            // Replace with newer episode
                            episodeDict.removeValue(forKey: existingEpisode.id)
                            episodeDict[episode.id] = episode
                            titlePodcastDict[titleKey] = episode
                        }
                        // Otherwise keep existing
                    case (_, nil):
                        // New episode has date, existing doesn't - prefer new
                        episodeDict.removeValue(forKey: existingEpisode.id)
                        episodeDict[episode.id] = episode
                        titlePodcastDict[titleKey] = episode
                    default:
                        // Keep existing episode
                        break
                    }
                } else {
                    // New episode - add it
                    episodeDict[episode.id] = episode
                    titlePodcastDict[titleKey] = episode
                }
            }
            
            episodes = Array(episodeDict.values).sorted { episode1, episode2 in
                switch (episode1.publishedDate, episode2.publishedDate) {
                case (let date1?, let date2?):
                    return date1 > date2 // Most recent first
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return episode1.title.localizedCaseInsensitiveCompare(episode2.title) == .orderedAscending
                }
            }
            
            // Only sync with global episode view model when we fetch fresh data
            // This prevents duplication while ensuring new episodes are added to the library
            episodeCacheService.syncWithEpisodeViewModel(episodes: episodes)
            
            print("📱 Final result: \(episodes.count) unique episodes for \(podcast.title) (deduped from \(fetchedEpisodes.count))")
            print("📱 Final first 3 episode titles:")
            for (index, episode) in episodes.prefix(3).enumerated() {
                print("   \(index + 1). \(episode.title) (ID: \(episode.id))")
            }
            
            completion?()
        }
    }
}

// MARK: - Podcast Detail Header
struct PodcastDetailHeaderView: View {
    let podcast: Podcast
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Show Picture (Left side) - Artwork removed
            // AsyncImage(url: podcast.artworkURL) { image in
            //     image
            //         .resizable()
            //         .aspectRatio(contentMode: .fill)
            // } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)], // Placeholder color
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "방송") // Using a generic podcast icon (Korean for broadcast)
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.8))
                    )
            // }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2) // Shadow removed
            
            // Show Details (Right side)
            VStack(alignment: .leading, spacing: 8) {
                // Show Name
                Text(podcast.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Show Author
                Text(podcast.author)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Show Details/Description
                if !podcast.description.isEmpty {
                    Text(podcast.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Episodes List Section
struct PodcastEpisodesListView: View {
    let episodes: [Episode]
    let isLoading: Bool
    let loadingError: String?
    let podcast: Podcast
    let currentPlayingEpisode: Episode?
    let onRetry: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Episodes List
            if episodes.isEmpty && !isLoading {
                EmptyEpisodesStateView(loadingError: loadingError, onRetry: onRetry)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(episodes) { episode in
                        EpisodeRowView(
                            episode: episode,
                            podcast: podcast,
                            isCurrentlyPlaying: currentPlayingEpisode?.id == episode.id,
                            onTap: {
                                QueueViewModel.shared.playEpisodeFromLibrary(episode)
                            },
                            onPlayNext: { episode in
                                QueueViewModel.shared.addToTopOfQueue(episode)
                                FeedbackManager.shared.playNext()
                            },
                            onMarkAsPlayed: { episode, played in
                                EpisodeViewModel.shared.markEpisodeAsPlayed(episode, played: played)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Loading indicator
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
    }
}

// MARK: - Empty Episodes State
struct EmptyEpisodesStateView: View {
    let loadingError: String?
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            if let error = loadingError {
                // Error state
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Connection Error")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            } else {
                // Default empty state
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                
                Text("No Episodes Available")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Episodes will appear here when they become available")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }
}

// MARK: - Search Result Detail View
struct SearchResultDetailView: View {
    let result: PodcastSearchResult
    @State private var episodes: [Episode] = []
    @State private var isSubscribed = false
    @State private var showingSubscriptionAlert = false
    @State private var subscriptionMessage = ""
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @ObservedObject private var episodeCacheService = EpisodeCacheService.shared
    @Environment(\.dismiss) private var dismiss
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode
    }
    
    private var podcast: Podcast {
        result.toPodcast()
    }
    
    var isLoading: Bool {
        episodeCacheService.isLoadingEpisodes[podcast.id] ?? false
    }
    
    var loadingError: String? {
        episodeCacheService.loadingErrors[podcast.id]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SearchResultHeaderView(
                    result: result,
                    isSubscribed: isSubscribed,
                    onSubscribe: subscribe
                )
                SearchResultEpisodesSection(
                    episodes: episodes,
                    isLoading: isLoading,
                    loadingError: loadingError,
                    result: result,
                    currentPlayingEpisode: currentPlayingEpisode,
                    onRetry: {
                        loadEpisodes(forceRefresh: true)
                    }
                )
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    dismiss()
                }
                .font(.system(.body, design: .rounded, weight: .medium))
            }
        }
        .onAppear {
            loadEpisodes()
            checkSubscriptionStatus()
        }
        .alert("Subscription", isPresented: $showingSubscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(subscriptionMessage)
        }
    }
    
    private func loadEpisodes(forceRefresh: Bool = false) {
        // Always clear episodes first to prevent any potential duplication
        episodes = []
        
        // Try to load from cache immediately if available and not force refreshing
        if !forceRefresh, let cachedEpisodes = episodeCacheService.getCachedEpisodes(for: podcast.id) {
            episodes = cachedEpisodes
            
            // Debug logging for cached episodes
            print("📱 Search: Loaded \(cachedEpisodes.count) cached episodes for \(podcast.title)")
            print("📱 Search: First 3 cached episode titles:")
            for (index, episode) in cachedEpisodes.prefix(3).enumerated() {
                print("   \(index + 1). \(episode.title) (ID: \(episode.id))")
            }
            
            return
        }
        
        // Fetch episodes using cache service
        episodeCacheService.getEpisodes(for: podcast, forceRefresh: forceRefresh) { fetchedEpisodes in
            // Debug logging for fetched episodes
            print("📱 Search: Fetched \(fetchedEpisodes.count) episodes from network for \(podcast.title)")
            print("📱 Search: First 3 fetched episode titles:")
            for (index, episode) in fetchedEpisodes.prefix(3).enumerated() {
                print("   \(index + 1). \(episode.title) (ID: \(episode.id))")
            }
            
            // Check for potential title-based duplicates
            let titleCounts = Dictionary(grouping: fetchedEpisodes, by: { $0.title }).mapValues { $0.count }
            let duplicateTitles = titleCounts.filter { $0.value > 1 }
            if !duplicateTitles.isEmpty {
                print("⚠️ Search: Found episodes with duplicate titles:")
                for (title, count) in duplicateTitles {
                    print("   '\(title)' appears \(count) times")
                }
            }
            
            // Deduplicate episodes by ID AND by podcast name + episode title
            var episodeDict: [UUID: Episode] = [:]
            var titlePodcastDict: [String: Episode] = [:]
            
            for episode in fetchedEpisodes {
                guard let podcastID = episode.podcastID else { continue }
                let titleKey = "\(podcastID.uuidString)_\(episode.title)"
                
                // Skip if we already have this episode by ID
                if episodeDict[episode.id] != nil {
                    continue
                }
                
                // Skip if we already have an episode with the same title for this podcast
                if let existingEpisode = titlePodcastDict[titleKey] {
                    // Keep the one with the more recent published date, or first one if dates are equal
                    switch (episode.publishedDate, existingEpisode.publishedDate) {
                    case (let newDate?, let existingDate?):
                        if newDate > existingDate {
                            // Replace with newer episode
                            episodeDict.removeValue(forKey: existingEpisode.id)
                            episodeDict[episode.id] = episode
                            titlePodcastDict[titleKey] = episode
                        }
                        // Otherwise keep existing
                    case (_, nil):
                        // New episode has date, existing doesn't - prefer new
                        episodeDict.removeValue(forKey: existingEpisode.id)
                        episodeDict[episode.id] = episode
                        titlePodcastDict[titleKey] = episode
                    default:
                        // Keep existing episode
                        break
                    }
                } else {
                    // New episode - add it
                    episodeDict[episode.id] = episode
                    titlePodcastDict[titleKey] = episode
                }
            }
            
            episodes = Array(episodeDict.values).sorted { episode1, episode2 in
                switch (episode1.publishedDate, episode2.publishedDate) {
                case (let date1?, let date2?):
                    return date1 > date2 // Most recent first
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return episode1.title.localizedCaseInsensitiveCompare(episode2.title) == .orderedAscending
                }
            }
            
            // Only sync with global episode view model when we fetch fresh data
            // This prevents duplication while ensuring new episodes are added to the library
            episodeCacheService.syncWithEpisodeViewModel(episodes: episodes)
            
            print("📱 Search: Final result: \(episodes.count) unique episodes for \(podcast.title) (deduped from \(fetchedEpisodes.count))")
            print("📱 Search: Final first 3 episode titles:")
            for (index, episode) in episodes.prefix(3).enumerated() {
                print("   \(index + 1). \(episode.title) (ID: \(episode.id))")
            }
        }
    }
    
    private func checkSubscriptionStatus() {
        let localPodcasts = PodcastService.shared.loadPodcasts()
        isSubscribed = localPodcasts.contains { $0.feedURL == result.feedURL }
    }
    
    private func subscribe() {
        if isSubscribed {
            subscriptionMessage = "You're already subscribed to \(result.title)"
            showingSubscriptionAlert = true
            return
        }
        
        var podcasts = PodcastService.shared.loadPodcasts()
        podcasts.append(podcast)
        PodcastService.shared.savePodcasts(podcasts)
        
        isSubscribed = true
        subscriptionMessage = "Successfully subscribed to \(result.title)"
        showingSubscriptionAlert = true
    }
}

struct SearchResultHeaderView: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // AsyncImage(url: result.artworkURL) { image in // Artwork removed
            //     image
            //         .resizable()
            //         .aspectRatio(contentMode: .fill)
            // } placeholder: {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)], // Placeholder color
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "magnifyingglass") // Using a generic search/discover icon
                            .font(.system(size: 60))
                            .foregroundColor(.secondary.opacity(0.8))
                    )
            // }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8) // Shadow removed
            
            VStack(spacing: 12) {
                Text(result.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                Text(result.author)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text(result.genre)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                
                Button(action: {
                    if !isSubscribed {
                        onSubscribe()
                    }
                }) {
                    Label(
                        isSubscribed ? "Subscribed" : "Subscribe",
                        systemImage: isSubscribed ? "checkmark.circle.fill" : "plus.circle"
                    )
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundColor(isSubscribed ? .green : .white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSubscribed ? Color.green.opacity(0.2) : Color.blue)
                    )
                }
                .disabled(isSubscribed)
                
                if let description = result.description {
                    Text(description)
                        .font(.system(.body, design: .default))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 40)
        .padding(.horizontal, 20)
    }
}

struct SearchResultEpisodesSection: View {
    let episodes: [Episode]
    let isLoading: Bool
    let loadingError: String?
    let result: PodcastSearchResult
    let currentPlayingEpisode: Episode?
    let onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Latest Episodes")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 20)
            
            if episodes.isEmpty && !isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("Unable to Load Episodes")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Check your internet connection and try again")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(episodes.prefix(10)) { episode in
                        EpisodeRowView(
                            episode: episode,
                            podcast: result.toPodcast(),
                            isCurrentlyPlaying: currentPlayingEpisode?.id == episode.id,
                            onTap: {
                                QueueViewModel.shared.playEpisodeFromLibrary(episode)
                            },
                            onPlayNext: { episode in
                                QueueViewModel.shared.addToTopOfQueue(episode)
                                FeedbackManager.shared.playNext()
                            },
                            onMarkAsPlayed: { episode, played in
                                EpisodeViewModel.shared.markEpisodeAsPlayed(episode, played: played)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

#Preview {
    NavigationView {
        PodcastDetailView(podcast: Podcast(
            id: UUID(),
            title: "Sample Podcast",
            author: "Sample Author",
            description: "This is a sample podcast description that explains what the show is about.",
            feedURL: URL(string: "https://example.com")!,
            artworkURL: nil
        ))
    }
} 