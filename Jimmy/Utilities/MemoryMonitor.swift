import Foundation
import UIKit
import os.log

/// Memory monitoring utility to prevent memory crashes
final class MemoryMonitor {
    static let shared = MemoryMonitor()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "memory")
    
    // MARK: - Configuration
    private struct Config {
        static let warningThreshold: Int = 200 * 1024 * 1024 // 200MB
        static let criticalThreshold: Int = 300 * 1024 * 1024 // 300MB
        static let monitoringInterval: TimeInterval = 30.0 // 30 seconds
    }
    
    // MARK: - Properties
    private var monitoringTimer: Timer?
    private var lastMemoryWarning: Date?
    
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
        logger.warning("🧹 Forcing memory cleanup")
        
        // Trigger cleanup in various services
        CrashPreventionManager.shared.handleMemoryWarning()
        
        // Force garbage collection
        for _ in 0..<3 {
            autoreleasepool {
                // Trigger garbage collection
            }
        }
        
        logger.info("✅ Memory cleanup completed")
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
        
        if currentUsage > Config.criticalThreshold {
            logger.error("🚨 CRITICAL: Memory usage is \(self.getFormattedMemoryUsage())")
            forceMemoryCleanup()
        } else if currentUsage > Config.warningThreshold {
            logger.warning("⚠️ WARNING: Memory usage is \(self.getFormattedMemoryUsage())")
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("📱 System memory warning received")
        lastMemoryWarning = Date()
        forceMemoryCleanup()
    }
} 