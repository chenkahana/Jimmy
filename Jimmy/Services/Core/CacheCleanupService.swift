import Foundation
import os.log

/// Service to manage cache cleanup and reduce memory pressure
/// This addresses memory-intensive operations identified in analysis
final class CacheCleanupService {
    static let shared = CacheCleanupService()
    
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "CacheCleanupService")
    private var cleanupTimer: Timer?
    
    private init() {
        logger.info("CacheCleanupService initialized")
        setupPeriodicCleanup()
    }
    
    /// Setup periodic cache cleanup
    private func setupPeriodicCleanup() {
        // Clean up caches every 5 minutes to prevent memory buildup
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            self?.performLightweightCleanup()
        }
    }
    
    /// Perform lightweight cache cleanup
    private func performLightweightCleanup() {
        let memoryUsage = MemoryTracker.shared.getCurrentMemoryUsage()
        
        // Only clean up if memory usage is above threshold
        if memoryUsage > 60.0 { // 60MB threshold
            logger.info("Memory usage at \(String(format: "%.1f", memoryUsage))MB - performing cache cleanup")
            
            // Clean URL cache
            let urlCache = URLCache.shared
            let beforeSize = urlCache.currentMemoryUsage
            urlCache.removeAllCachedResponses()
            
            logger.debug("Cleaned URL cache: \(beforeSize) bytes freed")
            
            // Log memory usage after cleanup
            let newMemoryUsage = MemoryTracker.shared.getCurrentMemoryUsage()
            let saved = memoryUsage - newMemoryUsage
            if saved > 0 {
                logger.info("Cache cleanup saved \(String(format: "%.1f", saved))MB")
            }
        }
    }
    
    /// Force cache cleanup (for memory pressure situations)
    func forceCleanup() {
        logger.info("Force cache cleanup requested")
        performLightweightCleanup()
        
        // Additional cleanup for memory pressure
        performAggressiveCleanup()
    }
    
    /// Perform aggressive cache cleanup during memory pressure
    private func performAggressiveCleanup() {
        logger.info("Performing aggressive cache cleanup")
        
        // Clear URL cache completely
        URLCache.shared.removeAllCachedResponses()
        
        // Suggest garbage collection
        autoreleasepool {
            // This helps release autoreleased objects
        }
        
        logger.info("Aggressive cache cleanup completed")
    }
    
    /// Get cache statistics
    func getCacheStats() -> String {
        let urlCache = URLCache.shared
        let memoryUsage = MemoryTracker.shared.getCurrentMemoryUsage()
        
        return """
        Cache Statistics:
        - URL Cache Memory: \(urlCache.currentMemoryUsage) bytes
        - URL Cache Disk: \(urlCache.currentDiskUsage) bytes
        - Current Memory Usage: \(String(format: "%.1f", memoryUsage))MB
        """
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
}