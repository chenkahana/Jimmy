import Foundation
import os.log

/// Simple tracker for app initialization performance
/// This is a minimal service to measure initialization time without changing app structure
final class AppInitializationTracker {
    static let shared = AppInitializationTracker()
    
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "AppInitializationTracker")
    private let startTime: CFAbsoluteTime
    
    private init() {
        startTime = CFAbsoluteTimeGetCurrent()
        logger.info("App initialization tracking started")
    }
    
    /// Log the completion of app initialization
    func logInitializationComplete() {
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("App initialization completed in \(String(format: "%.2f", totalTime))s")
    }
    
    /// Get current initialization time
    func getCurrentInitializationTime() -> TimeInterval {
        return CFAbsoluteTimeGetCurrent() - startTime
    }
}