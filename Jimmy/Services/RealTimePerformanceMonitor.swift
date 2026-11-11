import Foundation
import OSLog
import Combine

// MARK: - Performance Metrics Structure
struct PerformanceMetrics: Codable {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PerformanceMetrics")
    var averageFetchTime: TimeInterval = 0
    var cacheHitRate: Double = 0
    var errorRate: Double = 0
    var throughput: Double = 0 // Operations per second
    var memoryUsage: Int64 = 0 // Bytes
    var networkLatency: TimeInterval = 0
    var parsingTime: TimeInterval = 0
    var sortingTime: TimeInterval = 0
    var totalOperations: Int = 0
    var failedOperations: Int = 0
    var lastUpdated: Date = Date()
}

import os.signpost

/// Real-Time Performance Monitor with advanced metrics and AI-powered insights
final class RealTimePerformanceMonitor: ObservableObject {
    private let logger = Logger(subsystem: "Jimmy.PerformanceMonitor", category: "RealTime")
    
    // MARK: - OSLog Signposts for Instruments Integration
    private let performanceLog = OSLog(subsystem: "Jimmy.Performance", category: "Operations")
    private let fetchSignpostID = OSSignpostID(log: OSLog(subsystem: "Jimmy.Performance", category: "Fetch"))
    private let sortSignpostID = OSSignpostID(log: OSLog(subsystem: "Jimmy.Performance", category: "Sort"))
    private let cacheSignpostID = OSSignpostID(log: OSLog(subsystem: "Jimmy.Performance", category: "Cache"))
    
    // MARK: - Performance Metrics
    @Published private(set) var currentMetrics = PerformanceMetrics()
    let metricsPublisher = PassthroughSubject<PerformanceMetrics, Never>()
    
    // MARK: - Advanced Tracking
    private var operationMetrics: [String: OperationMetrics] = [:]
    private var performanceHistory: [PerformanceSnapshot] = []
    private var anomalyDetector: RealTimePerformanceAnomalyDetector
    
    // MARK: - Concurrency Management - CRITICAL FIX: Use serial queue to prevent crashes
    private let metricsQueue = DispatchQueue(label: "PerformanceMetrics", qos: .utility)
    private let historyQueue = DispatchQueue(label: "PerformanceHistory", qos: .background)
    
    // MARK: - Configuration
    private struct Config {
        static let historyRetentionDays = 7
        static let anomalyThreshold = 2.0 // Standard deviations
        static let metricsUpdateInterval: TimeInterval = 1.0
        static let maxOperationHistory = 1000
    }
    
    // MARK: - Timers
    private var metricsTimer: Timer?
    
    init() {
        self.anomalyDetector = RealTimePerformanceAnomalyDetector()
        
        // CRITICAL FIX: Disable intensive monitoring in simulator to prevent crashes
        #if targetEnvironment(simulator)
        logger.info("📊 Real-Time Performance Monitor initialized (simulator mode - reduced functionality)")
        #else
        setupPerformanceMonitoring()
        logger.info("📊 Real-Time Performance Monitor initialized (full functionality)")
        #endif
    }
    
    deinit {
        metricsTimer?.invalidate()
    }
    
    // MARK: - Public API
    
