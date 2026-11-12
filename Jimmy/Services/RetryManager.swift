import Foundation

/// Centralized retry manager with exponential backoff
/// Implements Phase 6 requirement: "Retry with exponential backoff (max 3)"
final class RetryManager {
    static let shared = RetryManager()
    private struct Config {
        static let maxRetries = 3
        static let baseDelay: TimeInterval = 1.0
        static let maxDelay: TimeInterval = 30.0
        static let backoffMultiplier: Double = 2.0
    }
    
    private init() {}
    
    /// Execute an operation with exponential backoff retry
    /// - Parameters:
    ///   - operation: The async operation to retry
    ///   - maxRetries: Maximum number of retries (default: 3)
    ///   - shouldRetry: Closure to determine if error should be retried
    /// - Returns: Result of the operation
    func executeWithRetry<T>(
        operation: @escaping () async throws -> T,
        maxRetries: Int = Config.maxRetries,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                let result = try await operation()
                if attempt > 0 {
                }
                return result
            } catch {
                lastError = error
                
                // Don't retry on last attempt or if error shouldn't be retried
                if attempt == maxRetries || !shouldRetry(error) {
                    break
                }
                
                // Calculate delay with exponential backoff
                let delay = min(
                    Config.baseDelay * pow(Config.backoffMultiplier, Double(attempt)),
                    Config.maxDelay
                )
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // All retries exhausted
        throw lastError ?? RetryError.maxAttemptsExceeded
    }
    
    /// Determine if a network error should be retried
    nonisolated static func shouldRetryNetworkError(_ error: Error) -> Bool {
        // Don't retry 304 Not Modified - it's a success case indicating cached data is valid
        // Don't retry 304 Not Modified (represented as cancelled in UnifiedNetworkService)
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return false
        }
        
        let nsError = error as NSError
        
        // Retry on temporary network errors
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotLoadFromNetwork:
            return true
        default:
            // Check HTTP status codes
            if let httpError = error as? HTTPError {
                switch httpError.statusCode {
                case 429, 500...599: // Rate limit and server errors
                    return true
                default:
                    return false
                }
            }
            return false
        }
    }
}

// MARK: - Error Types

enum RetryError: LocalizedError {
    case maxAttemptsExceeded
    
    var errorDescription: String? {
        switch self {
        case .maxAttemptsExceeded:
            return "Maximum retry attempts exceeded"
        }
    }
}

struct HTTPError: Error {
    let statusCode: Int
    let message: String?
    
    var localizedDescription: String {
        return message ?? "HTTP Error \(statusCode)"
    }
} 