import Foundation
import UIKit
import os.log

/// Memory monitoring utility to prevent memory crashes
final class MemoryMonitor {
    static let shared = MemoryMonitor()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "memory")
    
    // MARK: - Configuration
    private struct Config {
        static let warningThreshold: Int = 400 * 1024 * 1024 // 400MB (increased from 200MB)
        static let criticalThreshold: Int = 600 * 1024 * 1024 // 600MB (increased from 300MB)
        static let emergencyThreshold: Int = 800 * 1024 * 1024 // 800MB (new emergency level)
        static let monitoringInterval: TimeInterval = 60.0 // 60 seconds (reduced frequency)
        static let cleanupCooldown: TimeInterval = 30.0 // Prevent excessive cleanup
    }
    
    // MARK: - Properties
    private var monitoringTimer: Timer?
    private var lastMemoryWarning: Date?
    private var lastCleanup: Date?
    
    private init() {
        setupMemoryWarningObserver()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Interface
    
    /// Get current memory usage in bytes
    func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
        }
    }
    
    /// Get formatted memory usage string
    func getFormattedMemoryUsage() -> String {
        let bytes = getCurrentMemoryUsage()
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
    
    /// Check if memory usage is critical
    func isMemoryUsageCritical() -> Bool {
        return getCurrentMemoryUsage() > Config.criticalThreshold
    }
    
    /// Force memory cleanup
    func forceMemoryCleanup() {
        // Prevent excessive cleanup calls
        if let lastCleanup = lastCleanup,
           Date().timeIntervalSince(lastCleanup) < Config.cleanupCooldown {
            logger.info("⏳ Skipping cleanup - too soon since last cleanup")
            return
        }
        
        lastCleanup = Date()
        logger.warning("🧹 Forcing memory cleanup - targeting heavy objects")
        
        // FOCUS ON REAL MEMORY HOGS:
        
        // 1. Clear audio player cache (AVPlayerItems are memory-heavy)
        AudioPlayerService.shared.clearPlayerItemCache()
        
        // 2. Clear image cache (Images can be memory-heavy)
        ImageCache.shared.clearMemoryCache()
        
        // 3. Trigger crash prevention cleanup
        CrashPreventionManager.shared.handleMemoryWarning()
        
        // 4. Clear file-based caches only if really needed
        // (Episode text data is minimal, but file cache can grow)
        let currentUsage = getCurrentMemoryUsage()
        if currentUsage > Config.criticalThreshold {
            EpisodeCacheService.shared.clearAllCache()
            logger.warning("🗑️ Cleared file caches due to critical memory usage")
        }
        
        // 5. Force garbage collection for any unreferenced objects
        for _ in 0..<3 {
            autoreleasepool {
                // Trigger garbage collection
            }
        }
        
        logger.info("✅ Memory cleanup completed - focused on media assets")
    }
    
    // MARK: - Private Methods
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func startMonitoring() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: Config.monitoringInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.checkMemoryUsage()
        }
    }
    
    private func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    private func checkMemoryUsage() {
        let currentUsage = getCurrentMemoryUsage()
        
        if currentUsage > Config.emergencyThreshold {
            logger.error("🚨 EMERGENCY: Memory usage is \(self.getFormattedMemoryUsage()) - forcing aggressive cleanup")
            forceMemoryCleanup()
            // Also stop non-essential services
            EpisodeUpdateService.shared.stopPeriodicUpdates()
        } else if currentUsage > Config.criticalThreshold {
            logger.error("🚨 CRITICAL: Memory usage is \(self.getFormattedMemoryUsage())")
            forceMemoryCleanup()
        } else if currentUsage > Config.warningThreshold {
            logger.warning("⚠️ WARNING: Memory usage is \(self.getFormattedMemoryUsage())")
            // Light cleanup - just clear caches
            AudioPlayerService.shared.clearPlayerItemCache()
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("📱 System memory warning received")
        lastMemoryWarning = Date()
        forceMemoryCleanup()
    }
} 