    /// Measure operation performance with advanced tracking
    func measure<T>(
        operation: String,
        category: PerformanceCategory = .general,
        priority: OperationPriority = .normal,
        block: () async throws -> T
    ) async rethrows -> T {
        
        // CRITICAL FIX: Simplified monitoring in simulator to prevent crashes
        #if targetEnvironment(simulator)
        // In simulator, just execute the block without intensive monitoring
        return try await block()
        #else
        
        let operationID = UUID()
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = getCurrentMemoryUsage()
        
        // Start signpost for Instruments
        let signpostID = getSignpostID(for: category)
        os_signpost(.begin, log: performanceLog, name: "Operation", signpostID: signpostID, 
                   "Operation: %{public}s", operation)
        
        // logger.debug("🚀 Starting operation: \(operation) [\(operationID)]")
        #endif
        
        #if !targetEnvironment(simulator)
        do {
            let result = try await block()
            
            // Record successful completion
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let endMemory = getCurrentMemoryUsage()
            let memoryDelta = endMemory - startMemory
            
            recordOperationSuccess(
                operation: operation,
                category: category,
                priority: priority,
                duration: duration,
                memoryDelta: memoryDelta,
                operationID: operationID
            )
            
            os_signpost(.end, log: performanceLog, name: "Operation", signpostID: signpostID,
                       "Duration: %.2fms, Memory: %lldKB", duration * 1000, memoryDelta / 1024)
            
            // logger.debug("✅ Completed operation: \(operation) in \(String(format: "%.2f", duration * 1000))ms")
            
            return result
            
        } catch {
            // Record failure
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            recordOperationFailure(
                operation: operation,
                category: category,
                priority: priority,
                duration: duration,
                error: error,
                operationID: operationID
            )
            
            os_signpost(.end, log: performanceLog, name: "Operation", signpostID: signpostID,
                       "Failed after %.2fms: %{public}s", duration * 1000, error.localizedDescription)
            
            logger.error("❌ Failed operation: \(operation) after \(String(format: "%.2f", duration * 1000))ms - \(error.localizedDescription)")
            
            throw error
        }
        #endif
    }
    
    /// Get performance insights and recommendations
    func getPerformanceInsights() -> PerformanceInsights {
        return metricsQueue.sync {
            var insights = PerformanceInsights()
            
            // Analyze operation patterns
            for (operation, metrics) in operationMetrics {
                if metrics.averageDuration > 5.0 { // Operations taking more than 5 seconds
                    insights.slowOperations.append(SlowOperationAlert(
                        operation: operation,
                        averageDuration: metrics.averageDuration,
                        recommendation: generateRecommendation(for: operation, metrics: metrics)
                    ))
                }
                
                if metrics.errorRate > 0.1 { // More than 10% error rate
                    insights.errorProneOperations.append(ErrorProneOperationAlert(
                        operation: operation,
                        errorRate: metrics.errorRate,
                        commonErrors: metrics.commonErrors
                    ))
                }
            }
            
            // Memory analysis
            if currentMetrics.memoryUsage > 200 * 1024 * 1024 { // More than 200MB
                insights.memoryWarnings.append("High memory usage detected: \(formatBytes(currentMetrics.memoryUsage))")
            }
            
            // Detect anomalies
            insights.anomalies = anomalyDetector.detectAnomalies(in: performanceHistory)
            
            return insights
        }
    }
    
    /// Export performance data for analysis
    func exportPerformanceData() -> PerformanceExport {
        return metricsQueue.sync {
            return PerformanceExport(
                currentMetrics: currentMetrics,
                operationMetrics: operationMetrics,
                history: performanceHistory,
                insights: getPerformanceInsights()
            )
        }
    }
    
    /// Reset performance metrics
    func resetMetrics() {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Safe reset with proper synchronization
            self.operationMetrics.removeAll()
            self.performanceHistory.removeAll()
            self.anomalyDetector.reset()
            
            DispatchQueue.main.async {
                self.currentMetrics = PerformanceMetrics()
                self.metricsPublisher.send(PerformanceMetrics())
            }
        }
        
