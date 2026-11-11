import Foundation
import Network
import Combine
import OSLog

/// Advanced podcast fetching and sorting system
/// Features:
/// - Intelligent circuit breaker with exponential backoff
/// - Multi-tier caching with smart invalidation
/// - Priority-based queue management
/// - Real-time performance monitoring
/// - Error recovery
/// - Memory-efficient streaming parsing
/// - Predictive prefetching
/// - Advanced sorting algorithms
final class PodcastEngine: ObservableObject {
    static let shared = PodcastEngine()
    
    // MARK: - Logging
    private let logger = Logger(subsystem: "Jimmy.Engine", category: "PodcastEngine")
    
    // MARK: - Core Components
    private let cacheEngine: IntelligentCacheEngine  
    private let sortingEngine: PodcastSorter
    private let circuitBreaker: CircuitBreaker
    private let performanceMonitor: RealTimePerformanceMonitor
    private let priorityQueue: PriorityFetchQueue
    
    // MARK: - State Management
    @Published private(set) var engineStatus: EngineStatus = .initializing
    @Published private(set) var performanceMetrics: EnginePerformanceMetrics = EnginePerformanceMetrics()
    
    private let engineQueue = DispatchQueue(label: "PodcastEngine", qos: .userInitiated, attributes: .concurrent)
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.cacheEngine = IntelligentCacheEngine()
        self.sortingEngine = PodcastSorter()
        self.circuitBreaker = CircuitBreaker()
        self.performanceMonitor = RealTimePerformanceMonitor()
        self.priorityQueue = PriorityFetchQueue()
        
