import Foundation
import os.signpost

/// Performance monitoring service following CHAT_HELP.md specification
/// Uses os_signpost to wrap fetch, decode, DB write blocks
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    // MARK: - Signpost Configuration
    private let subsystem = "Jimmy"
    private let category = "Performance"
    
    // MARK: - Signpost Logs
    private let fetchLog: OSLog
    private let decodeLog: OSLog
    private let dbWriteLog: OSLog
    private let uiUpdateLog: OSLog
    
    // MARK: - Signpost IDs
    private let fetchSignpost: OSSignpostID
    private let decodeSignpost: OSSignpostID
    private let dbWriteSignpost: OSSignpostID
    private let uiUpdateSignpost: OSSignpostID
    
    // MARK: - Performance Metrics
    private var metrics = LegacyPerformanceMetrics()
    private let metricsQueue = DispatchQueue(label: "com.jimmy.performance.metrics", attributes: .concurrent)
    
    #if canImport(OSLog)
    #endif
    
    // MARK: - Initialization
    
    private init() {
        // Initialize signpost logs
        fetchLog = OSLog(subsystem: subsystem, category: "\(category).Fetch")
        decodeLog = OSLog(subsystem: subsystem, category: "\(category).Decode")
        dbWriteLog = OSLog(subsystem: subsystem, category: "\(category).DBWrite")
        uiUpdateLog = OSLog(subsystem: subsystem, category: "\(category).UIUpdate")
        
        // Initialize signpost IDs
        fetchSignpost = OSSignpostID(log: fetchLog)
        decodeSignpost = OSSignpostID(log: decodeLog)
        dbWriteSignpost = OSSignpostID(log: dbWriteLog)
        uiUpdateSignpost = OSSignpostID(log: uiUpdateLog)
        
        #if canImport(OSLog)
        #endif
    }
    
    // MARK: - Fetch Performance Monitoring
    
    /// Monitor fetch operation performance
    func monitorFetch<T>(
        podcastTitle: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: fetchLog, name: "PodcastFetch", signpostID: fetchSignpost,
                   "Starting fetch for: %{public}s", podcastTitle)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            
            os_signpost(.end, log: fetchLog, name: "PodcastFetch", signpostID: fetchSignpost,
                       "Completed fetch for: %{public}s in %.3fs", podcastTitle, duration)
            
            recordFetchMetrics(duration: duration, podcastTitle: podcastTitle)
        }
        
        return try await operation()
    }
    
    /// Monitor batch fetch performance
    func monitorBatchFetch<T>(
        podcastCount: Int,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: fetchLog, name: "BatchFetch", signpostID: fetchSignpost,
                   "Starting batch fetch for %d podcasts", podcastCount)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            
            os_signpost(.end, log: fetchLog, name: "BatchFetch", signpostID: fetchSignpost,
                       "Completed batch fetch for %d podcasts in %.3fs", podcastCount, duration)
            
            recordBatchFetchMetrics(duration: duration, podcastCount: podcastCount)
        }
        
        return try await operation()
    }
    
    // MARK: - Decode Performance Monitoring
    
    /// Monitor RSS decode operation
    func monitorDecode<T>(
        dataSize: Int,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: decodeLog, name: "RSSParse", signpostID: decodeSignpost,
                   "Starting RSS parse for %d bytes", dataSize)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            
            os_signpost(.end, log: decodeLog, name: "RSSParse", signpostID: decodeSignpost,
                       "Completed RSS parse for %d bytes in %.3fs", dataSize, duration)
            
            recordDecodeMetrics(duration: duration, dataSize: dataSize)
        }
        
        return try operation()
    }
    
    // MARK: - Database Write Performance Monitoring
    
    /// Monitor database write operation
    func monitorDBWrite<T>(
        changeCount: Int,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: dbWriteLog, name: "DBWrite", signpostID: dbWriteSignpost,
                   "Starting DB write for %d changes", changeCount)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            
            os_signpost(.end, log: dbWriteLog, name: "DBWrite", signpostID: dbWriteSignpost,
                       "Completed DB write for %d changes in %.3fs", changeCount, duration)
            
            recordDBWriteMetrics(duration: duration, changeCount: changeCount)
        }
        
        return try await operation()
    }
    
    // MARK: - UI Update Performance Monitoring
    
    /// Monitor UI update operation (< 16ms goal for 60fps, < 8ms for 120fps)
    @MainActor
    func monitorUIUpdate<T>(
        episodeCount: Int,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: uiUpdateLog, name: "UIUpdate", signpostID: uiUpdateSignpost,
                   "Starting UI update for %d episodes", episodeCount)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            let durationMs = duration * 1000
            
            os_signpost(.end, log: uiUpdateLog, name: "UIUpdate", signpostID: uiUpdateSignpost,
                       "Completed UI update for %d episodes in %.1fms", episodeCount, durationMs)
            
            recordUIUpdateMetrics(duration: duration, episodeCount: episodeCount)
            
            // Dynamic threshold based on ProMotion availability
            let proMotionManager = ProMotionManager.shared
            let threshold = proMotionManager.isProMotionAvailable ? 8.0 : 16.0 // 120fps vs 60fps
            
            // Warn if UI update exceeds threshold
            if durationMs > threshold {
                #if canImport(OSLog)
                #endif
            }
        }
        
        return try operation()
    }
    
    // MARK: - Animation Performance Monitoring
    
    /// Monitor skeleton animation performance
    func monitorSkeletonAnimation<T>(
        skeletonCount: Int,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: uiUpdateLog, name: "SkeletonAnimation", signpostID: uiUpdateSignpost,
                   "Starting skeleton animation for %d items", skeletonCount)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            let durationMs = duration * 1000
            
            os_signpost(.end, log: uiUpdateLog, name: "SkeletonAnimation", signpostID: uiUpdateSignpost,
                       "Completed skeleton animation for %d items in %.1fms", skeletonCount, durationMs)
            
            recordSkeletonAnimationMetrics(duration: duration, skeletonCount: skeletonCount)
        }
        
        return try operation()
    }
    
    /// Monitor loading state transitions
    func monitorLoadingStateTransition<T>(
        fromState: String,
        toState: String,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: uiUpdateLog, name: "LoadingStateTransition", signpostID: uiUpdateSignpost,
                   "Transitioning from %{public}s to %{public}s", fromState, toState)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            
            os_signpost(.end, log: uiUpdateLog, name: "LoadingStateTransition", signpostID: uiUpdateSignpost,
                       "Completed transition from %{public}s to %{public}s in %.3fs", fromState, toState, duration)
            
            recordLoadingStateTransitionMetrics(duration: duration, fromState: fromState, toState: toState)
        }
        
        return try operation()
    }
    
    /// Monitor ProMotion animation performance
    func monitorProMotionAnimation<T>(
        animationType: String,
        targetFPS: Int,
        operation: () throws -> T
    ) rethrows -> T {
        let startTime = Date()
        
        os_signpost(.begin, log: uiUpdateLog, name: "ProMotionAnimation", signpostID: uiUpdateSignpost,
                   "Starting %{public}s animation targeting %d fps", animationType, targetFPS)
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            
            os_signpost(.end, log: uiUpdateLog, name: "ProMotionAnimation", signpostID: uiUpdateSignpost,
                       "Completed %{public}s animation in %.3fs", animationType, duration)
            
            recordProMotionAnimationMetrics(duration: duration, animationType: animationType, targetFPS: targetFPS)
        }
        
        return try operation()
    }
    
    // MARK: - Custom Telemetry
    
    /// Log custom performance event
    func logCustomEvent(
        name: String,
        duration: TimeInterval,
        metadata: [String: Any] = [:]
    ) {
        #if canImport(OSLog)
        #endif
        
        metricsQueue.async(flags: .barrier) {
            self.metrics.customEvents.append(CustomEvent(
                name: name,
                duration: duration,
                timestamp: Date(),
                metadata: metadata
            ))
        }
    }
    
    /// Log fetch duration and lock wait times
    func logFetchDuration(_ duration: TimeInterval, lockWaitTime: TimeInterval = 0) {
        #if canImport(OSLog)
        #endif
    }
    
    /// Log queue depth
    func logQueueDepth(_ depth: Int, queueName: String) {
        #if canImport(OSLog)
        #endif
    }
    
    // MARK: - Metrics Collection
    
    /// Get current performance metrics
    func getCurrentMetrics() -> LegacyPerformanceMetrics {
        return metricsQueue.sync {
            return metrics
        }
    }
    
    /// Reset performance metrics
    func resetMetrics() {
        metricsQueue.async(flags: .barrier) {
            self.metrics = LegacyPerformanceMetrics()
        }
        
        #if canImport(OSLog)
        #endif
    }
    
    // MARK: - Private Metrics Recording
    
    private func recordFetchMetrics(duration: TimeInterval, podcastTitle: String) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.fetchOperations.append(FetchMetric(
                duration: duration,
                podcastTitle: podcastTitle,
                timestamp: Date()
            ))
        }
    }
    
    private func recordBatchFetchMetrics(duration: TimeInterval, podcastCount: Int) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.batchFetchOperations.append(BatchFetchMetric(
                duration: duration,
                podcastCount: podcastCount,
                timestamp: Date()
            ))
        }
    }
    
    private func recordDecodeMetrics(duration: TimeInterval, dataSize: Int) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.decodeOperations.append(DecodeMetric(
                duration: duration,
                dataSize: dataSize,
                timestamp: Date()
            ))
        }
    }
    
    private func recordDBWriteMetrics(duration: TimeInterval, changeCount: Int) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.dbWriteOperations.append(DBWriteMetric(
                duration: duration,
                changeCount: changeCount,
                timestamp: Date()
            ))
        }
    }
    
    private func recordUIUpdateMetrics(duration: TimeInterval, episodeCount: Int) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.uiUpdateOperations.append(UIUpdateMetric(
                duration: duration,
                episodeCount: episodeCount,
                timestamp: Date()
            ))
        }
    }
    
    private func recordSkeletonAnimationMetrics(duration: TimeInterval, skeletonCount: Int) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.skeletonAnimations.append(SkeletonAnimationMetric(
                duration: duration,
                skeletonCount: skeletonCount,
                timestamp: Date()
            ))
        }
    }
    
    private func recordLoadingStateTransitionMetrics(duration: TimeInterval, fromState: String, toState: String) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.loadingStateTransitions.append(LoadingStateTransitionMetric(
                duration: duration,
                fromState: fromState,
                toState: toState,
                timestamp: Date()
            ))
        }
    }
    
    private func recordProMotionAnimationMetrics(duration: TimeInterval, animationType: String, targetFPS: Int) {
        metricsQueue.async(flags: .barrier) {
            self.metrics.proMotionAnimations.append(ProMotionAnimationMetric(
                duration: duration,
                animationType: animationType,
                targetFPS: targetFPS,
                timestamp: Date()
            ))
        }
    }
}