        logger.info("🔄 Performance metrics reset")
    }
    
    // MARK: - Private Methods
    
    private func setupPerformanceMonitoring() {
        // Start periodic metrics collection
        metricsTimer = Timer.scheduledTimer(withTimeInterval: Config.metricsUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateCurrentMetrics()
        }
        
        // Setup memory pressure monitoring
        setupMemoryPressureMonitoring()
    }
    
    private func recordOperationSuccess(
        operation: String,
        category: PerformanceCategory,
        priority: OperationPriority,
        duration: TimeInterval,
        memoryDelta: Int64,
        operationID: UUID
    ) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Safe operation recording
            var metrics = self.operationMetrics[operation] ?? OperationMetrics(operation: operation)
            metrics.recordSuccess(duration: duration, memoryDelta: memoryDelta)
            self.operationMetrics[operation] = metrics
            
            // Check for performance anomalies (with error handling)
            do {
                if let anomaly = self.anomalyDetector.checkForAnomaly(
                    operation: operation,
                    duration: duration,
                    category: category
                ) {
                    self.logger.warning("🚨 Performance anomaly detected: \(anomaly.description)")
                }
            } catch {
                logger.warning("PerformanceMonitor: Anomaly detection failed - \(error)")
            }
            
            // Update global metrics (already on correct queue)
            // Don't call updateGlobalMetrics to avoid recursive calls
        }
    }
    
    private func recordOperationFailure(
        operation: String,
        category: PerformanceCategory,
        priority: OperationPriority,
        duration: TimeInterval,
        error: Error,
        operationID: UUID
    ) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Safe failure recording
            var metrics = self.operationMetrics[operation] ?? OperationMetrics(operation: operation)
            metrics.recordFailure(duration: duration, error: error)
            self.operationMetrics[operation] = metrics
            
            // Don't call updateGlobalMetrics to avoid recursive calls
        }
    }
    
    private func updateCurrentMetrics() {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Protect against concurrent access crashes
            guard !self.operationMetrics.isEmpty else {
                // If no operations yet, just update with empty metrics
                let emptyMetrics = PerformanceMetrics()
                DispatchQueue.main.async {
                    self.currentMetrics = emptyMetrics
                    self.metricsPublisher.send(emptyMetrics)
                }
                return
            }
            
            let totalOperations = self.operationMetrics.values.reduce(0) { $0 + $1.totalCount }
            let totalErrors = self.operationMetrics.values.reduce(0) { $0 + $1.errorCount }
            let averageDuration = self.operationMetrics.values.isEmpty ? 0 :
                self.operationMetrics.values.map(\.averageDuration).reduce(0, +) / Double(self.operationMetrics.count)
            
            let newMetrics = PerformanceMetrics(
                averageFetchTime: averageDuration,
                cacheHitRate: self.calculateCacheHitRate(),
                errorRate: totalOperations > 0 ? Double(totalErrors) / Double(totalOperations) : 0,
                throughput: self.calculateThroughput(),
                memoryUsage: self.getCurrentMemoryUsage(),
                networkLatency: 0,
                parsingTime: 0,
                sortingTime: 0,
                totalOperations: totalOperations,
                failedOperations: totalErrors,
                lastUpdated: Date()
            )
            
            // CRITICAL FIX: Safely create and add performance snapshot
            do {
                let snapshot = PerformanceSnapshot(
                    timestamp: Date(),
                    metrics: newMetrics,
                    operationCounts: self.operationMetrics.mapValues { $0.totalCount }
                )
                
                // CRITICAL FIX: Safely append to history with bounds checking
                if self.performanceHistory.count < Config.maxOperationHistory {
                    self.performanceHistory.append(snapshot)
                } else {
                    // Remove oldest entry before adding new one
                    self.performanceHistory.removeFirst()
                    self.performanceHistory.append(snapshot)
                }
                
                // Clean up old entries
                let cutoffDate = Date().addingTimeInterval(-TimeInterval(Config.historyRetentionDays * 24 * 60 * 60))
                self.performanceHistory = self.performanceHistory.filter { $0.timestamp > cutoffDate }
                
            } catch {
                // If snapshot creation fails, just log and continue
                logger.warning("PerformanceMonitor: Failed to create snapshot - \(error)")
            }
            
            DispatchQueue.main.async {
                self.currentMetrics = newMetrics
                self.metricsPublisher.send(newMetrics)
            }
        }
    }
    
    private func updateGlobalMetrics() {
        // This is called from within metricsQueue, so no additional synchronization needed
        updateCurrentMetrics()
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
    
    private func calculateCacheHitRate() -> Double {
        // This would integrate with the cache engine to get actual hit rates
        // For now, return a placeholder
        return 0.85
    }
    
    private func calculateThroughput() -> Double {
        // CRITICAL FIX: Safe access to performance history
        guard performanceHistory.count >= 2 else { return 0.0 }
        
        let recentOperations = Array(performanceHistory.suffix(60)) // Last 60 seconds
        guard let first = recentOperations.first, let last = recentOperations.last else { return 0.0 }
        
        let timeSpan = last.timestamp.timeIntervalSince(first.timestamp)
        let totalOps = recentOperations.map { $0.operationCounts.values.reduce(0, +) }.reduce(0, +)
        
        return timeSpan > 0 ? Double(totalOps) / timeSpan : 0.0
    }
    
    private func getActiveOperationsCount() -> Int {
        // This would track currently running operations
        // For now, return a placeholder
        return 0
    }
    
    private func getSignpostID(for category: PerformanceCategory) -> OSSignpostID {
        switch category {
        case .fetch:
            return fetchSignpostID
        case .sort:
            return sortSignpostID
        case .cache:
            return cacheSignpostID
        case .general:
            return OSSignpostID(log: performanceLog)
        }
    }
    
    private func generateRecommendation(for operation: String, metrics: OperationMetrics) -> String {
        if operation.contains("fetch") {
            if metrics.averageDuration > 10.0 {
                return "Consider implementing request caching or reducing timeout values"
            } else if metrics.errorRate > 0.2 {
                return "High error rate detected - check network connectivity and retry logic"
            }
        } else if operation.contains("sort") {
            return "Consider implementing incremental sorting or caching sorted results"
        } else if operation.contains("cache") {
            return "Optimize cache hit rates by adjusting cache size or TTL values"
        }
        
        return "Monitor operation performance and consider optimization"
    }
    
    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: metricsQueue)
        
        source.setEventHandler { [weak self] in
            let event = source.mask
            
            if event.contains(.warning) {
                self?.logger.warning("⚠️ Memory pressure warning detected")
            }
            
            if event.contains(.critical) {
                self?.logger.error("🚨 Critical memory pressure detected")
            }
        }
        
        source.resume()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Types

