import Foundation
import os.log

/// Memory tracking service for Phase 4.2 optimizations
/// This helps measure the impact of memory management improvements
final class MemoryTracker {
    static let shared = MemoryTracker()
    
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "MemoryTracker")
    private var initialMemoryUsage: Double = 0
    
    private init() {
        initialMemoryUsage = getCurrentMemoryUsage()
        logger.info("MemoryTracker initialized - baseline: \(String(format: "%.1f", self.initialMemoryUsage))MB")
    }
    
    /// Get current memory usage in MB
    func getCurrentMemoryUsage() -> Double {
        let bytes = MemoryMonitor.shared.getCurrentMemoryUsage()
        return Double(bytes) / (1024.0 * 1024.0)
    }
    
    /// Log memory usage with context
    func logMemoryUsage(context: String) {
        let currentMemory = getCurrentMemoryUsage()
        let change = currentMemory - initialMemoryUsage
        let changeStr = change >= 0 ? "+\(String(format: "%.1f", change))" : "\(String(format: "%.1f", change))"
        
        logger.info("Memory (\(context)): \(String(format: "%.1f", currentMemory))MB (\(changeStr)MB from baseline)")
    }
    
    /// Check if memory optimization is needed
    func needsOptimization() -> Bool {
        let currentMemory = getCurrentMemoryUsage()
        return currentMemory > 80.0 // Threshold for optimization
    }
}