// MARK: - Performance Metrics Models

struct LegacyPerformanceMetrics {
    var fetchOperations: [FetchMetric] = []
    var batchFetchOperations: [BatchFetchMetric] = []
    var decodeOperations: [DecodeMetric] = []
    var dbWriteOperations: [DBWriteMetric] = []
    var uiUpdateOperations: [UIUpdateMetric] = []
    var skeletonAnimations: [SkeletonAnimationMetric] = []
    var loadingStateTransitions: [LoadingStateTransitionMetric] = []
    var proMotionAnimations: [ProMotionAnimationMetric] = []
    var customEvents: [CustomEvent] = []
    
    var averageFetchTime: TimeInterval {
        guard !fetchOperations.isEmpty else { return 0 }
        return fetchOperations.map(\.duration).reduce(0, +) / Double(fetchOperations.count)
    }
    
    var averageUIUpdateTime: TimeInterval {
        guard !uiUpdateOperations.isEmpty else { return 0 }
        return uiUpdateOperations.map(\.duration).reduce(0, +) / Double(uiUpdateOperations.count)
    }
    
    var averageSkeletonAnimationTime: TimeInterval {
        guard !skeletonAnimations.isEmpty else { return 0 }
        return skeletonAnimations.map(\.duration).reduce(0, +) / Double(skeletonAnimations.count)
    }
    