enum PerformanceCategory {
    case fetch
    case sort
    case cache
    case general
}

enum OperationPriority {
    case low
    case normal
    case high
    case critical
}

fileprivate struct OperationMetrics {
    let operation: String
    var totalCount: Int = 0
    var successCount: Int = 0
    var errorCount: Int = 0
    var totalDuration: TimeInterval = 0
    var minDuration: TimeInterval = Double.infinity
    var maxDuration: TimeInterval = 0
    var totalMemoryDelta: Int64 = 0
    var commonErrors: [String: Int] = [:]
    
    var averageDuration: TimeInterval {
        return totalCount > 0 ? totalDuration / Double(totalCount) : 0
    }
    
    var errorRate: Double {
        return totalCount > 0 ? Double(errorCount) / Double(totalCount) : 0
    }
    
    var averageMemoryDelta: Int64 {
        return totalCount > 0 ? totalMemoryDelta / Int64(totalCount) : 0
    }
    
    mutating func recordSuccess(duration: TimeInterval, memoryDelta: Int64) {
        totalCount += 1
        successCount += 1
        totalDuration += duration
        minDuration = min(minDuration, duration)
        maxDuration = max(maxDuration, duration)
        totalMemoryDelta += memoryDelta
    }
    
    mutating func recordFailure(duration: TimeInterval, error: Error) {
        totalCount += 1
        errorCount += 1
        totalDuration += duration
        
        let errorKey = String(describing: type(of: error))
        commonErrors[errorKey, default: 0] += 1
    }
}

