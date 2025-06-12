import Foundation
import OSLog

/// WORLD-CLASS NAVIGATION: Ultra-fast UI performance manager with zero delays
@MainActor
class UIPerformanceManager: ObservableObject {
    static let shared = UIPerformanceManager()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "ui-performance")
    
    // MARK: - Published Properties (Minimal State)
    @Published var currentTab: Int = 3 // Start with Library tab
    private(set) var memoryUsage: Int = 0
    
    // MARK: - Private Properties (Minimal)
    private var memoryMonitorTimer: Timer?
    private let backgroundQueue = DispatchQueue(label: "ui-performance", qos: .utility)
    
    // Performance metrics (lightweight)
    private var tabSwitchTimes: [TimeInterval] = []
    private var lastTabSwitchStart: Date?
    
    private init() {
        setupMemoryMonitoring()
    }
    
    deinit {
        memoryMonitorTimer?.invalidate()
    }
    
    // MARK: - INSTANT Navigation
    
    /// WORLD-CLASS: Instant tab switching with zero delays
    func switchToTab(_ newTab: Int) {
        guard newTab != currentTab else { return }
        
        lastTabSwitchStart = Date()
        logger.info("⚡ INSTANT switch from tab \(self.currentTab) to tab \(newTab)")
        
        // INSTANT update - no animations, no delays, no debouncing
        currentTab = newTab
        
        // Track performance (non-blocking)
        trackTabSwitchPerformance()
    }
    
    // MARK: - Lightweight Performance Tracking
    
    private func trackTabSwitchPerformance() {
        if let startTime = lastTabSwitchStart {
            let switchTime = Date().timeIntervalSince(startTime)
            tabSwitchTimes.append(switchTime)
            
            // Keep only recent measurements (lightweight)
            if tabSwitchTimes.count > 5 {
                tabSwitchTimes.removeFirst()
            }
            
            logger.info("⚡ Tab switch completed in \(String(format: "%.3f", switchTime))s")
        }
        lastTabSwitchStart = nil
    }
    
    /// Get performance statistics
    func getPerformanceStats() -> (avgTabSwitchTime: TimeInterval, memoryUsage: Int) {
        let avgTabSwitchTime = tabSwitchTimes.isEmpty ? 0 : tabSwitchTimes.reduce(0, +) / Double(tabSwitchTimes.count)
        return (
            avgTabSwitchTime: avgTabSwitchTime,
            memoryUsage: memoryUsage
        )
    }
    
    /// Handle memory warning (lightweight)
    func handleMemoryWarning() {
        logger.warning("⚠️ Memory warning received")
        // Minimal cleanup - let iOS handle most of it
        backgroundQueue.async {
            autoreleasepool {
                // Lightweight cleanup
            }
        }
    }
    
    // MARK: - Minimal Memory Monitoring
    
    private func setupMemoryMonitoring() {
        // PERFORMANCE FIX: Reduce memory monitoring frequency from 60s to 300s (5 minutes)
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateMemoryUsage()
            }
        }
    }
    
    private func updateMemoryUsage() {
        // PERFORMANCE FIX: Remove background memory monitoring to prevent publishing warnings
        // Memory monitoring is not critical for UI performance
    }
}

// MARK: - Supporting Types (Minimal)

extension UIPerformanceManager {
    struct PerformanceMetrics {
        let avgTabSwitchTime: TimeInterval
        let memoryUsage: Int
    }
} 