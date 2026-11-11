import Foundation
import OSLog
import Darwin.Mach

// MARK: - Logging Service
// Centralized logging service with structured logging and performance monitoring

final class LoggingService {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LoggingService")
    static let shared = LoggingService()
    
    private let logger = Logger(subsystem: "Jimmy.App", category: "General")
    private let performanceLogger = Logger(subsystem: "Jimmy.Performance", category: "Metrics")
    private let networkLogger = Logger(subsystem: "Jimmy.Network", category: "Requests")
    private let databaseLogger = Logger(subsystem: "Jimmy.Database", category: "Operations")
    
    private let loggingQueue = DispatchQueue(label: "jimmy.logging", qos: .utility)
    
    // Performance tracking
    private var performanceMetrics: [String: PerformanceMetric] = [:]
    private let metricsLock = NSLock()
    
    private init() {}
    
    // MARK: - General Logging
    func debug(_ message: String, category: LogCategory = .general, userInfo: [String: Any]? = nil) {
        log(level: .debug, message: message, category: category, userInfo: userInfo)
    }
    
    func info(_ message: String, category: LogCategory = .general, userInfo: [String: Any]? = nil) {
        log(level: .info, message: message, category: category, userInfo: userInfo)
    }
    
    func warning(_ message: String, category: LogCategory = .general, userInfo: [String: Any]? = nil) {
        log(level: .default, message: message, category: category, userInfo: userInfo)
    }
    
    func error(_ message: String, category: LogCategory = .general, userInfo: [String: Any]? = nil) {
        log(level: .error, message: message, category: category, userInfo: userInfo)
    }
    
    func critical(_ message: String, category: LogCategory = .general, userInfo: [String: Any]? = nil) {
        log(level: .fault, message: message, category: category, userInfo: userInfo)
    }
    
    // MARK: - Performance Logging
    func startPerformanceTracking(for operation: String) -> PerformanceTracker {
        let tracker = PerformanceTracker(operation: operation, startTime: Date())
        
        metricsLock.lock()
        performanceMetrics[operation] = PerformanceMetric(
            operation: operation,
            startTime: tracker.startTime,
            endTime: nil,
            duration: 0,
            memoryUsage: getCurrentMemoryUsage()
        )
        metricsLock.unlock()
        
        return tracker
    }
    
    func endPerformanceTracking(_ tracker: PerformanceTracker) {
        let endTime = Date()
        let duration = endTime.timeIntervalSince(tracker.startTime)
        
        metricsLock.lock()
        if var metric = performanceMetrics[tracker.operation] {
            metric.endTime = endTime
            metric.duration = duration
            performanceMetrics[tracker.operation] = metric
        }
        metricsLock.unlock()
        
        performanceLogger.info("Performance: \(tracker.operation) completed in \(String(format: "%.2f", duration * 1000))ms")
        
        // Log slow operations
        if duration > 1.0 {
            performanceLogger.warning("Slow operation detected: \(tracker.operation) took \(String(format: "%.2f", duration))s")
        }
    }
    
    // MARK: - Network Logging
    func logNetworkRequest(url: URL, method: String, statusCode: Int? = nil, duration: TimeInterval? = nil) {
        var message = "Network: \(method) \(url.absoluteString)"
        
        if let statusCode = statusCode {
            message += " -> \(statusCode)"
        }
        
        if let duration = duration {
            message += " (\(String(format: "%.2f", duration * 1000))ms)"
        }
        
        networkLogger.info("\(message)")
    }
    
    func logNetworkError(url: URL, method: String, error: Error) {
        networkLogger.error("Network Error: \(method) \(url.absoluteString) - \(error.localizedDescription)")
    }
    
    // MARK: - Database Logging
    func logDatabaseOperation(_ operation: String, table: String? = nil, duration: TimeInterval? = nil) {
        var message = "Database: \(operation)"
        
        if let table = table {
            message += " on \(table)"
        }
        
        if let duration = duration {
            message += " (\(String(format: "%.2f", duration * 1000))ms)"
        }
        
        databaseLogger.info("\(message)")
    }
    
    func logDatabaseError(_ operation: String, table: String? = nil, error: Error) {
        var message = "Database Error: \(operation)"
        
        if let table = table {
            message += " on \(table)"
        }
        
        message += " - \(error.localizedDescription)"
        
        databaseLogger.error("\(message)")
    }
    
    // MARK: - Private Methods
    private func log(level: OSLogType, message: String, category: LogCategory, userInfo: [String: Any]?) {
        loggingQueue.async { [weak self] in
            self?.performLogging(level: level, message: message, category: category, userInfo: userInfo)
        }
    }
    
    private func performLogging(level: OSLogType, message: String, category: LogCategory, userInfo: [String: Any]?) {
        let loggerToUse = getLogger(for: category)
        var fullMessage = message
        
        if let userInfo = userInfo, !userInfo.isEmpty {
            let userInfoString = userInfo.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            fullMessage += " | \(userInfoString)"
        }
        
        loggerToUse.log(level: level, "\(fullMessage)")
        
        // Also log to console in debug mode
        #if DEBUG
        let levelString = logLevelString(for: level)
        let categoryString = category.rawValue.uppercased()
        logger.debug("[\(levelString)] [\(categoryString)] \(fullMessage)")
        #endif
    }
    
    private func getLogger(for category: LogCategory) -> Logger {
        switch category {
        case .general:
            return logger
        case .performance:
            return performanceLogger
        case .network:
            return networkLogger
        case .database:
            return databaseLogger
        case .service:
            return logger
        case .ui:
            return logger
        }
    }
    
    private func logLevelString(for level: OSLogType) -> String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .default:
            return "WARNING"
        case .error:
            return "ERROR"
        case .fault:
            return "CRITICAL"
        default:
            return "UNKNOWN"
        }
    }
    
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
    
    // MARK: - Metrics Retrieval
    func getPerformanceMetrics() -> [PerformanceMetric] {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        
        return Array(performanceMetrics.values)
    }
    
    func clearPerformanceMetrics() {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        
        performanceMetrics.removeAll()
    }
}

// MARK: - Supporting Types

enum LogCategory: String, CaseIterable {
    case general = "general"
    case performance = "performance"
    case network = "network"
    case database = "database"
    case service = "service"
    case ui = "ui"
}

struct PerformanceTracker {
    let operation: String
    let startTime: Date
}

struct PerformanceMetric {
    let operation: String
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval
    let memoryUsage: UInt64
}

// MARK: - Convenience Extensions

extension LoggingService {
    func logServiceOperation(_ service: String, operation: String, duration: TimeInterval? = nil) {
        var message = "Service: \(service).\(operation)"
        
        if let duration = duration {
            message += " (\(String(format: "%.2f", duration * 1000))ms)"
        }
        
        info(message, category: .service)
    }
    
    func logServiceError(_ service: String, operation: String, error: Error) {
        let message = "Service Error: \(service).\(operation) - \(error.localizedDescription)"
        self.error(message, category: .service)
    }
    
    func logUIEvent(_ event: String, screen: String? = nil) {
        var message = "UI: \(event)"
        
        if let screen = screen {
            message += " on \(screen)"
        }
        
        info(message, category: .ui)
    }
}