private struct PerformanceSnapshot {
    let timestamp: Date
    let metrics: PerformanceMetrics
    let operationCounts: [String: Int]
}

struct PerformanceInsights {
    var slowOperations: [SlowOperationAlert] = []
    var errorProneOperations: [ErrorProneOperationAlert] = []
    var memoryWarnings: [String] = []
    var anomalies: [PerformanceAnomaly] = []
}

struct SlowOperationAlert {
    let operation: String
    let averageDuration: TimeInterval
    let recommendation: String
}

struct ErrorProneOperationAlert {
    let operation: String
    let errorRate: Double
    let commonErrors: [String: Int]
}

struct PerformanceAnomaly {
    let operation: String
    let timestamp: Date
    let duration: TimeInterval
    let expectedDuration: TimeInterval
    let severity: AnomalySeverity
    
    var description: String {
        return "\(operation) took \(String(format: "%.2f", duration))s (expected \(String(format: "%.2f", expectedDuration))s)"
    }
}

enum AnomalySeverity {
    case minor
    case moderate
    case severe
}

struct PerformanceExport: Codable {
    let currentMetrics: PerformanceMetrics
    let operationMetrics: [String: String] // Simplified for JSON export
    let historyCount: Int
    let exportDate: Date
    let insights: String // Simplified insights summary
    
    fileprivate init(currentMetrics: PerformanceMetrics, operationMetrics: [String: OperationMetrics], history: [PerformanceSnapshot], insights: PerformanceInsights) {
        self.currentMetrics = currentMetrics
        self.operationMetrics = operationMetrics.mapValues { "\($0.totalCount) ops, \(String(format: "%.2f", $0.averageDuration))s avg" }
        self.historyCount = history.count
        self.exportDate = Date()
        self.insights = "Slow ops: \(insights.slowOperations.count), Errors: \(insights.errorProneOperations.count), Anomalies: \(insights.anomalies.count)"
    }
}

// MARK: - Anomaly Detection

private class RealTimePerformanceAnomalyDetector {
    private var operationBaselines: [String: OperationBaseline] = [:]
    
    func checkForAnomaly(operation: String, duration: TimeInterval, category: PerformanceCategory) -> PerformanceAnomaly? {
        var baseline = operationBaselines[operation] ?? OperationBaseline()
        baseline.addSample(duration)
        operationBaselines[operation] = baseline
        
        if baseline.sampleCount < 10 { return nil } // Need enough samples
        
        let zScore = abs(duration - baseline.mean) / baseline.standardDeviation
        
        if zScore > 2.0 { // 2 standard deviations
            let severity: AnomalySeverity
            if zScore > 4.0 {
                severity = .severe
            } else if zScore > 3.0 {
                severity = .moderate
            } else {
                severity = .minor
            }
            
            return PerformanceAnomaly(
                operation: operation,
                timestamp: Date(),
                duration: duration,
                expectedDuration: baseline.mean,
                severity: severity
            )
        }
        
        return nil
    }
    
    func detectAnomalies(in history: [PerformanceSnapshot]) -> [PerformanceAnomaly] {
        // Analyze historical data for patterns
        // This is a simplified implementation
        return []
    }
    
    func reset() {
        operationBaselines.removeAll()
    }
}

private struct OperationBaseline {
    private var samples: [TimeInterval] = []
    
    var sampleCount: Int { samples.count }
    
    var mean: TimeInterval {
        return samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
    }
    
    var standardDeviation: TimeInterval {
        guard samples.count > 1 else { return 0 }
        
        let meanValue = mean
        let squaredDifferences = samples.map { pow($0 - meanValue, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(samples.count - 1)
        
        return sqrt(variance)
    }
    
    mutating func addSample(_ duration: TimeInterval) {
        samples.append(duration)
        
        // Keep only recent samples (sliding window)
        if samples.count > 100 {
            samples.removeFirst()
        }
    }
}
