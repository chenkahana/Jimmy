import Foundation
import BackgroundTasks
import os

/// Background refresh service following CHAT_HELP.md specification
/// Implements BGAppRefreshTask adapter for podcast updates
final class BackgroundRefreshService {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "BackgroundRefreshService")
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
        #endif
    }
    
    /// Schedule next background refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Config.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Config.refreshInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            
            #if canImport(OSLog)
            #endif
            
        } catch {
            #if canImport(OSLog)
            #endif
        }
    }
    
    /// Cancel scheduled background refresh
    func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Config.backgroundTaskIdentifier)
        
        #if canImport(OSLog)
        #endif
    }
    
    // MARK: - Background Task Handling
    
    /// Handle background refresh task
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        #if canImport(OSLog)
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
            #endif
            backgroundTask.cancel()
            task.setTaskCompleted(success: false)
        }
        
        // Execute background refresh
        Task {
            let success = await performBackgroundRefreshWithTimeout()
            task.setTaskCompleted(success: success)
            
            #if canImport(OSLog)
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
            #endif
            
            return false
        }
    }
    
    /// Core background refresh logic
    private func performBackgroundRefresh() async {
        let startTime = Date()

        // Get subscribed podcasts, prioritized by staleness (least-recently-fetched first)
        let allPodcasts = await PodcastService.shared.loadPodcastsAsync()
        let podcasts = FetchWorker.prioritizedByStale(allPodcasts)

        // Batch fetch episodes (uses conditional GET with ETags, updates podcast metadata)
        let episodesByPodcast = await fetchWorker.batchFetchEpisodes(for: podcasts)

        // Batch write to store
        await podcastStore.batchWrite(episodesByPodcast)

        // Auto-add new episodes for podcasts with autoAddToQueue enabled
        await autoAddNewEpisodesToQueue(podcasts: podcasts, episodesByPodcast: episodesByPodcast)

        // Save sync payload to iCloud KVS if enabled
        AppDataDocument.saveSyncPayload()

        let duration = Date().timeIntervalSince(startTime)
        let totalEpisodes = episodesByPodcast.values.reduce(0) { $0 + $1.count }
        Self.logger.info("Background refresh completed in \(String(format: "%.1f", duration))s: \(totalEpisodes) episodes")
    }

    /// Auto-add new episodes to queue for podcasts with autoAddToQueue enabled
    @MainActor
    private func autoAddNewEpisodesToQueue(podcasts: [Podcast], episodesByPodcast: [UUID: [Episode]]) async {
        let autoAddPodcasts = podcasts.filter { $0.autoAddToQueue }
        guard !autoAddPodcasts.isEmpty else { return }

        let maxAutoAddPerRefresh = 5
        var addedCount = 0

        for podcast in autoAddPodcasts {
            guard addedCount < maxAutoAddPerRefresh else { break }
            guard let newEpisodes = episodesByPodcast[podcast.id] else { continue }

            // Only add episodes that aren't already in the queue
            for episode in newEpisodes where AppModel.current?.isQueued(episode.id) != true {
                guard addedCount < maxAutoAddPerRefresh else { break }
                await AppModel.current?.enqueue(episode.id)
                addedCount += 1
            }
        }

        if addedCount > 0 {
            Self.logger.info("Auto-added \(addedCount) episodes to queue")
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

struct TimeoutError: Error {
    let localizedDescription = "Operation timed out"
} 