    var averageLoadingStateTransitionTime: TimeInterval {
        guard !loadingStateTransitions.isEmpty else { return 0 }
        return loadingStateTransitions.map(\.duration).reduce(0, +) / Double(loadingStateTransitions.count)
    }
    
    var slowUIUpdates: [UIUpdateMetric] {
        // Use a fixed threshold since we can't access MainActor from here
        let threshold = 0.016 // 60fps threshold as fallback
        return uiUpdateOperations.filter { $0.duration > threshold }
    }
    
    var slowSkeletonAnimations: [SkeletonAnimationMetric] {
        return skeletonAnimations.filter { $0.duration > 0.1 } // > 100ms
    }
}

struct FetchMetric {
    let duration: TimeInterval
    let podcastTitle: String
    let timestamp: Date
}

struct BatchFetchMetric {
    let duration: TimeInterval
    let podcastCount: Int
    let timestamp: Date
    
    var throughput: Double {
        return Double(podcastCount) / duration
    }
}

struct DecodeMetric {
    let duration: TimeInterval
    let dataSize: Int
    let timestamp: Date
    
    var throughput: Double {
        return Double(dataSize) / duration // bytes per second
    }
}

struct DBWriteMetric {
    let duration: TimeInterval
    let changeCount: Int
    let timestamp: Date
}

struct UIUpdateMetric {
    let duration: TimeInterval
    let episodeCount: Int
    let timestamp: Date
    
    var durationMs: Double {
        return duration * 1000
    }
    
    var exceedsThreshold: Bool {
        return durationMs > 16.0 // 60fps threshold
    }
}

struct CustomEvent {
    let name: String
    let duration: TimeInterval
    let timestamp: Date
    let metadata: [String: Any]
}

struct SkeletonAnimationMetric {
    let duration: TimeInterval
    let skeletonCount: Int
    let timestamp: Date
    
    var durationMs: Double {
        return duration * 1000
    }
    
    var isSlowAnimation: Bool {
        return duration > 0.1 // > 100ms
    }
}

struct LoadingStateTransitionMetric {
    let duration: TimeInterval
    let fromState: String
    let toState: String
    let timestamp: Date
    
    var durationMs: Double {
        return duration * 1000
    }
}

struct ProMotionAnimationMetric {
    let duration: TimeInterval
    let animationType: String
    let targetFPS: Int
    let timestamp: Date
    
    var durationMs: Double {
        return duration * 1000
    }
    
    var isProMotionOptimized: Bool {
        return targetFPS > 60
    }
} 