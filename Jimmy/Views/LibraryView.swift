import SwiftUI

struct LibraryView: View {
    @State private var searchText: String = ""
    @State private var subscribedPodcasts: [Podcast] = []
    @State private var isEditMode: Bool = false
    @State private var selectedViewType: LibraryViewType = .episodes
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @ObservedObject private var episodeViewModel = EpisodeViewModel.shared
    @ObservedObject private var updateService = EpisodeUpdateService.shared
    @ObservedObject private var episodeCacheService = EpisodeCacheService.shared
    @State private var episodesUpdatedObserver: NSObjectProtocol?
    
    // PERFORMANCE FIX: Memory caching system for instant tab switching
    @State private var cachedFilteredPodcasts: [Podcast] = []
    @State private var cachedAllEpisodes: [Episode] = []
    @State private var lastSearchText: String = ""
    @State private var lastSubscribedPodcastsHash: Int = 0
    @State private var lastEpisodesHash: Int = 0
    @State private var isInitialLoad = true
    @State private var isCacheReady = false
    
    // INSTANT DISPLAY: Pre-computed data ready for immediate display
    @State private var displayEpisodes: [Episode] = []
    @State private var displayPodcasts: [Podcast] = []
    
    enum LibraryViewType: String, CaseIterable {
        case shows = "Shows"
        case episodes = "Episodes"
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    // INSTANT DISPLAY: Always return cached data immediately for fast tab switching
    var filteredPodcasts: [Podcast] {
        // PERFORMANCE FIX: Only update cache if data has actually changed, not on every access
        return displayPodcasts
    }

    var allEpisodes: [Episode] {
        // PERFORMANCE FIX: Only update cache if data has actually changed, not on every access
        return displayEpisodes
    }
    
    // INSTANT CACHE: Synchronous update for immediate initial loading
    private func updateCachedFilteredPodcastsSync() {
        let podcastsToFilter: [Podcast]
        
        if searchText.isEmpty {
            podcastsToFilter = subscribedPodcasts
        } else {
            podcastsToFilter = subscribedPodcasts.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.author.localizedCaseInsensitiveContains(searchText) 
            }
        }
        
        // Sort by lastEpisodeDate (most recent first), with fallback to title for podcasts without dates
        let sortedPodcasts = podcastsToFilter.sorted { podcast1, podcast2 in
            switch (podcast1.lastEpisodeDate, podcast2.lastEpisodeDate) {
            case (let date1?, let date2?):
                return date1 > date2 // Most recent first
            case (nil, _?):
                return false // Podcasts without dates go to the end
            case (_?, nil):
                return true // Podcasts with dates come before those without
            case (nil, nil):
                return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending // Alphabetical fallback
            }
        }
        
        // Update both cache and display data
        cachedFilteredPodcasts = sortedPodcasts
        displayPodcasts = sortedPodcasts
        lastSearchText = searchText
        lastSubscribedPodcastsHash = subscribedPodcasts.count
    }
    
    // BACKGROUND UPDATE: Async update for subsequent changes
    private func updateCachedFilteredPodcastsAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            let podcastsToFilter: [Podcast]
            
            if self.searchText.isEmpty {
                podcastsToFilter = self.subscribedPodcasts
            } else {
                podcastsToFilter = self.subscribedPodcasts.filter { 
                    $0.title.localizedCaseInsensitiveContains(self.searchText) || 
                    $0.author.localizedCaseInsensitiveContains(self.searchText) 
                }
            }
            
            // Sort by lastEpisodeDate (most recent first), with fallback to title for podcasts without dates
            let sortedPodcasts = podcastsToFilter.sorted { podcast1, podcast2 in
                switch (podcast1.lastEpisodeDate, podcast2.lastEpisodeDate) {
                case (let date1?, let date2?):
                    return date1 > date2 // Most recent first
                case (nil, _?):
                    return false // Podcasts without dates go to the end
                case (_?, nil):
                    return true // Podcasts with dates come before those without
                case (nil, nil):
                    return podcast1.title.localizedCaseInsensitiveCompare(podcast2.title) == .orderedAscending // Alphabetical fallback
                }
            }
            
