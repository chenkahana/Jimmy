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
    private let semaphore = DispatchSemaphore(value: Config.maxConcurrentFetches)
    
    // Services
    private let episodeCacheService = EpisodeCacheService.shared
    private let originalPodcastService = PodcastService.shared
    
    // Background processing
    private var backgroundTimer: Timer?
    
    // Performance tracking - thread-safe
    private let fetchStartTimesQueue = DispatchQueue(label: "fetch-start-times", attributes: .concurrent)
    private var _fetchStartTimes: [String: Date] = [:]
    
    private init() {
        setupBackgroundProcessing()
    }
    
    deinit {
        backgroundTimer?.invalidate()
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
        let cachedPodcasts = originalPodcastService.loadPodcasts()
        completion(cachedPodcasts)
    }
    
    /// Fetch episodes with intelligent caching and background processing
    func fetchEpisodes(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        let startTime = Date()
        fetchStartTimesQueue.async(flags: .barrier) { [weak self] in
            self?._fetchStartTimes[podcast.id.uuidString] = startTime
        }
        
        logger.info("🚀 Starting optimized fetch for: \(podcast.title)")
        
        episodeCacheService.getCachedEpisodes(for: podcast.id) { [weak self] cachedEpisodes in
            guard let self = self else { 
                completion([])
                return 
            }
            
            if let episodes = cachedEpisodes, !episodes.isEmpty {
                self.logger.info("💾 Cache hit for \(podcast.title): \(episodes.count) episodes")
                completion(episodes)
                self.backgroundFetchEpisodes(for: podcast)
                return
            }
            
            self.performOptimizedFetch(for: podcast, completion: completion)
        }
    }
    
    /// Batch fetch episodes for multiple podcasts
    func batchFetchEpisodes(for podcasts: [Podcast], completion: @escaping ([UUID: [Episode]]) -> Void) {
        let task = Task {
            var results: [UUID: [Episode]] = [:]
            
            await withTaskGroup(of: (UUID, [Episode]).self) { group in
                for podcast in podcasts {
                    group.addTask {
                        await (podcast.id, self.fetchEpisodesAsync(for: podcast))
                    }
                }
                
                for await (podcastId, episodes) in group {
                    results[podcastId] = episodes
                }
            }
            
            return results
        }
        
        Task {
            let results = await task.value
            logger.info("✅ Batch fetch completed: \(results.count) podcasts processed")
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
    
    /// Get performance statistics
    func getPerformanceStats(completion: @escaping ((cacheStats: (count: Int, memoryUsage: Int), avgFetchTime: TimeInterval)) -> Void) {
        episodeCacheService.getCacheStats { stats in
            let avgFetchTime: TimeInterval = self.fetchStartTimesQueue.sync {
                if !self._fetchStartTimes.isEmpty {
                    let totalTime = self._fetchStartTimes.values.reduce(0) { total, startTime in
                        total + Date().timeIntervalSince(startTime)
                    }
                    return totalTime / Double(self._fetchStartTimes.count)
                } else {
                    return 0
                }
            }
            
            let cacheStats = (count: stats.totalPodcasts, memoryUsage: Int(stats.totalSizeKB))
            completion((cacheStats: cacheStats, avgFetchTime: avgFetchTime))
        }
    }
    
    // MARK: - Async Public Interface
    
    func fetchEpisodesAsync(for podcast: Podcast) async -> [Episode] {
        return await withCheckedContinuation { continuation in
            fetchEpisodes(for: podcast) { episodes in
                continuation.resume(returning: episodes)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func performOptimizedFetch(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        Task(priority: .userInitiated) {
            let episodes = await fetchAndParseEpisodes(for: podcast)
            
            // Track performance
            self.fetchStartTimesQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                if let startTime = self._fetchStartTimes[podcast.id.uuidString] {
                    let fetchTime = Date().timeIntervalSince(startTime)
                    self.logger.info("⏱️ Fetch completed for \(podcast.title) in \(String(format: "%.2f", fetchTime))s")
                    self._fetchStartTimes.removeValue(forKey: podcast.id.uuidString)
                }
            }
            
            completion(episodes)
        }
    }
    
    private func backgroundFetchEpisodes(for podcast: Podcast) {
        Task(priority: .background) {
            _ = await fetchAndParseEpisodes(for: podcast)
            self.logger.info("🔄 Background update completed for \(podcast.title)")
        }
    }
    
    private func fetchAndParseEpisodes(for podcast: Podcast) async -> [Episode] {
        // Use async-compatible concurrency control
        return await withCheckedContinuation { continuation in
            semaphore.wait()
            
            Task {
                defer { semaphore.signal() }
                
                logger.info("🌐 Fetching and parsing episodes for '\(podcast.title)' with new parser.")
                
                let parser = RSSParser(podcastID: podcast.id)
                do {
                    let (episodes, metadata) = try await parser.parse(from: podcast.feedURL)
                    logger.info("✅ Successfully parsed \(episodes.count) episodes for '\(podcast.title)'.")
                    
                    // Update cache
                    episodeCacheService.updateCache(episodes, for: podcast.id)
                    
                    // Update podcast metadata if needed
                    await updatePodcastMetadataIfNeeded(metadata: metadata, podcast: podcast)
                    
                    continuation.resume(returning: episodes)
                } catch {
                    logger.error("❌ Failed to parse RSS feed for \(podcast.title): \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func updatePodcastMetadataIfNeeded(metadata: PodcastMetadata, podcast: Podcast) async {
        var needsUpdate = false
        var updatedPodcast = podcast
        
        // Check artwork
        if let artworkURL = metadata.artworkURL, podcast.artworkURL != artworkURL {
            updatedPodcast.artworkURL = artworkURL
            needsUpdate = true
        }
        
        // Check title
        if let newTitle = metadata.title, !newTitle.isEmpty, newTitle != podcast.title {
            updatedPodcast.title = newTitle
            needsUpdate = true
        }
        
        if needsUpdate {
            await updatePodcastInStorage(updatedPodcast)
        }
    }
    
    private func updatePodcastInStorage(_ updatedPodcast: Podcast) async {
        var podcasts = await originalPodcastService.loadPodcastsAsync()
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
    
    private func performBackgroundProcessing() {
        let podcasts = loadPodcasts()
        guard podcasts.count >= Config.prefetchThreshold else { return }
        
        logger.info("🔄 Performing background processing for \(podcasts.count) podcasts")
        
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
}

 