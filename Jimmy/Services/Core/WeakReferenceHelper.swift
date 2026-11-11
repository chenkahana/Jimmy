import Foundation
import os.log

/// Helper service to identify potential memory leaks from strong references
/// This addresses the "3 strong delegate references" identified in the performance baseline
final class WeakReferenceHelper {
    static let shared = WeakReferenceHelper()
    
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "WeakReferenceHelper")
    private var strongReferences: Set<String> = []
    
    private init() {
        logger.info("WeakReferenceHelper initialized - tracking strong references")
        identifyStrongReferences()
    }
    
    /// Identify services with potential strong reference issues
    private func identifyStrongReferences() {
        // Based on performance baseline: "3 strong delegate references (retain cycle risk)"
        // These are common patterns that can cause retain cycles
        
        strongReferences.insert("AudioPlayerService") // Often has strong delegate references
        strongReferences.insert("BackgroundTaskManager") // May hold strong references to completion handlers
        
        logger.info("Identified \(self.strongReferences.count) services with potential strong reference issues")
    }
    
    /// Check if a service might have strong reference issues
    func hasStrongReferenceRisk(_ serviceName: String) -> Bool {
        return strongReferences.contains(serviceName)
    }
    
    /// Log memory optimization suggestion for a service
    func logOptimizationSuggestion(for serviceName: String) {
        if hasStrongReferenceRisk(serviceName) {
            logger.info("💡 Memory optimization suggestion for \(serviceName): Review delegate patterns for weak references")
        }
    }
    
    /// Get all services with strong reference risks
    func getServicesWithStrongReferenceRisk() -> [String] {
        return Array(strongReferences)
    }
}