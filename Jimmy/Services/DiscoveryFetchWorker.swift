import Foundation
import BackgroundTasks
import UIKit
#if canImport(OSLog)
import OSLog
#endif

/// Background worker that processes discovery data fetch requests
/// Integrates with BGAppRefreshTask for proper iOS background scheduling
@MainActor
class DiscoveryFetchWorker: ObservableObject {
    static let shared = DiscoveryFetchWorker()
    
    // MARK: - Configuration
    
    private struct Config {
        static let backgroundTaskIdentifier = "com.chenkahana.Jimmy.discoveryFetch"
        static let maxConcurrentRequests = 3
        static let requestTimeoutInterval: TimeInterval = 30
        static let maxBackgroundTime: TimeInterval = 25 // Leave 5s buffer for iOS
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastProcessedTime: Date?
    @Published private(set) var processingStats: ProcessingStats = ProcessingStats()
    
    // MARK: - Processing Statistics
    
    struct ProcessingStats: Codable {
        var totalRequests: Int = 0
        var completedRequests: Int = 0
        var failedRequests: Int = 0
        var averageProcessingTime: TimeInterval = 0
        var lastProcessingTime: Date?
        
        var successRate: Double {
            guard totalRequests > 0 else { return 0 }
            return Double(completedRequests) / Double(totalRequests)
        }
        
        mutating func recordSuccess(processingTime: TimeInterval) {
            totalRequests += 1
            completedRequests += 1
            updateAverageTime(processingTime)
            lastProcessingTime = Date()
        }
        
        mutating func recordFailure(processingTime: TimeInterval) {
            totalRequests += 1
            failedRequests += 1
            updateAverageTime(processingTime)
            lastProcessingTime = Date()
        }
        
        private mutating func updateAverageTime(_ newTime: TimeInterval) {
            let totalCompleted = completedRequests + failedRequests
            if totalCompleted > 0 {
                averageProcessingTime = (averageProcessingTime * Double(totalCompleted - 1) + newTime) / Double(totalCompleted)
            }
        }
    }
    
    // MARK: - Private Properties
    
    /// Currently processing requests
    private var activeRequests: Set<UUID> = []
    
    /// Services
    private let repository = DiscoveryRepository.shared
    private let discoveryService = DiscoveryService.shared
    private let networkManager = OptimizedNetworkManager.shared
    
    /// Background task management
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTaskStartTime: Date?
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "DiscoveryFetchWorker")
    #endif
    
    // MARK: - Initialization
    
    private init() {
        setupBackgroundTaskHandling()
    }
    
    // MARK: - Public Interface
    
    /// Process a discovery fetch request
    func processRequest(_ request: FetchDiscoveryRequest) async throws -> Bool {
        let startTime = Date()
        
        #if canImport(OSLog)
        logger.info("🔄 Processing discovery request: \(request.requestType.rawValue)")
        #endif
        
        // Mark as active
        activeRequests.insert(request.id)
        defer { activeRequests.remove(request.id) }
        
        do {
            let success = try await executeRequest(request)
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            if success {
                processingStats.recordSuccess(processingTime: processingTime)
                lastProcessedTime = Date()
                
                #if canImport(OSLog)
                logger.info("✅ Discovery request completed successfully in \(String(format: "%.2f", processingTime))s")
                #endif
                
                return true
            } else {
                processingStats.recordFailure(processingTime: processingTime)
                
                #if canImport(OSLog)
                logger.warning("⚠️ Discovery request failed: \(request.requestType.rawValue)")
                #endif
                
                return false
            }
            
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            processingStats.recordFailure(processingTime: processingTime)
            
            #if canImport(OSLog)
            logger.error("❌ Discovery request error: \(error.localizedDescription)")
            #endif
            
            throw error
        }
    }
    
    /// Get current processing status
    func getProcessingStatus() -> (isProcessing: Bool, activeRequests: Int, stats: ProcessingStats) {
        return (
            isProcessing: isProcessing,
            activeRequests: activeRequests.count,
            stats: processingStats
        )
    }
    
    /// Reset processing statistics
    func resetStats() async {
        processingStats = ProcessingStats()
    }
    
    // MARK: - Private Methods
    
