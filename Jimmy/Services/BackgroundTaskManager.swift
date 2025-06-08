import Foundation
import BackgroundTasks
import UIKit

/// Manages background tasks for podcast refresh operations
/// Replaces Timer-based refresh with BGTaskScheduler for better iOS integration
@MainActor
class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()
    
    // MARK: - Configuration
    
    private struct Config {
        static let backgroundRefreshIdentifier = "com.chenkahana.Jimmy.refresh"
        static let refreshInterval: TimeInterval = 30 * 60 // 30 minutes
        static let maxBackgroundTime: TimeInterval = 25 // 25 seconds max for background processing
    }
    
    // MARK: - Properties
    
    private let podcastDataManager = PodcastDataManager.shared
    private let episodeUpdateService = EpisodeUpdateService.shared
    
    @Published var lastBackgroundRefresh: Date?
    @Published var backgroundRefreshCount: Int = 0
    
    // MARK: - Initialization
    
    private init() {
        registerBackgroundTasks()
        setupAppStateObservers()
    }
    
    // MARK: - Public Interface
    
    /// Register background task handlers
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Config.backgroundRefreshIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    /// Schedule the next background refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Config.backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Config.refreshInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 Background refresh scheduled for \(request.earliestBeginDate?.formatted() ?? "unknown time")")
        } catch {
            print("❌ Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }
    
    /// Cancel scheduled background refresh
    func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Config.backgroundRefreshIdentifier)
        print("🚫 Background refresh cancelled")
    }
    
    /// Force immediate background refresh (for testing)
    func performImmediateRefresh() {
        Task {
            await performBackgroundRefreshOperations()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        print("🔄 Background refresh task started")
        
        // Schedule the next refresh immediately
        scheduleBackgroundRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            print("⏰ Background refresh task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Perform the refresh operations
        Task {
            let success = await performBackgroundRefreshOperations()
            
            await MainActor.run { [weak self] in
                self?.lastBackgroundRefresh = Date()
                self?.backgroundRefreshCount += 1
            }
            
            task.setTaskCompleted(success: success)
        }
    }
    
    private func performBackgroundRefreshOperations() async -> Bool {
        let startTime = Date()
        
        do {
            // Create a task group to run operations concurrently
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                var results: [Bool] = []
                
                // Add podcast refresh task
                group.addTask { [weak self] in
                    await self?.refreshPodcastData() ?? false
                }
                
                // Add episode update task
                group.addTask { [weak self] in
                    await self?.refreshEpisodeData() ?? false
                }
                
                // Collect results with timeout
                for try await result in group {
                    results.append(result)
                    
                    // Check if we're running out of time
                    if Date().timeIntervalSince(startTime) > Config.maxBackgroundTime {
                        print("⏰ Background refresh timeout reached")
                        break
                    }
                }
                
                return results.allSatisfy { $0 }
            }
        } catch {
            print("❌ Background refresh failed: \(error.localizedDescription)")
            return false
        }
    }
    
    private func refreshPodcastData() async -> Bool {
        return await podcastDataManager.performBackgroundRefresh()
    }
    
    private func refreshEpisodeData() async -> Bool {
        return await withCheckedContinuation { continuation in
            Task {
                // Update episodes in background using the public forceUpdate method
                episodeUpdateService.forceUpdate()
                continuation.resume(returning: true)
            }
        }
    }
    
    private func setupAppStateObservers() {
        // Schedule background refresh when app enters background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleBackgroundRefresh()
        }
        
        // Cancel background refresh when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Don't cancel - let background refresh continue for better user experience
            // self?.cancelBackgroundRefresh()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension BackgroundTaskManager {
    /// Test background refresh in simulator
    func simulateBackgroundRefresh() {
        Task {
            await performBackgroundRefreshOperations()
        }
    }
}

private class MockBGAppRefreshTask: NSObject {
    private var _expirationHandler: (() -> Void)?
    
    var expirationHandler: (() -> Void)? {
        get { _expirationHandler }
        set { _expirationHandler = newValue }
    }
    
    func setTaskCompleted(success: Bool) {
        print("🧪 Mock background task completed with success: \(success)")
    }
}
#endif 