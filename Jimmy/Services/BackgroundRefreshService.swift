import Foundation
import BackgroundTasks
import OSLog

/// Background refresh service following CHAT_HELP.md specification
/// Implements BGAppRefreshTask adapter for podcast updates
final class BackgroundRefreshService {
    static let shared = BackgroundRefreshService()
    
    // MARK: - Configuration
    private struct Config {
        static let backgroundTaskIdentifier = "com.jimmy.podcast.refresh"
        static let refreshInterval: TimeInterval = 3600 // 1 hour
        static let maxBackgroundTime: TimeInterval = 30 // 30 seconds
    }
    
    // MARK: - Properties
    private let fetchWorker = FetchWorker.shared
    private let podcastStore = PodcastStore.shared
    private let podcastService = OptimizedPodcastService.shared
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "BackgroundRefresh")
    #endif
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Register background task handler
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Config.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
        
        #if canImport(OSLog)
        logger.info("✅ Registered background task: \(Config.backgroundTaskIdentifier)")
        #endif
    }
    
    /// Schedule next background refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Config.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Config.refreshInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            
            #if canImport(OSLog)
            logger.info("📅 Scheduled background refresh for \(request.earliestBeginDate?.formatted() ?? "unknown")")
            #endif
            
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Failed to schedule background refresh: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Cancel scheduled background refresh
    func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Config.backgroundTaskIdentifier)
        
        #if canImport(OSLog)
        logger.info("🚫 Cancelled background refresh")
        #endif
    }
    
    // MARK: - Background Task Handling
    
    /// Handle background refresh task
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        #if canImport(OSLog)
        logger.info("🌙 Starting background refresh task")
        #endif
        
        // Schedule next refresh immediately
        scheduleBackgroundRefresh()
        
        // Create background task with timeout
        let backgroundTask = Task {
            await performBackgroundRefresh()
        }
        
        // Set expiration handler
        task.expirationHandler = {
            #if canImport(OSLog)
            self.logger.warning("⏰ Background task expired, cancelling...")
            #endif
            backgroundTask.cancel()
            task.setTaskCompleted(success: false)
        }
        
        // Execute background refresh
        Task {
            let success = await performBackgroundRefreshWithTimeout()
            task.setTaskCompleted(success: success)
            
            #if canImport(OSLog)
            self.logger.info("✅ Background refresh completed: \(success ? "success" : "failed")")
            #endif
        }
    }
    
    /// Perform background refresh with timeout
    private func performBackgroundRefreshWithTimeout() async -> Bool {
        let startTime = Date()
        
        do {
            // Use withTimeout to respect background time limits
            return try await withTimeout(Config.maxBackgroundTime) { [self] in
                await self.performBackgroundRefresh()
                return true
            }
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            
            #if canImport(OSLog)
            logger.error("❌ Background refresh failed after \(String(format: "%.1f", duration))s: \(error.localizedDescription)")
            #endif
            
            return false
        }
    }
    
    /// Core background refresh logic
    private func performBackgroundRefresh() async {
        #if canImport(OSLog)
        logger.info("🔄 Performing background podcast refresh")
        #endif
        
        let startTime = Date()
        
        do {
            // Get subscribed podcasts using the correct method
            let podcasts = await PodcastService.shared.loadPodcastsAsync()
            
            #if canImport(OSLog)
            logger.info("📡 Refreshing \(podcasts.count) podcasts in background")
            #endif
            
            // Batch fetch episodes (optimized for background)
            let episodesByPodcast = await fetchWorker.batchFetchEpisodes(for: podcasts)
            
            // Batch write to store
            await podcastStore.batchWrite(episodesByPodcast)
            
            let duration = Date().timeIntervalSince(startTime)
            let totalEpisodes = episodesByPodcast.values.reduce(0) { $0 + $1.count }
            
            #if canImport(OSLog)
            logger.info("✅ Background refresh completed: \(totalEpisodes) episodes in \(String(format: "%.2f", duration))s")
            #endif
            
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Background refresh error: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Utility Methods
    
    /// Check if background refresh is available
    func isBackgroundRefreshAvailable() -> Bool {
        // BGTaskScheduler doesn't have backgroundRefreshStatus property
        // Return true for now - this would need to be implemented differently
        return true
    }
    
    /// Get background refresh status description
    func getBackgroundRefreshStatusDescription() -> String {
        // Since BGTaskScheduler doesn't expose backgroundRefreshStatus,
        // we'll return a generic status
        return "Background refresh configured"
    }
}

// MARK: - Timeout Utility

private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation
        group.addTask {
            try await operation()
        }
        
        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TimeoutError()
        }
        
        // Return first completed result
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Timeout Error

private struct TimeoutError: Error {
    let localizedDescription = "Operation timed out"
} 