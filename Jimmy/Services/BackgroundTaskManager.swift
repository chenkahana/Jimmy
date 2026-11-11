import Foundation
import os
import BackgroundTasks
import UIKit

/// Manages background tasks for podcast refresh operations
/// Replaces Timer-based refresh with BGTaskScheduler for better iOS integration
@MainActor
class BackgroundTaskManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "BackgroundTaskManager")
    static let shared = BackgroundTaskManager()
    
    // MARK: - Configuration
    
    private struct Config {
        static let backgroundRefreshIdentifier = "com.chenkahana.Jimmy.refresh"
        static let libraryIncrementalRefreshIdentifier = "com.chenkahana.Jimmy.libraryIncrementalRefresh"
        static let refreshInterval: TimeInterval = 60 * 60 // Increased to 60 minutes to reduce background load
        static let maxBackgroundTime: TimeInterval = 15 // Reduced to 15 seconds max for background processing
    }
    
    // MARK: - Properties
    
    private let podcastDataManager = PodcastDataManager.shared
    private let episodeUpdateService = EpisodeUpdateService.shared
    
    @Published var lastBackgroundRefresh: Date?
    @Published var backgroundRefreshCount: Int = 0
    
    // Track if background tasks are already registered to prevent re-registration
    private var backgroundTasksRegistered = false
    
    // MARK: - Initialization
    
    private init() {
        // Don't register background tasks here - they must be registered during app init
        // registerBackgroundTasks() will be called from JimmyApp.init()
        setupAppStateObservers()
    }
    
    // MARK: - Public Interface
    
    /// Register background task handlers
    func registerBackgroundTasks() {
        guard !backgroundTasksRegistered else {
            return
        }
        
        // Register background app refresh
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Config.backgroundRefreshIdentifier, using: nil) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        
        // Register library incremental refresh for LibrarySorter
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Config.libraryIncrementalRefreshIdentifier, using: nil) { task in
            self.handleLibraryIncrementalRefresh(task: task as! BGAppRefreshTask)
        }
        
        backgroundTasksRegistered = true
    }
    
    /// Schedule the next background refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Config.backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Config.refreshInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background refresh scheduling failed - log as error only
        }
    }
    
    /// Schedule library incremental refresh for LibrarySorter warm-launch updates
    func scheduleLibraryIncrementalRefresh() {
        // Schedule library incremental refresh for LibrarySorter warm-launch updates
        
        let request = BGAppRefreshTaskRequest(identifier: Config.libraryIncrementalRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes for incremental refresh
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background refresh scheduling failed - log as error only
        }
    }
    
    /// Cancel scheduled background refresh
    func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Config.backgroundRefreshIdentifier)
    }
    
    /// Cancel library incremental refresh
    func cancelLibraryIncrementalRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Config.libraryIncrementalRefreshIdentifier)
    }
    
    /// Force immediate background refresh (for testing)
    func performImmediateRefresh() {
        Task {
            await performBackgroundRefreshOperations()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh immediately
        scheduleBackgroundRefresh()
        
        // PERF-08: Create budget tracker for this background session
        let budgetTracker = BackgroundBudgetTracker(maxTime: Config.maxBackgroundTime)
        
        // Set expiration handler
        task.expirationHandler = { [budgetTracker] in
            budgetTracker.markExpired()
            task.setTaskCompleted(success: false)
        }
        
        // Perform the refresh operations with budget tracking
        Task {
            let success = await performBackgroundRefreshOperations(budgetTracker: budgetTracker)
            
            await MainActor.run { [weak self] in
                self?.lastBackgroundRefresh = Date()
                self?.backgroundRefreshCount += 1
            }
            
            task.setTaskCompleted(success: success)
        }
    }
    
    private func performBackgroundRefreshOperations(budgetTracker: BackgroundBudgetTracker? = nil) async -> Bool {
        let tracker = budgetTracker ?? BackgroundBudgetTracker(maxTime: Config.maxBackgroundTime)
        
        do {
            // PERF-08: Check budget before each operation
            guard tracker.hasRemainingBudget else {
                Self.logger.warning("Background budget exhausted before starting")
                return false
            }
            
            // REDUCED SCOPE: Only refresh podcast data, not episodes, to reduce memory pressure
            // Episodes will be updated when app is active through EpisodeUpdateService
            let result = await refreshPodcastData()
            
            // PERF-08: Log budget usage
            let usage = tracker.budgetUsage
            let usagePct = String(format: "%.1f", usage * 100)
            Self.logger.info("Background refresh completed - Budget used: \(usagePct)%")
            
            // Check if we exceeded time limit
            guard tracker.hasRemainingBudget else {
                Self.logger.warning("Background budget exhausted during refresh")
                return false
            }
            
            return result
        } catch {
            return false
        }
    }
    
    /// Handle library incremental refresh for LibrarySorter
    private func handleLibraryIncrementalRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleLibraryIncrementalRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Perform incremental refresh using LibrarySorter
        Task {
            let success = await performLibraryIncrementalRefresh()
            
            await MainActor.run { [weak self] in
                self?.lastBackgroundRefresh = Date()
                self?.backgroundRefreshCount += 1
            }
            
            task.setTaskCompleted(success: success)
        }
    }
    
    /// Perform library incremental refresh using the shared integration layer.
    private func performLibraryIncrementalRefresh() async -> Bool {
        let startTime = Date()
        
        do {
            // Refresh podcasts through the shared integration layer.
            _ = try await WorldClassIntegration.shared.fetchPodcasts(forceRefresh: true)
            
            // Check if we exceeded time limit (should be much faster with incremental refresh)
            if Date().timeIntervalSince(startTime) > Config.maxBackgroundTime {
                return false
            }
            
            return true
        } catch {
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

// MARK: - PERF-08: Background Budget Tracker

/// Tracks remaining background execution time budget
/// iOS gives limited time for background tasks - this helps prioritize operations
final class BackgroundBudgetTracker: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "BackgroundBudgetTracker")
    private let startTime: Date
    private let maxTime: TimeInterval
    private var isExpired: Bool = false
    private let lock = NSLock()

    /// Reserve some time for cleanup operations
    private let reservedTime: TimeInterval = 2.0
    
    init(maxTime: TimeInterval) {
        self.startTime = Date()
        self.maxTime = maxTime
    }
    
    /// Time elapsed since budget tracking started
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    /// Time remaining in the budget (accounting for reserved cleanup time)
    var remainingTime: TimeInterval {
        max(0, maxTime - elapsedTime - reservedTime)
    }
    
    /// Whether there's still budget available for operations
    var hasRemainingBudget: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isExpired && remainingTime > 0
    }
    
    /// Percentage of budget used (0.0 to 1.0)
    var budgetUsage: Double {
        min(1.0, elapsedTime / maxTime)
    }
    
    /// Mark the budget as expired (called when iOS signals expiration)
    func markExpired() {
        lock.lock()
        defer { lock.unlock() }
        isExpired = true
        let elapsedFormatted = String(format: "%.1f", elapsedTime)
        Self.logger.warning("Background budget expired by iOS after \(elapsedFormatted)s")
    }
    
    /// Check if there's enough time for an operation with estimated duration
    func canPerformOperation(estimatedDuration: TimeInterval) -> Bool {
        remainingTime >= estimatedDuration
    }
    
    /// Get a description of current budget status
    var statusDescription: String {
        if isExpired {
            return "Expired (iOS terminated)"
        } else if hasRemainingBudget {
            return "Active - \(String(format: "%.1f", remainingTime))s remaining"
        } else {
            return "Exhausted"
        }
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
                    // Mock background task completed
    }
}
#endif 
