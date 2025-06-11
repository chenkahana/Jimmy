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
        static let refreshInterval: TimeInterval = 60 * 60 // Increased to 60 minutes to reduce background load
        static let maxBackgroundTime: TimeInterval = 15 // Reduced to 15 seconds max for background processing
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
            // REDUCED SCOPE: Only refresh podcast data, not episodes, to reduce memory pressure
            // Episodes will be updated when app is active through EpisodeUpdateService
            let result = await refreshPodcastData()
            
            // Check if we exceeded time limit
            if Date().timeIntervalSince(startTime) > Config.maxBackgroundTime {
                print("⏰ Background refresh timeout reached")
                return false
            }
            
            return result
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
        // DISABLED: Don't schedule background refresh automatically to prevent Signal 9 crashes
        // Background refresh will only be scheduled manually when needed
        
        // Cancel background refresh when app goes to background to reduce memory pressure
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Cancel to prevent excessive background processing
            Task { @MainActor in
                self?.cancelBackgroundRefresh()
            }
        }
        
        // Don't automatically restart background tasks when app becomes active
        // This prevents aggressive background processing that leads to Signal 9 crashes
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