        setupEngineMonitoring()
        initializeEngine()
    }
    
    // MARK: - Public API
    
    /// Fetch podcasts with world-class reliability and performance
    func fetchPodcasts(
        priority: FetchPriority = .normal,
        forceRefresh: Bool = false
    ) async throws -> [EnhancedPodcast] {
        let operationID = UUID()
        logger.info("🚀 Starting world-class podcast fetch - Operation: \(operationID)")
        
        return try await performanceMonitor.measure(operation: "fetchPodcasts") {
            // Step 1: Check circuit breaker
            try circuitBreaker.checkState()
            
            // Step 2: Intelligent cache lookup
            if !forceRefresh, let cachedPodcasts = await cacheEngine.getCachedPodcasts() {
                logger.info("⚡ Cache hit - returning \(cachedPodcasts.count) podcasts instantly")
                return cachedPodcasts
            }
            
            // Step 3: Priority-based fetching
            let fetchRequest = FetchRequest(
                id: operationID,
                priority: priority,
                type: .podcastList,
                timestamp: Date()
            )
            
            return try await priorityQueue.execute(request: fetchRequest) {
                try await self.performAdvancedPodcastFetch()
            }
        }
    }
    
    /// Stream podcasts progressively - each podcast appears as it's loaded
    /// This enables true multi-threaded UI updates without waiting for all shows
    func streamPodcasts(
        priority: FetchPriority = .normal,
        forceRefresh: Bool = false,
        progressHandler: @escaping (Podcast, Int) -> Void
    ) async throws {
        let operationID = UUID()
        logger.info("🌊 Starting progressive podcast streaming - Operation: \(operationID)")
        
        try await performanceMonitor.measure(operation: "streamPodcasts") {
            // Step 1: Check circuit breaker
            try circuitBreaker.checkState()
            
            // Step 2: Try cache first for immediate display
            if !forceRefresh, let cachedPodcasts = await cacheEngine.getCachedPodcasts() {
                logger.info("⚡ Streaming from cache - \(cachedPodcasts.count) podcasts")
                
                // Stream cached podcasts immediately with throttling
                await streamCachedPodcasts(cachedPodcasts, progressHandler: progressHandler)
                return
            }
            
            // Step 3: Stream from database progressively
            await streamPodcastsFromDatabase(progressHandler: progressHandler)
        }
    }
    
    /// TRUE non-blocking progressive streaming - NEVER blocks UI thread
    func streamPodcastsNonBlocking(
        priority: FetchPriority = .normal,
        forceRefresh: Bool = false,
        progressHandler: @escaping (Podcast, Int) async -> Void
    ) async {
        let operationID = UUID()
        logger.info("🚀 Starting TRUE non-blocking streaming - Operation: \(operationID)")
        
        // Start streaming in background without blocking
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Step 1: Try cache first for immediate results
            if !forceRefresh, let cachedPodcasts = await self.cacheEngine.getCachedPodcasts() {
                self.logger.info("⚡ Non-blocking cache streaming - \(cachedPodcasts.count) podcasts")
                await self.streamCachedPodcastsNonBlocking(cachedPodcasts, progressHandler: progressHandler)
                return
            }
            
            // Step 2: Stream from database with immediate UI updates
            await self.streamPodcastsFromDatabaseNonBlocking(progressHandler: progressHandler)
        }
    }
    
    /// Fetch episodes for a specific podcast with streaming and caching
    func fetchEpisodes(
        for podcast: EnhancedPodcast,
        priority: FetchPriority = .normal,
        progressHandler: ((Episode, Int) -> Void)? = nil
    ) async throws -> [Episode] {
        let operationID = UUID()
        logger.info("📡 Fetching episodes for '\(podcast.title)' - Operation: \(operationID)")
        
        return try await performanceMonitor.measure(operation: "fetchEpisodes") {
            // Check circuit breaker for this specific feed
            try circuitBreaker.checkFeedState(podcast.feedURL)
            
            // Smart cache check with freshness validation
            if let cachedEpisodes = await cacheEngine.getCachedEpisodes(for: podcast.id),
               await cacheEngine.isFresh(podcast.feedURL) {
                // logger.info("⚡ Fresh cache hit - returning \(cachedEpisodes.count) episodes")
                return cachedEpisodes
            }
            
            // Advanced streaming fetch with memory management
            return try await streamingFetchEpisodes(
                for: podcast,
                operationID: operationID,
                progressHandler: progressHandler
            )
        }
    }
    
    /// Get sorted podcasts with quantum-speed algorithms
    func getSortedPodcasts(
        sortType: SortType = .latestEpisode,
        filterCriteria: FilterCriteria? = nil
    ) async -> [EnhancedPodcast] {
        return await performanceMonitor.measure(operation: "sortPodcasts") {
            await sortingEngine.getSortedPodcasts(
                sortType: sortType,
                filterCriteria: filterCriteria
            )
        }
    }
    
    /// Subscribe to a new podcast with intelligent validation
    func subscribe(to feedURL: URL) async throws -> (EnhancedPodcast, [Episode]) {
        logger.info("🎯 Subscribing to new podcast: \(feedURL)")
        
        return try await performanceMonitor.measure(operation: "subscribe") {
            // Step 1: Validate feed URL with HEAD request
            try await UnifiedNetworkService.shared.validateFeedURL(feedURL)
            
            // Step 2: Fetch and parse with streaming
            let (podcast, episodes) = try await fetchPodcastWithEpisodes(from: feedURL)
            
            // Step 3: Cache immediately for instant access
            await cacheEngine.cachePodcast(podcast, with: episodes)
            
            // Step 4: Update sorting index
            await sortingEngine.addPodcast(podcast)
            
            logger.info("✅ Successfully subscribed to '\(podcast.title)' with \(episodes.count) episodes")
            return (podcast, episodes)
        }
    }
    
    // MARK: - Progressive Streaming Methods
    
    private func streamCachedPodcasts(
        _ cachedPodcasts: [EnhancedPodcast],
        progressHandler: @escaping (Podcast, Int) -> Void
    ) async {
        // Process podcasts in small batches for immediate UI feedback
        let batchSize = 3
        
        for batchStart in stride(from: 0, to: cachedPodcasts.count, by: batchSize) {
            // PERF-04: Check for cancellation at start of each batch
            if Task.isCancelled { return }
            
            let batchEnd = min(batchStart + batchSize, cachedPodcasts.count)
            let batch = Array(cachedPodcasts[batchStart..<batchEnd])
            
            // Process batch concurrently
            await withTaskGroup(of: (Int, Podcast).self) { group in
                for (localIndex, enhancedPodcast) in batch.enumerated() {
                    let globalIndex = batchStart + localIndex
                    group.addTask {
                        // Small delay for UI smoothness
                        try? await Task.sleep(nanoseconds: UInt64(localIndex * 20_000_000)) // 20ms
                        return (globalIndex, enhancedPodcast.basePodcast)
                    }
                }
                
                // Collect and sort results
                var batchResults: [(Int, Podcast)] = []
                for await result in group {
                    batchResults.append(result)
                }
                
                batchResults.sort { $0.0 < $1.0 }
                
                // Update UI with this batch
                for (index, podcast) in batchResults {
                    let count = index + 1
                    await MainActor.run {
                        progressHandler(podcast, count)
                    }
                }
            }
            
            // Small delay between batches
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
    
    /// Stream podcasts from database with progressive loading
    private func streamPodcastsFromDatabase(
        progressHandler: @escaping (Podcast, Int) -> Void
    ) async {
        do {
            // Get database connection
            let dbManager = DatabaseManager.shared
            
            // Use LIMIT and OFFSET for progressive loading from database
            let batchSize = 5
            var offset = 0
            var hasMore = true
            
            while hasMore {
                // PERF-04: Check for cancellation at start of each iteration
                if Task.isCancelled {
                    logger.info("📊 Database streaming cancelled at offset \(offset)")
                    return
                }
                
                // Fetch batch from database
                let podcastBatch = try await dbManager.readAsync { db in
                    try Podcast.limit(batchSize, offset: offset).fetchAll(db)
                }
                
                if podcastBatch.isEmpty {
                    hasMore = false
                    break
                }
                
                // Stream this batch to UI with concurrent processing
                await withTaskGroup(of: (Int, Podcast).self) { group in
                    for (batchIndex, podcast) in podcastBatch.enumerated() {
                        group.addTask {
                            // Small delay for smooth UI updates
                            try? await Task.sleep(nanoseconds: UInt64(batchIndex * 30_000_000)) // 30ms
                            return (batchIndex, podcast)
                        }
                    }
                    
                    // Collect results and update UI in order
                    var batchResults: [(Int, Podcast)] = []
                    for await result in group {
                        batchResults.append(result)
                    }
                    
                    batchResults.sort { $0.0 < $1.0 }
                    
                    // Use local count that's captured by value
                    let startingCount = offset
                    for (index, (_, podcast)) in batchResults.enumerated() {
                        let currentCount = startingCount + index + 1
                        await MainActor.run {
                            progressHandler(podcast, currentCount)
                        }
                    }
                }
                
                offset += batchSize
                
                // Small delay between batches for system breathing room
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            logger.info("📊 Streaming completed - \(offset) podcasts streamed")
            
        } catch {
            logger.error("❌ Database streaming error: \(error.localizedDescription)")
            // Don't rethrow - this function should handle errors gracefully
        }
    }
    
    /// NON-BLOCKING cached podcast streaming - immediate UI updates
    private func streamCachedPodcastsNonBlocking(
        _ cachedPodcasts: [EnhancedPodcast],
        progressHandler: @escaping (Podcast, Int) async -> Void
    ) async {
        var count = 0
        
        // Stream in TINY batches for instant UI responsiveness
        let batchSize = 1 // One podcast at a time for maximum responsiveness
        
        for i in stride(from: 0, to: cachedPodcasts.count, by: batchSize) {
            // PERF-04: Check for cancellation
            if Task.isCancelled { return }
            
            let endIndex = min(i + batchSize, cachedPodcasts.count)
            let batch = Array(cachedPodcasts[i..<endIndex])
            
            // Process each podcast immediately
            for enhancedPodcast in batch {
                count += 1
                // Call progress handler immediately - no delays!
                await progressHandler(enhancedPodcast.basePodcast, count)
                
                // Micro delay for smooth animations only
                try? await Task.sleep(nanoseconds: 5_000_000) // 5ms only
            }
        }
        
        logger.info("⚡ Non-blocking cache streaming completed: \(count) podcasts")
    }
    
    /// NON-BLOCKING database streaming - immediate UI updates
    private func streamPodcastsFromDatabaseNonBlocking(
        progressHandler: @escaping (Podcast, Int) async -> Void
    ) async {
        do {
            // Get database connection
            let dbManager = DatabaseManager.shared
            var podcastCount = 0
            
            // Use TINY batches for maximum UI responsiveness
            let batchSize = 1 // One podcast at a time
            var offset = 0
            var hasMore = true
            
            while hasMore {
                // PERF-04: Check for cancellation
                if Task.isCancelled {
                    logger.info("🚀 Non-blocking streaming cancelled at \(podcastCount) podcasts")
                    return
                }
                
                // Fetch minimal batch from database
                let podcastBatch = try await dbManager.readAsync { db in
                    try Podcast.limit(batchSize, offset: offset).fetchAll(db)
                }
                
                if podcastBatch.isEmpty {
                    hasMore = false
                    break
                }
                
                // Process each podcast immediately
                for podcast in podcastBatch {
                    podcastCount += 1
                    // Call progress handler immediately - no blocking!
                    await progressHandler(podcast, podcastCount)
                    
                    // Micro delay for smooth UI animations
                    try? await Task.sleep(nanoseconds: 3_000_000) // 3ms only
                }
                
                offset += batchSize
                
                // Tiny pause to prevent overwhelming the database
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            
            logger.info("🚀 Non-blocking database streaming completed: \(podcastCount) podcasts")
            
        } catch {
            logger.error("❌ Non-blocking database streaming error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Advanced Internal Methods
    
    private func performAdvancedPodcastFetch() async throws -> [EnhancedPodcast] {
        // Get all subscribed podcast URLs from repository
        let subscriptions = try await DIContainer.shared.subscriptionRepository.fetchSubscriptions(ignoreCache: false)
        
        guard !subscriptions.isEmpty else {
            logger.warning("⚠️ No podcast subscriptions found")
            return []
        }
        
        logger.info("🔄 Fetching \(subscriptions.count) podcasts with advanced algorithms")
        
        // Convert to enhanced podcasts with metadata
        var enhancedPodcasts: [EnhancedPodcast] = []
        
        // Use TaskGroup for concurrent processing with controlled concurrency
        try await withThrowingTaskGroup(of: EnhancedPodcast?.self) { group in
            // Process in smaller batches to control concurrency
            let batchSize = 8
            
            for batchStart in stride(from: 0, to: subscriptions.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, subscriptions.count)
                let batch = Array(subscriptions[batchStart..<batchEnd])
                
                for podcast in batch {
                    group.addTask { [weak self] in
                        return await self?.enhancePodcast(podcast)
                    }
                }
                
                // Collect this batch before starting the next
                for _ in batch {
                    if let enhancedPodcast = try await group.next(), let podcast = enhancedPodcast {
                        enhancedPodcasts.append(podcast)
                    }
                }
            }
        }
        
        // Cache the results
        await cacheEngine.cachePodcasts(enhancedPodcasts)
        
        // Update sorting engine
        await sortingEngine.updatePodcasts(enhancedPodcasts)
        
        logger.info("✅ Successfully fetched and enhanced \(enhancedPodcasts.count) podcasts")
        return enhancedPodcasts
    }
    
    private func streamingFetchEpisodes(
        for podcast: EnhancedPodcast,
        operationID: UUID,
        progressHandler: ((Episode, Int) -> Void)?
    ) async throws -> [Episode] {
        var episodes: [Episode] = []
        var episodeCount = 0
        
        // Use advanced streaming parser with memory management
        let streamingParser = MemoryEfficientStreamingParser(
            feedURL: podcast.feedURL,
            podcastID: podcast.id,
            maxMemoryUsage: 50 * 1024 * 1024 // 50MB limit
        )
        
        do {
            for try await result in streamingParser.streamEpisodes() {
                switch result {
                case .episode(let episode):
                    episodes.append(episode)
                    episodeCount += 1
                    
                    // Call progress handler on main thread with local copy
                    if let progressHandler = progressHandler {
                        let currentCount = episodeCount // Capture local copy
                        await MainActor.run {
                            progressHandler(episode, currentCount)
                        }
                    }
                    
                    // Incremental caching for immediate UI updates
                    await cacheEngine.cacheEpisode(episode, for: podcast.id)
                    
                case .metadata(let metadata):
                    let metadataTitle = metadata.title ?? "Unknown"
                    logger.debug("📊 Received metadata for '\(metadataTitle)'")
                    
                case .error(let error):
                    logger.error("❌ Streaming error: \(error.localizedDescription)")
                    circuitBreaker.recordFailure(for: podcast.feedURL)
                    
                case .completed:
                    // logger.info("🎉 Streaming completed")
                    circuitBreaker.recordSuccess(for: podcast.feedURL)
                }
            }
        } catch {
            logger.error("💥 Critical streaming error: \(error.localizedDescription)")
            circuitBreaker.recordFailure(for: podcast.feedURL)
            throw error
        }
        
        // Final cache update with all episodes
        await cacheEngine.cacheEpisodes(episodes, for: podcast.id)
        
        return episodes
    }
    
    private func enhancePodcast(_ podcast: Podcast) async -> EnhancedPodcast? {
        // CRITICAL FIX: Skip network requests in simulator to prevent hanging
        #if targetEnvironment(simulator)
        // Use cached data only in simulator
        let freshnessScore = calculateFreshnessScore(
            lastEpisodeDate: podcast.lastEpisodeDate,
            lastFetched: podcast.lastFetched
        )
        
        return EnhancedPodcast(
            base: podcast,
            latestEpisodeDate: podcast.lastEpisodeDate,
            freshnessScore: freshnessScore,
            fetchPriority: determineFetchPriority(freshnessScore: freshnessScore),
            lastSuccessfulFetch: podcast.lastFetched ?? Date(),
            errorCount: 0
        )
        #else
        // On device, try network request with timeout
        do {
            // Get latest episode date using fast HEAD request with aggressive timeout
            let latestEpisodeDate = await UnifiedNetworkService.shared.getLatestEpisodeDate(for: podcast.feedURL)
            
            // Calculate freshness score
            let freshnessScore = calculateFreshnessScore(
                lastEpisodeDate: latestEpisodeDate,
                lastFetched: podcast.lastFetched
            )
            
            return EnhancedPodcast(
                base: podcast,
                latestEpisodeDate: latestEpisodeDate,
                freshnessScore: freshnessScore,
                fetchPriority: determineFetchPriority(freshnessScore: freshnessScore),
                lastSuccessfulFetch: Date(),
                errorCount: 0
            )
        } catch {
            logger.warning("⚠️ Failed to enhance podcast '\(podcast.title)': \(error.localizedDescription)")
            
            // Return basic enhanced podcast with error tracking
            return EnhancedPodcast(
                base: podcast,
                latestEpisodeDate: podcast.lastEpisodeDate,
                freshnessScore: 0.0,
                fetchPriority: .low,
                lastSuccessfulFetch: podcast.lastFetched ?? Date.distantPast,
                errorCount: 1
            )
        }
        #endif
    }
    
    private func fetchPodcastWithEpisodes(from feedURL: URL) async throws -> (EnhancedPodcast, [Episode]) {
        // Use unified network service for robust fetching
        let (data, etag, _) = try await UnifiedNetworkService.shared.fetchRSSFeed(
            from: feedURL,
            etag: nil,
            lastModified: nil
        )
        
        // Parse with memory-efficient parser
        let parser = AdvancedRSSParser()
        let (episodes, metadata) = try await parser.parse(
            data: data,
            feedURL: feedURL,
            memoryLimit: 100 * 1024 * 1024 // 100MB limit
        )
        
        // Create enhanced podcast
        let podcastID = DeterministicUUIDGenerator.generatePodcastID(from: feedURL)
        let basePodcast = Podcast(
            id: podcastID,
            title: metadata.title ?? "Unknown Podcast",
            author: metadata.author ?? "Unknown Author",
            description: metadata.description ?? "",
            feedURL: feedURL,
            artworkURL: metadata.artworkURL,
            lastEpisodeDate: episodes.compactMap(\.publishedDate).max(),
            etag: etag,
            lastFetched: Date()
        )
        
        let enhancedPodcast = EnhancedPodcast(
            base: basePodcast,
            latestEpisodeDate: episodes.compactMap(\.publishedDate).max(),
            freshnessScore: 1.0, // New podcast gets max freshness
            fetchPriority: .high,
            lastSuccessfulFetch: Date(),
            errorCount: 0
        )
        
        return (enhancedPodcast, episodes)
    }
    
    // MARK: - Utility Methods
    
    private func calculateFreshnessScore(lastEpisodeDate: Date?, lastFetched: Date?) -> Double {
        guard let lastEpisode = lastEpisodeDate else { return 0.0 }
        
        let now = Date()
        let daysSinceLastEpisode = now.timeIntervalSince(lastEpisode) / (24 * 60 * 60)
        
        // Exponential decay function for freshness
        let freshness = exp(-daysSinceLastEpisode / 30.0) // 30-day half-life
        return max(0.0, min(1.0, freshness))
    }
    
    private func determineFetchPriority(freshnessScore: Double) -> FetchPriority {
        switch freshnessScore {
        case 0.8...1.0: return .critical
        case 0.5...0.8: return .high
        case 0.2...0.5: return .normal
        default: return .low
        }
    }
    
    private func setupEngineMonitoring() {
        // Monitor performance metrics
        performanceMonitor.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                // Convert RealTime metrics to EnginePerformanceMetrics
                self?.performanceMetrics = EnginePerformanceMetrics(
                    averageFetchTime: metrics.averageFetchTime,
                    cacheHitRate: metrics.cacheHitRate,
                    errorRate: metrics.errorRate,
                    throughput: metrics.throughput,
                    memoryUsage: metrics.memoryUsage,
                    networkLatency: metrics.networkLatency,
                    parsingTime: metrics.parsingTime,
                    sortingTime: metrics.sortingTime,
                    totalOperations: metrics.totalOperations,
                    failedOperations: metrics.failedOperations,
                    lastUpdated: metrics.lastUpdated
                )
            }
            .store(in: &self.cancellables)
        
        // Monitor circuit breaker state
        circuitBreaker.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.logger.info("🔧 Circuit breaker state changed: \(String(describing: state))")
            }
            .store(in: &cancellables)
    }
    
    private func initializeEngine() {
        Task {
            await MainActor.run {
                self.engineStatus = .ready
            }
            // World-Class Podcast Engine initialized and ready
        }
    }
}

// MARK: - Enhanced Data Models

struct EnhancedPodcast: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let author: String
    let description: String
    let feedURL: URL
    let artworkURL: URL?
    let latestEpisodeDate: Date?
    let freshnessScore: Double
    let fetchPriority: FetchPriority
    let lastSuccessfulFetch: Date
    let errorCount: Int
    let etag: String?
    let lastFetched: Date?
    
    init(base: Podcast, latestEpisodeDate: Date?, freshnessScore: Double, fetchPriority: FetchPriority, lastSuccessfulFetch: Date, errorCount: Int) {
        self.id = base.id
        self.title = base.title
        self.author = base.author
        self.description = base.description
        self.feedURL = base.feedURL
        self.artworkURL = base.artworkURL
        self.latestEpisodeDate = latestEpisodeDate
        self.freshnessScore = freshnessScore
        self.fetchPriority = fetchPriority
        self.lastSuccessfulFetch = lastSuccessfulFetch
        self.errorCount = errorCount
        self.etag = base.etag
        self.lastFetched = base.lastFetched
    }
    
    // Convert back to base Podcast for compatibility
    var basePodcast: Podcast {
        return Podcast(
            id: id,
            title: title,
            author: author,
            description: description,
            feedURL: feedURL,
            artworkURL: artworkURL,
            lastEpisodeDate: latestEpisodeDate,
            etag: etag,
            lastFetched: lastFetched
        )
    }
}

enum FetchPriority: Int, CaseIterable, Comparable, Codable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    static func < (lhs: FetchPriority, rhs: FetchPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum EngineStatus: Equatable {
    case initializing
    case ready
    case busy
    case error(String)
}

struct EnginePerformanceMetrics {
    var averageFetchTime: TimeInterval = 0
    var cacheHitRate: Double = 0
    var errorRate: Double = 0
    var throughput: Double = 0 // Operations per second
    var memoryUsage: Int64 = 0 // Bytes
    var networkLatency: TimeInterval = 0
    var parsingTime: TimeInterval = 0
    var sortingTime: TimeInterval = 0
    var totalOperations: Int = 0
    var failedOperations: Int = 0
    var lastUpdated: Date = Date()
    var activeOperations: Int = 0
    
    init() {}
    
    init(averageFetchTime: TimeInterval, cacheHitRate: Double, errorRate: Double, throughput: Double, memoryUsage: Int64, networkLatency: TimeInterval, parsingTime: TimeInterval, sortingTime: TimeInterval, totalOperations: Int, failedOperations: Int, lastUpdated: Date) {
        self.averageFetchTime = averageFetchTime
        self.cacheHitRate = cacheHitRate
        self.errorRate = errorRate
        self.throughput = throughput
        self.memoryUsage = memoryUsage
        self.networkLatency = networkLatency
        self.parsingTime = parsingTime
        self.sortingTime = sortingTime
        self.totalOperations = totalOperations
        self.failedOperations = failedOperations
        self.lastUpdated = lastUpdated
        self.activeOperations = 0
    }
}

enum SortType {
    case latestEpisode
    case alphabetical
    case subscriptionDate
    case freshnessScore
    case custom(comparator: (EnhancedPodcast, EnhancedPodcast) -> Bool)
}

struct FilterCriteria {
    let searchText: String?
    let categories: [String]?
    let minFreshnessScore: Double?
    let hasNewEpisodes: Bool?
}

struct FetchRequest {
    let id: UUID
    let priority: FetchPriority
    let type: FetchType
    let timestamp: Date
}

enum FetchType {
    case podcastList
    case episodes(podcastID: UUID)
    case newSubscription(feedURL: URL)
}
