import Foundation
import OSLog
import BackgroundTasks

/// High-performance podcast service with background processing and intelligent caching
class OptimizedPodcastService {
    static let shared = OptimizedPodcastService()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "optimized-podcast")
    
    // MARK: - Configuration
    private struct Config {
        static let maxConcurrentFetches = 4
        static let batchSize = 10
        static let backgroundProcessingInterval: TimeInterval = 5 * 60 // 5 minutes
        static let prefetchThreshold = 3 // Prefetch when user has 3+ podcasts
    }
    
    // MARK: - Properties
    private(set) var hasAttemptedLoad: Bool = false
    private(set) var isBackgroundProcessing: Bool = false
    
    private let podcastsKey = "podcastsKey"
    private let backgroundQueue = DispatchQueue(label: "optimized-podcast-service", qos: .utility, attributes: .concurrent)
    private let processingQueue = DispatchQueue(label: "podcast-processing", qos: .userInitiated)
    private let semaphore = DispatchSemaphore(value: Config.maxConcurrentFetches)
    
    // Services
    private let optimizedNetworkManager = OptimizedNetworkManager.shared
    private let episodeCacheService = EpisodeCacheService.shared
    private let originalPodcastService = PodcastService.shared
    
    // Background processing
    private var backgroundTimer: Timer?
    private var prefetchTimer: Timer?
    
    // Performance tracking - thread-safe
    private let fetchStartTimesQueue = DispatchQueue(label: "fetch-start-times", attributes: .concurrent)
    private var _fetchStartTimes: [String: Date] = [:]
    
    private init() {
        setupBackgroundProcessing()
        setupPrefetching()
    }
    
    deinit {
        backgroundTimer?.invalidate()
        prefetchTimer?.invalidate()
    }
    
    // MARK: - Public Interface
    
    /// Load podcasts with immediate return of cached data
    func loadPodcasts() -> [Podcast] {
        hasAttemptedLoad = true
        return originalPodcastService.loadPodcasts()
    }
    
    /// Load podcasts asynchronously with background optimization
    func loadPodcastsAsync(completion: @escaping ([Podcast]) -> Void) {
        hasAttemptedLoad = true
        
        // Return cached data immediately
        let cachedPodcasts = originalPodcastService.loadPodcasts()
        completion(cachedPodcasts)
        
        // Start background prefetching if we have podcasts
        if cachedPodcasts.count >= Config.prefetchThreshold {
            startBackgroundPrefetching(for: cachedPodcasts)
        }
    }
    
    /// Fetch episodes with intelligent caching and background processing
    func fetchEpisodes(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        let startTime = Date()
        fetchStartTimesQueue.async(flags: .barrier) { [weak self] in
            self?._fetchStartTimes[podcast.id.uuidString] = startTime
        }
        
        logger.info("🚀 Starting optimized fetch for: \(podcast.title)")
        
        // Check cache first
        episodeCacheService.getCachedEpisodes(for: podcast.id) { [weak self] cachedEpisodes in
            guard let self = self else { 
                completion([])
                return 
            }
            
            if let episodes = cachedEpisodes {
                self.logger.info("💾 Cache hit for \(podcast.title): \(episodes.count) episodes")
                completion(episodes)
                
                // Still fetch in background to update cache
                self.backgroundFetchEpisodes(for: podcast)
                return
            }
            
            // No cache - fetch immediately
            self.performOptimizedFetch(for: podcast, completion: completion)
        }
    }
    
    /// Batch fetch episodes for multiple podcasts
    func batchFetchEpisodes(for podcasts: [Podcast], completion: @escaping ([UUID: [Episode]]) -> Void) {
        guard !podcasts.isEmpty else {
            completion([:])
            return
        }
        
        logger.info("📦 Starting batch fetch for \(podcasts.count) podcasts")
        
        let dispatchGroup = DispatchGroup()
        var results: [UUID: [Episode]] = [:]
        let resultsQueue = DispatchQueue(label: "batch-results", attributes: .concurrent)
        
        // Process in batches to avoid overwhelming the system
        let batches = podcasts.chunked(into: Config.batchSize)
        
        for batch in batches {
            for podcast in batch {
                dispatchGroup.enter()
                
                fetchEpisodes(for: podcast) { episodes in
                    resultsQueue.async(flags: .barrier) {
                        results[podcast.id] = episodes
                        dispatchGroup.leave()
                    }
                }
            }
            
            // Small delay between batches - use Task.sleep for non-blocking delay
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.logger.info("✅ Batch fetch completed: \(results.count) podcasts processed")
            completion(results)
        }
    }
    
    /// Start background processing for all subscribed podcasts
    func startBackgroundProcessing() {
        guard !isBackgroundProcessing else { return }
        
        isBackgroundProcessing = true
        logger.info("🔄 Starting background processing")
        
        backgroundQueue.async { [weak self] in
            self?.performBackgroundProcessing()
        }
    }
    
    /// Prefetch RSS feeds for better performance
    func prefetchPodcastFeeds(_ podcasts: [Podcast]) {
        let feedURLs = podcasts.map { $0.feedURL }
        optimizedNetworkManager.prefetchRSSFeeds(urls: feedURLs)
        logger.info("🔮 Prefetching \(feedURLs.count) RSS feeds")
    }
    
    /// Get performance statistics
    func getPerformanceStats() -> (cacheStats: (count: Int, memoryUsage: Int), avgFetchTime: TimeInterval) {
        let cacheStats = optimizedNetworkManager.getCacheStats()
        
        let avgFetchTime: TimeInterval = fetchStartTimesQueue.sync {
            if !_fetchStartTimes.isEmpty {
                let totalTime = _fetchStartTimes.values.reduce(0) { total, startTime in
                    total + Date().timeIntervalSince(startTime)
                }
                return totalTime / Double(_fetchStartTimes.count)
            } else {
                return 0
            }
        }
        
        return (cacheStats: cacheStats, avgFetchTime: avgFetchTime)
    }
    
    // MARK: - Private Methods
    
    private func performOptimizedFetch(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Acquire semaphore to limit concurrent fetches
            self.semaphore.wait()
            
            self.optimizedNetworkManager.fetchRSSFeed(url: podcast.feedURL) { [weak self] result in
                defer { self?.semaphore.signal() }
                
                guard let self = self else { 
                    Task { @MainActor in completion([]) }
                    return 
                }
                
                switch result {
                case .failure(let error):
                    self.logger.error("❌ Fetch failed for \(podcast.title): \(error.localizedDescription)")
                    Task { @MainActor in completion([]) }
                    
                case .success(let data):
                    self.processingQueue.async {
                        let episodes = self.parseAndCacheEpisodes(data: data, podcast: podcast)
                        
                        // Track performance
                        self.fetchStartTimesQueue.async(flags: .barrier) { [weak self] in
                            guard let self = self else { return }
                            if let startTime = self._fetchStartTimes[podcast.id.uuidString] {
                                let fetchTime = Date().timeIntervalSince(startTime)
                                self.logger.info("⏱️ Fetch completed for \(podcast.title) in \(String(format: "%.2f", fetchTime))s")
                                self._fetchStartTimes.removeValue(forKey: podcast.id.uuidString)
                            }
                        }
                        
                        Task { @MainActor in
                            completion(episodes)
                        }
                    }
                }
            }
        }
    }
    
    private func backgroundFetchEpisodes(for podcast: Podcast) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.optimizedNetworkManager.fetchRSSFeed(url: podcast.feedURL) { result in
                if case .success(let data) = result {
                    self.processingQueue.async {
                        _ = self.parseAndCacheEpisodes(data: data, podcast: podcast)
                        self.logger.info("🔄 Background update completed for \(podcast.title)")
                    }
                }
            }
        }
    }
    
    private func parseAndCacheEpisodes(data: Data, podcast: Podcast) -> [Episode] {
        let parser = RSSParser()
        let episodes = parser.parseRSS(data: data, podcastID: podcast.id)
        
        // Update cache
        episodeCacheService.updateCache(episodes, for: podcast.id)
        
        // Update podcast metadata if needed
        updatePodcastMetadataIfNeeded(parser: parser, podcast: podcast)
        
        return episodes
    }
    
    private func updatePodcastMetadataIfNeeded(parser: RSSParser, podcast: Podcast) {
        var needsUpdate = false
        var updatedPodcast = podcast
        
        // Check artwork
        if let artworkURLString = parser.getPodcastArtworkURL(),
           let artworkURL = URL(string: artworkURLString),
           podcast.artworkURL != artworkURL {
            updatedPodcast.artworkURL = artworkURL
            needsUpdate = true
        }
        
        // Check title
        if let newTitle = parser.getPodcastTitle(), newTitle != podcast.title {
            updatedPodcast.title = newTitle
            needsUpdate = true
        }
        
        if needsUpdate {
            // Update in background
            backgroundQueue.async { [weak self] in
                self?.updatePodcastInStorage(updatedPodcast)
            }
        }
    }
    
    private func updatePodcastInStorage(_ updatedPodcast: Podcast) {
        var podcasts = originalPodcastService.loadPodcasts()
        if let index = podcasts.firstIndex(where: { $0.id == updatedPodcast.id }) {
            podcasts[index] = updatedPodcast
            originalPodcastService.savePodcasts(podcasts)
        }
    }
    
    private func setupBackgroundProcessing() {
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: Config.backgroundProcessingInterval, repeats: true) { [weak self] _ in
            self?.performBackgroundProcessing()
        }
    }
    
    private func setupPrefetching() {
        prefetchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.performPrefetching()
        }
    }
    
    private func performBackgroundProcessing() {
        let podcasts = loadPodcasts()
        guard podcasts.count >= Config.prefetchThreshold else { return }
        
        logger.info("🔄 Performing background processing for \(podcasts.count) podcasts")
        
        // Process podcasts that haven't been updated recently
        let staleThreshold = Date().addingTimeInterval(-30 * 60) // 30 minutes
        let stalePodcasts = podcasts.filter { podcast in
            guard let lastEpisodeDate = podcast.lastEpisodeDate else { return true }
            return lastEpisodeDate < staleThreshold
        }
        
        if !stalePodcasts.isEmpty {
            batchFetchEpisodes(for: stalePodcasts) { _ in
                self.logger.info("🔄 Background processing completed")
                self.isBackgroundProcessing = false
            }
        } else {
            self.isBackgroundProcessing = false
        }
    }
    
    private func performPrefetching() {
        let podcasts = loadPodcasts()
        guard !podcasts.isEmpty else { return }
        
        // Prefetch feeds for better performance
        prefetchPodcastFeeds(podcasts)
    }
    
    private func startBackgroundPrefetching(for podcasts: [Podcast]) {
        backgroundQueue.async { [weak self] in
            self?.prefetchPodcastFeeds(podcasts)
        }
    }
}

 