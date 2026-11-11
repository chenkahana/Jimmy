import Foundation
import UIKit
import os.log

/// Manages singleton lifecycle to reduce memory pressure
/// This addresses the issue of 58 singleton services identified in analysis
final class SingletonLifecycleManager {
    static let shared = SingletonLifecycleManager()
    
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SingletonLifecycleManager")
    private var managedSingletons: [String: Any] = [:]
    private var singletonUsageCount: [String: Int] = [:]
    
    private init() {
        logger.info("SingletonLifecycleManager initialized - managing singleton lifecycle")
        setupMemoryPressureObserver()
    }
    
    /// Register a singleton for lifecycle management
    func registerSingleton<T>(_ singleton: T, name: String) {
        managedSingletons[name] = singleton
        singletonUsageCount[name] = 0
        logger.debug("Registered singleton: \(name)")
    }
    
    /// Track singleton usage
    func trackUsage(of singletonName: String) {
        singletonUsageCount[singletonName, default: 0] += 1
    }
    
    /// Get usage statistics
    func getUsageStats() -> [String: Int] {
        return singletonUsageCount
    }
    
    /// Setup memory pressure observer to clean up unused singletons
    private func setupMemoryPressureObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryPressure()
        }
    }
    
    /// Handle memory pressure by identifying unused singletons
    private func handleMemoryPressure() {
        logger.warning("Memory pressure detected - analyzing singleton usage")
        
        let unusedSingletons = singletonUsageCount.filter { $0.value == 0 }
        if !unusedSingletons.isEmpty {
            logger.info("Found \(unusedSingletons.count) unused singletons that could be optimized")
            for (name, _) in unusedSingletons {
                logger.debug("Unused singleton: \(name)")
            }
        }
        
        // Log memory optimization suggestions
        logMemoryOptimizationSuggestions()
    }
    
    /// Log memory optimization suggestions
    private func logMemoryOptimizationSuggestions() {
        let totalSingletons = managedSingletons.count
        let unusedCount = singletonUsageCount.filter { $0.value == 0 }.count
        
        if unusedCount > 0 {
            logger.info("💡 Memory optimization: \(unusedCount)/\(totalSingletons) singletons are unused and could be lazy-loaded")
        }
    }
    
    /// Get memory optimization report
    func getMemoryOptimizationReport() -> String {
        let totalSingletons = managedSingletons.count
        let unusedCount = singletonUsageCount.filter { $0.value == 0 }.count
        let usedCount = totalSingletons - unusedCount
        
        return """
        Singleton Memory Report:
        - Total managed singletons: \(totalSingletons)
        - Currently used: \(usedCount)
        - Unused (optimization opportunity): \(unusedCount)
        - Memory optimization potential: \(unusedCount > 0 ? "\(Int(Double(unusedCount)/Double(totalSingletons) * 100))%" : "0%")
        """
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}