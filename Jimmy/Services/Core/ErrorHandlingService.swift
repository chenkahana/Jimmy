import Foundation
import OSLog

// MARK: - Error Handling Service
// Centralized error handling and logging for improved maintainability

final class ErrorHandlingService: ErrorHandlingServiceProtocol {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ErrorHandlingService")
    static let shared = ErrorHandlingService()
    
    private let logger = Logger(subsystem: "Jimmy.ErrorHandling", category: "Service")
    private let loggingService = LoggingService.shared
    private let errorQueue = DispatchQueue(label: "jimmy.error.handling", qos: .utility)
    
    // Error tracking
    private var errorCounts: [String: Int] = [:]
    private let maxErrorCount = 10
    private let errorCountResetInterval: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Error Handling
    func handleError(_ error: Error, context: String) {
        logError(error, context: context, userInfo: nil)
        
        // Track error frequency
        trackErrorFrequency(context: context)
        
        // Handle specific error types
        handleSpecificError(error, context: context)
    }
    
    func logError(_ error: Error, context: String, userInfo: [String: Any]?) {
        errorQueue.async { [weak self] in
            self?.performErrorLogging(error, context: context, userInfo: userInfo)
        }
    }
    
    // MARK: - Private Methods
    private func performErrorLogging(_ error: Error, context: String, userInfo: [String: Any]?) {
        let errorMessage = formatErrorMessage(error, context: context, userInfo: userInfo)
        
        // Log to system logger
        logger.error("\(errorMessage)")
        
        // Log through centralized logging service
        loggingService.error(errorMessage, category: .service, userInfo: userInfo)
    }
    
    private func formatErrorMessage(_ error: Error, context: String, userInfo: [String: Any]?) -> String {
        var message = "[\(context)] \(error.localizedDescription)"
        
        if let userInfo = userInfo, !userInfo.isEmpty {
            let userInfoString = userInfo.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            message += " | UserInfo: \(userInfoString)"
        }
        
        return message
    }
    
    private func trackErrorFrequency(context: String) {
        errorCounts[context, default: 0] += 1
        
        // Reset error counts periodically
        DispatchQueue.main.asyncAfter(deadline: .now() + errorCountResetInterval) { [weak self] in
            self?.errorCounts[context] = 0
        }
        
        // Alert if error frequency is too high
        if let count = errorCounts[context], count >= maxErrorCount {
            logger.critical("High error frequency detected in context: \(context) (\(count) errors)")
        }
    }
    
    private func handleSpecificError(_ error: Error, context: String) {
        switch error {
        case let urlError as URLError:
            handleNetworkError(urlError, context: context)
        case let decodingError as DecodingError:
            handleDecodingError(decodingError, context: context)
        default:
            // Generic error handling
            break
        }
    }
    
    private func handleNetworkError(_ error: URLError, context: String) {
        switch error.code {
        case .notConnectedToInternet:
            logger.info("Network unavailable in context: \(context)")
        case .timedOut:
            logger.warning("Network timeout in context: \(context)")
        case .cannotFindHost, .cannotConnectToHost:
            logger.error("Host connection failed in context: \(context)")
        default:
            logger.error("Network error in context: \(context) - \(error.localizedDescription)")
        }
    }
    
    private func handleDecodingError(_ error: DecodingError, context: String) {
        switch error {
        case .keyNotFound(let key, _):
            logger.error("Missing key '\(key.stringValue)' in context: \(context)")
        case .typeMismatch(let type, _):
            logger.error("Type mismatch for \(type) in context: \(context)")
        case .valueNotFound(let type, _):
            logger.error("Value not found for \(type) in context: \(context)")
        case .dataCorrupted:
            logger.error("Data corrupted in context: \(context)")
        @unknown default:
            logger.error("Unknown decoding error in context: \(context)")
        }
    }
    
}

// MARK: - Error Types
enum ServiceError: LocalizedError {
    case notInitialized
    case configurationError(String)
    case dependencyMissing(String)
    case operationFailed(String)
    case timeout
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Service not initialized"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .dependencyMissing(let dependency):
            return "Missing dependency: \(dependency)"
        case .operationFailed(let operation):
            return "Operation failed: \(operation)"
        case .timeout:
            return "Operation timed out"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

// MARK: - Error Context Constants
extension ErrorHandlingService {
    enum Context {
        static let episodeService = "EpisodeService"
        static let networkService = "NetworkService"
        static let databaseService = "DatabaseService"
        static let cacheService = "CacheService"
        static let parsingService = "ParsingService"
        static let playbackService = "PlaybackService"
        static let subscriptionService = "SubscriptionService"
        static let discoveryService = "DiscoveryService"
    }
}