            // Update display data on main thread
            DispatchQueue.main.async {
                self.cachedFilteredPodcasts = sortedPodcasts
                self.displayPodcasts = sortedPodcasts
                self.lastSearchText = self.searchText
                self.lastSubscribedPodcastsHash = self.subscribedPodcasts.count
            }
        }
    }
    
    // INSTANT CACHE: Synchronous update for immediate initial loading
    private func updateCachedAllEpisodesSync() {
        let subscribedPodcastIDs = Set(subscribedPodcasts.map { $0.id })
        let episodes = episodeViewModel.episodes.filter { episode in
            guard let podcastID = episode.podcastID else { return false }
            return subscribedPodcastIDs.contains(podcastID)
        }
        
        // Filter by search text if provided
        let filteredEpisodes = searchText.isEmpty ? episodes : episodes.filter { episode in
            let podcast = getPodcast(for: episode)
            return episode.title.localizedCaseInsensitiveContains(searchText) ||
                   episode.description?.localizedCaseInsensitiveContains(searchText) == true ||
                   podcast?.title.localizedCaseInsensitiveContains(searchText) == true ||
                   podcast?.author.localizedCaseInsensitiveContains(searchText) == true
        }
        
        // Sort by publication date (most recent first)
        let sortedEpisodes = filteredEpisodes.sorted { episode1, episode2 in
            switch (episode1.publishedDate, episode2.publishedDate) {
            case (let date1?, let date2?):
                return date1 > date2 // Most recent first
            case (nil, _?):
                return false // Episodes without dates go to the end
            case (_?, nil):
                return true // Episodes with dates come before those without
            case (nil, nil):
                return episode1.title.localizedCaseInsensitiveCompare(episode2.title) == .orderedAscending // Alphabetical fallback
            }
        }
        
        // Update both cache and display data
        cachedAllEpisodes = sortedEpisodes
        displayEpisodes = sortedEpisodes
        lastSearchText = searchText
        lastEpisodesHash = episodeViewModel.episodes.count
        lastSubscribedPodcastsHash = subscribedPodcasts.count
    }
    
    // BACKGROUND UPDATE: Async update for subsequent changes
    private func updateCachedAllEpisodesAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            let subscribedPodcastIDs = Set(self.subscribedPodcasts.map { $0.id })
            let episodes = self.episodeViewModel.episodes.filter { episode in
                guard let podcastID = episode.podcastID else { return false }
                return subscribedPodcastIDs.contains(podcastID)
            }
            
            // Filter by search text if provided
            let filteredEpisodes = self.searchText.isEmpty ? episodes : episodes.filter { episode in
                let podcast = self.getPodcast(for: episode)
                return episode.title.localizedCaseInsensitiveContains(self.searchText) ||
                       episode.description?.localizedCaseInsensitiveContains(self.searchText) == true ||
                       podcast?.title.localizedCaseInsensitiveContains(self.searchText) == true ||
                       podcast?.author.localizedCaseInsensitiveContains(self.searchText) == true
            }
            
            // Sort by publication date (most recent first)
            let sortedEpisodes = filteredEpisodes.sorted { episode1, episode2 in
                switch (episode1.publishedDate, episode2.publishedDate) {
                case (let date1?, let date2?):
                    return date1 > date2 // Most recent first
                case (nil, _?):
                    return false // Episodes without dates go to the end
                case (_?, nil):
                    return true // Episodes with dates come before those without
                case (nil, nil):
                    return episode1.title.localizedCaseInsensitiveCompare(episode2.title) == .orderedAscending // Alphabetical fallback
                }
            }
            
            // Update display data on main thread
            DispatchQueue.main.async {
                self.cachedAllEpisodes = sortedEpisodes
                self.displayEpisodes = sortedEpisodes
                self.lastSearchText = self.searchText
                self.lastEpisodesHash = self.episodeViewModel.episodes.count
                self.lastSubscribedPodcastsHash = self.subscribedPodcasts.count
            }
        }
    }

    private func getPodcast(for episode: Episode) -> Podcast? {
        guard let podcastID = episode.podcastID else { return nil }
        return subscribedPodcasts.first { $0.id == podcastID }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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
                SearchBarView(searchText: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // Main Content Area - Use lazy loading to prevent UI freezes
                if selectedViewType == .shows {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            // Subscribed Shows Section
                            SubscribedShowsGridView(
                                podcasts: filteredPodcasts,
                                searchText: searchText,
                                isEditMode: isEditMode,
                                onDelete: { podcast in
                                    deletePodcast(podcast)
                                }
                            )

                            Spacer(minLength: 50)
                        }
                        .padding(.top, 16)
                    }
                } else {
                    EpisodesListView(
                        episodes: allEpisodes,
                        searchText: searchText,
                        getPodcast: getPodcast
                    )
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Update button (only for episodes view)
                        if selectedViewType == .episodes && updateService.lastUpdateTime != nil {
                            Button(action: {
                                updateService.forceUpdate()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)
                            }
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
            }
        }
        .onAppear {
            // PERFORMANCE FIX: Make all loading operations asynchronous to prevent UI freeze
            if isInitialLoad {
                isInitialLoad = false
                
                // 1. Load basic data first (podcasts) - keep minimal for immediate display
                loadSubscribedPodcasts()
                
                // 2. Provide immediate empty display data to prevent UI waiting
                displayPodcasts = subscribedPodcasts
                displayEpisodes = []
                isCacheReady = true
                
                // 3. Start building proper cache asynchronously - prevents UI freeze
                DispatchQueue.global(qos: .userInitiated).async {
                    // Build cache on background thread, then update UI
                    DispatchQueue.main.async {
                        self.updateCachedFilteredPodcastsAsync()
                        self.updateCachedAllEpisodesAsync()
                    }
                }
                
                // 4. Setup background operations (non-blocking)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Setup notification observer
                    setupEpisodesUpdatedObserver()
                    
                    // Load additional episodes in background if needed
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.loadAllEpisodesForPodcasts()
                    }
                }
                
                // 5. Defer cleanup and maintenance operations
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    DispatchQueue.global(qos: .utility).async {
                        // Clean up large UserDefaults data that has been migrated to file storage
                        UserDefaultsCleanup.shared.performCleanup()
                        
                        // Fix artwork URLs for sample podcasts and refresh real ones
                        if UserDefaults.standard.bool(forKey: "artworkFixApplied") == false {
                            print("🎨 Applying one-time artwork fix...")
                            self.fixPodcastArtwork()
                            UserDefaults.standard.set(true, forKey: "artworkFixApplied")
                        }
                    }
                }
            }
            // Trigger episode update if enough time has passed - but don't block UI
            if updateService.needsUpdate() {
                DispatchQueue.global(qos: .background).async {
                    updateService.forceUpdate()
                }
            }
            // INSTANT DISPLAY: Cache is ready, no additional work needed on subsequent appearances
        }
        .onDisappear {
            if let observer = episodesUpdatedObserver {
                NotificationCenter.default.removeObserver(observer)
                episodesUpdatedObserver = nil
            }
        }
        .onChange(of: selectedViewType) {
            // Reset edit mode when switching views
            isEditMode = false
        }
        .onChange(of: searchText) {
            // PERFORMANCE FIX: Update display data only when search actually changes
            if isCacheReady && searchText != lastSearchText {
                updateCachedFilteredPodcastsAsync()
                updateCachedAllEpisodesAsync()
            }
        }
        .onChange(of: subscribedPodcasts.count) {
            // PERFORMANCE FIX: Update display data when podcasts change
            if isCacheReady && subscribedPodcasts.count != lastSubscribedPodcastsHash {
                updateCachedFilteredPodcastsAsync()
                updateCachedAllEpisodesAsync()
            }
        }
        .onChange(of: episodeViewModel.episodes.count) {
            // PERFORMANCE FIX: Update display data when episodes change
            if isCacheReady && episodeViewModel.episodes.count != lastEpisodesHash {
                updateCachedAllEpisodesAsync()
            }
        }
        .keyboardDismissToolbar()
    }
    

    
    private func loadSubscribedPodcasts() {
        subscribedPodcasts = PodcastService.shared.loadPodcasts()
        
        // For testing purposes - add sample data if no podcasts exist
        // DISABLED: Let new users start with empty library
        // if subscribedPodcasts.isEmpty {
        //     addSampleDataForTesting()
        // }
    }
    
    private func loadAllEpisodesForPodcasts() {
        // PERFORMANCE FIX: Always show cached episodes immediately, never wait for network
        
        // 1. First, check if we have any episodes already (from cache loading)
        if !episodeViewModel.episodes.isEmpty {
            // We have cached episodes - just update the display cache
            DispatchQueue.main.async {
                self.updateCachedAllEpisodesAsync()
            }
            return 
        }
        
        // 2. If no cached episodes, load from disk immediately (non-blocking)
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Try to load episodes from disk cache first
            if let cachedEpisodes: [Episode] = FileStorage.shared.load([Episode].self, from: "episodes.json"),
               !cachedEpisodes.isEmpty {
                
                // Show cached episodes immediately on main thread
                DispatchQueue.main.async {
                    episodeViewModel.episodes = cachedEpisodes
                    updateCachedAllEpisodesAsync()
                    print("📱 Loaded \(cachedEpisodes.count) cached episodes from disk")
                }
                
                // Schedule background refresh after UI is ready (much later)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    scheduleBackgroundEpisodeRefresh()
                }
                return
            }
            
            // 3. If no cached episodes exist, only then consider fresh fetch
            // But still defer it to prevent startup blocking
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                handleFirstTimeEpisodeLoad()
            }
        }
        
        // 4. Always clean up and add sample data if needed (for testing)
        cleanupSampleEpisodesFromRealPodcasts()
        addSampleEpisodesForTesting()
    }
    
    private func scheduleBackgroundEpisodeRefresh() {
        let realPodcasts = subscribedPodcasts.filter { podcast in
            let feedURLString = podcast.feedURL.absoluteString
            let artworkURLString = podcast.artworkURL?.absoluteString ?? ""
            return !feedURLString.contains("example.com") && 
                   !artworkURLString.contains("picsum.photos")
        }
        
        if !realPodcasts.isEmpty {
            print("🔄 Scheduling background episode refresh for \(realPodcasts.count) podcasts")
            // Background refresh - completely non-blocking
            DispatchQueue.global(qos: .background).async {
                EpisodeUpdateService.shared.forceUpdate()
            }
        }
    }
    
    private func handleFirstTimeEpisodeLoad() {
        let realPodcasts = subscribedPodcasts.filter { podcast in
            let feedURLString = podcast.feedURL.absoluteString
            let artworkURLString = podcast.artworkURL?.absoluteString ?? ""
            return !feedURLString.contains("example.com") && 
                   !artworkURLString.contains("picsum.photos")
        }
        
        if !realPodcasts.isEmpty {
            print("🌟 First time setup - fetching episodes for \(realPodcasts.count) podcasts")
            // Even first-time loading should be non-blocking
            DispatchQueue.global(qos: .utility).async {
                EpisodeUpdateService.shared.forceUpdate()
            }
        }
    }
    
    private func cleanupSampleEpisodesFromRealPodcasts() {
        // Get all real podcasts (non-sample ones)
        let realPodcasts = subscribedPodcasts.filter { podcast in
            let feedURLString = podcast.feedURL.absoluteString
            let artworkURLString = podcast.artworkURL?.absoluteString ?? ""
            
            // Real podcasts don't have example.com or picsum.photos URLs
            return !feedURLString.contains("example.com") && 
                   !artworkURLString.contains("picsum.photos")
        }
        
        // Remove episodes for real podcasts so they can be properly fetched from RSS
        for podcast in realPodcasts {
            episodeViewModel.removeEpisodes(for: podcast.id)
        }
        
        if !realPodcasts.isEmpty {
            print("🧹 Cleaned up episodes for \(realPodcasts.count) real podcasts")
        }
    }
    
    private func addSampleEpisodesForTesting() {
        // Only add sample episodes if none exist
        guard episodeViewModel.episodes.isEmpty else { return }
        
        // Only create sample episodes for sample/test podcasts (those with picsum.photos URLs or other test indicators)
        let samplePodcasts = subscribedPodcasts.filter { podcast in
            // Check if this is a sample/test podcast by looking at its feedURL or artworkURL
            let feedURLString = podcast.feedURL.absoluteString
            let artworkURLString = podcast.artworkURL?.absoluteString ?? ""
            
            return feedURLString.contains("example.com") || 
                   artworkURLString.contains("picsum.photos")
        }
        
        // If no sample podcasts exist, don't create any sample episodes
        guard !samplePodcasts.isEmpty else { return }
        
        let calendar = Calendar.current
        let now = Date()
        
        var sampleEpisodes: [Episode] = []
        
        for (index, podcast) in samplePodcasts.enumerated() {
            // Add 3-5 episodes per sample podcast only
            let episodeCount = Int.random(in: 3...5)
            
            for episodeIndex in 0..<episodeCount {
                let daysAgo = index * 3 + episodeIndex
                let episodeDate = calendar.date(byAdding: .day, value: -daysAgo, to: now)
                
                let episode = Episode(
                    id: UUID(),
                    title: generateSampleEpisodeTitle(for: podcast, episodeNumber: episodeIndex + 1),
                    artworkURL: podcast.artworkURL,
                    audioURL: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-\(episodeIndex + 1).mp3"),
                    description: generateSampleEpisodeDescription(for: podcast, episodeNumber: episodeIndex + 1),
                    played: Bool.random(),
                    podcastID: podcast.id,
                    publishedDate: episodeDate,
                    localFileURL: nil,
                    playbackPosition: Bool.random() ? TimeInterval.random(in: 0...3600) : 0
                )
                
                sampleEpisodes.append(episode)
            }
        }
        
        // Only add episodes if we actually have sample episodes to add
        if !sampleEpisodes.isEmpty {
            episodeViewModel.addEpisodes(sampleEpisodes)
        }
    }
    
    private func generateSampleEpisodeTitle(for podcast: Podcast, episodeNumber: Int) -> String {
        let templates = [
            "Episode \(episodeNumber): ",
            "#\(episodeNumber) - ",
            "Ep. \(episodeNumber): ",
            ""
        ]
        
        let topics = [
            "Understanding the Basics",
            "Advanced Techniques and Tips",
            "Behind the Scenes",
            "Q&A Session",
            "Special Guest Interview",
            "Deep Dive Analysis",
            "Getting Started Guide",
            "Expert Insights",
            "Case Study Review",
            "Future Trends and Predictions"
        ]
        
        let template = templates.randomElement() ?? ""
        let topic = topics.randomElement() ?? "Episode Topic"
        
        return template + topic
    }
    
    private func generateSampleEpisodeDescription(for podcast: Podcast, episodeNumber: Int) -> String {
        let descriptions = [
            "In this episode, we explore the fundamental concepts and provide actionable insights that you can apply immediately.",
            "Join us for an in-depth discussion covering the latest trends, expert opinions, and practical advice.",
            "We dive deep into the subject matter, sharing real-world examples and lessons learned from experience.",
            "This episode features expert analysis, case studies, and practical tips to help you succeed.",
            "Discover the strategies and techniques that industry leaders use to achieve outstanding results.",
            "We break down complex topics into easy-to-understand concepts with practical applications.",
            "Learn from the best as we share insights, strategies, and actionable advice in this comprehensive episode.",
            "This episode covers everything you need to know, from basic principles to advanced techniques.",
        ]
        
        return descriptions.randomElement() ?? "Episode description"
    }
    
    private func addSampleDataForTesting() {
        let samplePodcasts = [
            // Real גיקונומי podcast
            Podcast(
                title: "גיקונומי",
                author: "ראם שרמן ודורון ניר",
                description: "שיחות לא קצרות, לא ערוכות ולא מצונזרות על שלל נושאים עם אנשים שמבינים ומנחה אחד שאוהב לשאול שאלות.",
                feedURL: URL(string: "https://geekonomy.podzone.net/rss")!,
                artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts113/v4/7a/5c/7b/7a5c7bf4-1a5e-8a9f-96c5-c5c89bb4a7b7/mza_5909946798084675406.jpg/600x600bb.jpg"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
            ),
            Podcast(
                title: "Tech Talk Daily",
                author: "Tech Network",
                description: "Daily discussions about the latest technology trends and innovations.",
                feedURL: URL(string: "https://example.com/tech-talk.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-tech/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()) // Yesterday
            ),
            Podcast(
                title: "Design Matters",
                author: "Design Studio",
                description: "Exploring the world of design through interviews with leading designers.",
                feedURL: URL(string: "https://example.com/design-matters.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-design/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) // 1 week ago
            ),
            Podcast(
                title: "History Uncovered",
                author: "History Channel",
                description: "Discovering untold stories from our past.",
                feedURL: URL(string: "https://example.com/history.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-history/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()) // 3 days ago
            ),
            Podcast(
                title: "Startup Stories",
                author: "Business Weekly",
                description: "Inspiring stories from successful entrepreneurs.",
                feedURL: URL(string: "https://example.com/startup.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-startup/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) // 2 hours ago (most recent)
            ),
            Podcast(
                title: "Science Explorer",
                author: "Science Network",
                description: "Making complex scientific concepts accessible to everyone.",
                feedURL: URL(string: "https://example.com/science.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-science/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -14, to: Date()) // 2 weeks ago
            ),
            Podcast(
                title: "Music & Culture",
                author: "Cultural Media",
                description: "The intersection of music and culture around the world.",
                feedURL: URL(string: "https://example.com/music.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-music/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()) // 5 days ago
            ),
            Podcast(
                title: "Mindful Living",
                author: "Wellness Group",
                description: "Tips and techniques for living a more mindful life.",
                feedURL: URL(string: "https://example.com/mindful.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-mindful/400/400"),
                lastEpisodeDate: nil // No episodes yet
            ),
            Podcast(
                title: "Sports Central",
                author: "Sports Network",
                description: "Your daily dose of sports news and analysis.",
                feedURL: URL(string: "https://example.com/sports.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-sports/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()) // 2 days ago
            ),
            Podcast(
                title: "Comedy Hour",
                author: "Laugh Factory",
                description: "The best comedy content to brighten your day.",
                feedURL: URL(string: "https://example.com/comedy.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/podcast-comedy/400/400"),
                lastEpisodeDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()) // 10 days ago
            )
        ]
        
        subscribedPodcasts = samplePodcasts
        PodcastService.shared.savePodcasts(samplePodcasts)
        
        // Also add a sample current episode for testing the mini player
        addSampleCurrentEpisode()
    }
    
    private func addSampleCurrentEpisode() {
        let sampleEpisode = Episode(
            id: UUID(),
            title: "Tech Talk Daily | The Future of AI in Technology",
            artworkURL: nil, // Use podcast artwork instead of episode-specific artwork
            audioURL: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"),
            description: "An in-depth discussion about how artificial intelligence is shaping the future of technology and our daily lives.",
            played: false,
            podcastID: UUID(),
            publishedDate: Date(),
            localFileURL: nil,
            playbackPosition: 120 // 2 minutes in
        )
        
        // Load the sample episode into the audio player for testing the mini player
        AudioPlayerService.shared.loadEpisode(sampleEpisode)
    }
    
    private func deletePodcast(_ podcast: Podcast) {
        // Record this operation for undo
        ShakeUndoManager.shared.recordOperation(
            .subscriptionRemoved(podcast: podcast),
            description: "Unsubscribed from \"\(podcast.title)\""
        )
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            subscribedPodcasts.removeAll { $0.id == podcast.id }
        }
        
        // Save the updated list
        PodcastService.shared.savePodcasts(subscribedPodcasts)
        
        // Also remove from queue if any episodes from this podcast are queued
        let queueViewModel = QueueViewModel.shared
        let episodesToRemove = queueViewModel.queue.filter { $0.podcastID == podcast.id }
        if !episodesToRemove.isEmpty {
            let idsToRemove = Set(episodesToRemove.map { $0.id })
            queueViewModel.removeEpisodes(withIDs: idsToRemove)
        }
    }
    
    private func fixPodcastArtwork() {
        var podcasts = PodcastService.shared.loadPodcasts()
        var needsUpdate = false
        
        for i in 0..<podcasts.count {
            let podcast = podcasts[i]
            
            // Check if this is a fake sample podcast (example.com or picsum.photos URLs)
            let feedURLString = podcast.feedURL.absoluteString
            let isFakePodcast = feedURLString.contains("example.com") || 
                               podcast.artworkURL?.absoluteString.contains("picsum.photos") == true
            
            if isFakePodcast {
                // Remove invalid artwork URL for sample podcasts
                // This will make them use the clean fallback design
                print("🎨 Removing invalid artwork for sample podcast '\(podcast.title)'")
                podcasts[i].artworkURL = nil
                needsUpdate = true
            } else {
                // For real podcasts, refresh from RSS (do this in background)
                print("🎨 Will refresh real podcast '\(podcast.title)' from RSS")
                refreshRealPodcastArtwork(podcast)
            }
        }
        
        if needsUpdate {
            PodcastService.shared.savePodcasts(podcasts)
            DispatchQueue.main.async {
                self.loadSubscribedPodcasts()
            }
        }
    }
    
    private func refreshRealPodcastArtwork(_ podcast: Podcast) {
        // Only refresh if this is a real RSS feed (not example.com)
        guard !podcast.feedURL.absoluteString.contains("example.com") else { return }
        
        URLSession.shared.dataTask(with: podcast.feedURL) { data, response, error in
            guard let data = data, error == nil else { return }
            
            let parser = RSSParser()
            _ = parser.parseRSS(data: data, podcastID: podcast.id)
            
            if let artworkURLString = parser.getPodcastArtworkURL(),
               let artworkURL = URL(string: artworkURLString) {
                
                var podcasts = PodcastService.shared.loadPodcasts()
                if let index = podcasts.firstIndex(where: { $0.id == podcast.id }) {
                    podcasts[index].artworkURL = artworkURL
                    PodcastService.shared.savePodcasts(podcasts)
                    
                    DispatchQueue.main.async {
                        self.loadSubscribedPodcasts()
                    }
                }
            }
        }.resume()
    }
    
    private func setupEpisodesUpdatedObserver() {
        // Start listening for episode updates
        episodesUpdatedObserver = NotificationCenter.default.addObserver(
            forName: .episodesUpdated,
            object: nil,
            queue: .main
        ) { _ in
            // Refresh podcast data and cache when episodes are updated
            loadSubscribedPodcasts()
            
            // Update cache with new episode data
            if isCacheReady {
                updateCachedFilteredPodcastsAsync()
                updateCachedAllEpisodesAsync()
            }
        }
    }
}

// MARK: - Search Bar Component
struct SearchBarView: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Subscribed Shows Grid
struct SubscribedShowsGridView: View {
    let podcasts: [Podcast]
    let searchText: String
    let isEditMode: Bool
    let onDelete: (Podcast) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscribed Shows")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if !podcasts.isEmpty {
                        Text("Sorted by latest update")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Grid Content
            if podcasts.isEmpty {
                EmptySubscriptionsView(hasSearchText: !searchText.isEmpty)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(podcasts) { podcast in
                        ZStack(alignment: .topTrailing) {
                            // Main podcast item
                            NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                                PodcastGridItemView(podcast: podcast, isEditMode: isEditMode)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditMode) // Disable navigation when in edit mode
                            
                            // Delete button overlay (only shown in edit mode)
                            if isEditMode {
                                Button(action: {
                                    onDelete(podcast)
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 24, height: 24)
                                        
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .offset(x: 8, y: -8)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isEditMode)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Podcast Grid Item
struct PodcastGridItemView: View {
    let podcast: Podcast
    let isEditMode: Bool
    @ObservedObject private var episodeCacheService = EpisodeCacheService.shared
    
    private var hasCachedEpisodes: Bool {
        episodeCacheService.hasFreshCache(for: podcast.id)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let artworkURL = podcast.artworkURL {
                    CachedAsyncImagePhase(url: artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_):
                            // Clean fallback for failed loads
                            podcastFallbackView(for: podcast)
                        case .empty:
                            // Loading state
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                )
                        }
                    }
                } else {
                    // No artwork URL - show clean fallback
                    podcastFallbackView(for: podcast)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(isEditMode ? 0.9 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isEditMode)
            
            Text(podcast.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)
                .opacity(isEditMode ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isEditMode)
        }
    }
    
    private func podcastFallbackView(for podcast: Podcast) -> some View {
        // Generate a consistent color based on podcast title
        let titleHash = abs(podcast.title.hashValue)
        
        // Define color pairs separately to help the compiler
        let purple = (Color.purple, Color.purple.opacity(0.3))
        let blue = (Color.blue, Color.blue.opacity(0.3))
        let green = (Color.green, Color.green.opacity(0.3))
        let orange = (Color.orange, Color.orange.opacity(0.3))
        let red = (Color.red, Color.red.opacity(0.3))
        let pink = (Color.pink, Color.pink.opacity(0.3))
        let teal = (Color.teal, Color.teal.opacity(0.3))
        let indigo = (Color.indigo, Color.indigo.opacity(0.3))
        
        let colors = [purple, blue, green, orange, red, pink, teal, indigo]
        let colorPair = colors[titleHash % colors.count]
        
        return RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(
                colors: [colorPair.0, colorPair.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Empty State
struct EmptySubscriptionsView: View {
    let hasSearchText: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearchText ? "magnifyingglass" : "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(hasSearchText ? "No Results" : "No Subscriptions")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(hasSearchText ? "Try a different search term" : "Your subscribed podcasts will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Episodes List View
struct EpisodesListView: View {
    let episodes: [Episode]
    let searchText: String
    let getPodcast: (Episode) -> Podcast?
    
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @ObservedObject private var queueViewModel = QueueViewModel.shared
    @ObservedObject private var episodeViewModel = EpisodeViewModel.shared
    @ObservedObject private var updateService = EpisodeUpdateService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Episodes")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)

                    if !episodes.isEmpty {
                        HStack(spacing: 4) {
                            Text("Sorted by upload date")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if updateService.lastUpdateTime != nil {
                                Text("• Updated \(updateService.lastUpdateTimeString())")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            // Episodes List
            if episodes.isEmpty {
                EmptyEpisodesView(hasSearchText: !searchText.isEmpty)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(episodes) { episode in
                        if let podcast = getPodcast(episode) {
                            EpisodeLibraryRowView(
                                episode: episode,
                                podcast: podcast,
                                isCurrentlyPlaying: audioPlayer.currentEpisode?.id == episode.id,
                                onTap: {
                                    // Show episode detail instead of playing
                                },
                                onAddToQueue: {
                                    queueViewModel.addToQueue(episode)
                                    FeedbackManager.shared.addedToQueue()
                                },
                                onMarkAsPlayed: { played in
                                    episodeViewModel.markEpisodeAsPlayed(episode, played: played)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .id(episode.id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Episode Library Row
struct EpisodeLibraryRowView: View {
    let episode: Episode
    let podcast: Podcast
    let isCurrentlyPlaying: Bool
    let onTap: () -> Void
    let onAddToQueue: () -> Void
    let onMarkAsPlayed: (Bool) -> Void
    
    @State private var showingEpisodeDetail = false
    @ObservedObject private var queueViewModel = QueueViewModel.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Episode artwork - tap to play
                CachedAsyncImagePhase(url: episode.artworkURL ?? podcast.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_), .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .overlay(
                                Image(systemName: "waveform.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .blur(radius: episode.played ? 2 : 0)
                .id("\(episode.id.uuidString)_\(episode.artworkURL?.absoluteString ?? podcast.artworkURL?.absoluteString ?? "")")
                .onTapGesture {
                    // Play episode when artwork is tapped
                    queueViewModel.playEpisodeFromLibrary(episode)
                }
                
                // Episode info - tap to show details
                VStack(alignment: .leading, spacing: 4) {
                    // Episode title
                    Text(episode.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(episode.played ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Podcast title
                    Text(podcast.title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Episode metadata
                    HStack(spacing: 8) {
                        // Publication date
                        if let date = episode.publishedDate {
                            Text(relativeDateString(for: date))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        // Progress and status indicators
                        if episode.playbackPosition > 0 && !episode.played {
                            // Show remaining time for partially played episodes
                            if episode.episodeDuration > 0 {
                                let remainingTime = episode.episodeDuration - episode.playbackPosition
                                Text("\(formatRemainingTime(remainingTime)) left")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(3)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                        } else if episode.played {
                            // Show completion status for played episodes
                            if episode.episodeDuration > 0 {
                                let remainingTime = episode.episodeDuration - episode.playbackPosition
                                if remainingTime > 60 { // More than 1 minute left
                                    Text("\(formatRemainingTime(remainingTime)) left")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(3)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                }
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        // Currently playing indicator
                        if isCurrentlyPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        }
                        
                        Spacer()
                    }
                }
                .blur(radius: episode.played ? 1 : 0)
                .onTapGesture {
                    // Show episode detail when main content is tapped
                    showingEpisodeDetail = true
                }
                
                // Action buttons
                VStack(spacing: 8) {
                    // Options menu button
                    Menu {
                        Button(action: onAddToQueue) {
                            Label("Add to Queue", systemImage: "plus.circle")
                        }
                        
                        Button(action: {
                            onMarkAsPlayed(!episode.played)
                        }) {
                            Label(episode.played ? "Mark as Unplayed" : "Mark as Played", 
                                  systemImage: episode.played ? "circle" : "checkmark.circle")
                        }
                        
                        Button(action: {
                            showingEpisodeDetail = true
                        }) {
                            Label("Episode Details", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                }
                .blur(radius: episode.played ? 1 : 0)
            }
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .opacity(episode.played ? 0.6 : 1.0)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: onAddToQueue) {
                    Label("Add to Queue", systemImage: "plus.circle")
                }

                Button(action: {
                    onMarkAsPlayed(!episode.played)
                }) {
                    Label(
                        episode.played ? "Mark as Unplayed" : "Mark as Played",
                        systemImage: episode.played ? "circle" : "checkmark.circle"
                    )
                }
            }
            
            // Separator
            Divider()
                .padding(.leading, 84) // Align with episode info
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingEpisodeDetail) {
            EpisodeDetailView(episode: episode, podcast: podcast)
        }
    }
    
    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatRemainingTime(_ timeInterval: TimeInterval) -> String {
        let totalMinutes = Int(timeInterval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Empty Episodes State
struct EmptyEpisodesView: View {
    let hasSearchText: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearchText ? "magnifyingglass" : "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(hasSearchText ? "No Episodes Found" : "No Episodes")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(hasSearchText ? "Try a different search term" : "Episodes from your subscribed podcasts will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    LibraryView()
} 