    private func executeRequest(_ request: FetchDiscoveryRequest) async throws -> Bool {
        await repository.setLoading(true)
        defer {
            Task {
                await repository.setLoading(false)
            }
        }
        
        switch request.requestType {
        case .trending:
            return await fetchTrendingEpisodes(limit: request.limit ?? 8)
            
        case .featured:
            return await fetchFeaturedPodcasts(limit: request.limit ?? 12)
            
        case .charts:
            return await fetchCharts(limit: request.limit ?? 20)
            
        case .all, .userInitiated, .backgroundRefresh, .silentRefresh:
            return await fetchAllDiscoveryData(request: request)
            
        case .cacheRefresh:
            return await refreshCacheFromRepository()
        }
    }
    
    private func fetchTrendingEpisodes(limit: Int) async -> Bool {
        do {
            let episodes = await discoveryService.fetchTrendingEpisodes(limit: limit)
            await repository.updateTrending(episodes)
            return true
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Failed to fetch trending episodes: \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    private func fetchFeaturedPodcasts(limit: Int) async -> Bool {
        do {
            let podcasts = await discoveryService.fetchFeaturedPodcasts(limit: limit)
            await repository.updateFeatured(podcasts)
            return true
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Failed to fetch featured podcasts: \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    private func fetchCharts(limit: Int) async -> Bool {
        do {
            let charts = await discoveryService.fetchTopCharts(limit: limit)
            await repository.updateCharts(charts)
            return true
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Failed to fetch charts: \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    private func fetchAllDiscoveryData(request: FetchDiscoveryRequest) async -> Bool {
        let trendingLimit = request.limit ?? 8
        let featuredLimit = request.limit ?? 12
        let chartsLimit = request.limit ?? 20
        
        // Run all requests in parallel for maximum efficiency
        async let trendingTask = discoveryService.fetchTrendingEpisodes(limit: trendingLimit)
        async let featuredTask = discoveryService.fetchFeaturedPodcasts(limit: featuredLimit)
        async let chartsTask = discoveryService.fetchTopCharts(limit: chartsLimit)
        
        let (trending, featured, charts) = await (trendingTask, featuredTask, chartsTask)
        
        // Batch update for atomic operation
        await repository.batchUpdate(trending: trending, featured: featured, charts: charts)
        
        let hasData = !trending.isEmpty || !featured.isEmpty || !charts.isEmpty
        
        #if canImport(OSLog)
        logger.info("📊 Fetched all discovery data - Trending: \(trending.count), Featured: \(featured.count), Charts: \(charts.count)")
        #endif
        
        return hasData
    }
    
    private func refreshCacheFromRepository() async -> Bool {
        // This is a no-op for discovery data since we don't have a separate cache layer
        // The repository itself handles caching
        return true
    }
    
    // MARK: - Background Task Management
    
    private func setupBackgroundTaskHandling() {
        // Register background task handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Config.backgroundTaskIdentifier, using: nil) { [weak self] task in
            self?.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
    }
    
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        #if canImport(OSLog)
        logger.info("🔄 Starting background discovery refresh")
        #endif
        
        backgroundTaskStartTime = Date()
        
        // Set expiration handler
        task.expirationHandler = { [weak self] in
            #if canImport(OSLog)
            self?.logger.warning("⏰ Background discovery task expired")
            #endif
            task.setTaskCompleted(success: false)
        }
        
        // Process background refresh request
        Task {
            let request = FetchDiscoveryRequest.backgroundRefresh()
            
            do {
                let success = try await self.processRequest(request)
                
                #if canImport(OSLog)
                self.logger.info("✅ Background discovery refresh completed: \(success)")
                #endif
                
                task.setTaskCompleted(success: success)
                
                // Schedule next background refresh
                self.scheduleBackgroundRefresh()
                
            } catch {
                #if canImport(OSLog)
                self.logger.error("❌ Background discovery refresh failed: \(error.localizedDescription)")
                #endif
                
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    /// Schedule background refresh task
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Config.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            
            #if canImport(OSLog)
            logger.info("✅ Scheduled background discovery refresh")
            #endif
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Failed to schedule background discovery refresh: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Start background task for long-running operations
    private func beginBackgroundTask() {
        endBackgroundTask() // End any existing task
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "DiscoveryFetch") { [weak self] in
            self?.endBackgroundTask()
        }
        
        backgroundTaskStartTime = Date()
    }
    
    /// End background task
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            backgroundTaskStartTime = nil
        }
    }
    
    /// Check if background task is running too long
    private func isBackgroundTaskExpiring() -> Bool {
        guard let startTime = backgroundTaskStartTime else { return false }
        return Date().timeIntervalSince(startTime) > Config.maxBackgroundTime
    }
} 