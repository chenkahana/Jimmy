import Foundation
import Network

/// Simple networking utility with retry logic.
enum NetworkError: Error {
    case offline
    case tooManyRetries
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .offline:
            return "No internet connection available"
        case .tooManyRetries:
            return "Maximum retry attempts exceeded"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

final class NetworkManager {
    static let shared = NetworkManager()
    
    private struct Config {
        static let maxRetries = 3
        static let baseRetryDelay: TimeInterval = 1.5
        static let requestTimeout: TimeInterval = 60.0
        static let resourceTimeout: TimeInterval = 120.0
    }

    private init() {}

    /// Fetch data with enhanced retry logic and exponential backoff.
    /// - Parameters:
    ///   - request: The URL request to perform.
    ///   - retries: Number of additional attempts on failure.
    ///   - completion: Completion handler with result.
    func fetchData(with request: URLRequest,
                   retries: Int = Config.maxRetries,
                   completion: @escaping (Result<Data, Error>) -> Void) {
        
        // Check network connectivity first
        guard NetworkMonitor.shared.isConnected else {
            completion(.failure(NetworkError.offline))
            return
        }
        
        // Configure request with proper timeouts
        var enhancedRequest = request
        if enhancedRequest.timeoutInterval <= 0 {
            enhancedRequest.timeoutInterval = Config.requestTimeout
        }
        
        // Add headers for better compatibility
        if enhancedRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            enhancedRequest.setValue("Jimmy/1.0 (iOS Podcast Client)", forHTTPHeaderField: "User-Agent")
        }
        if enhancedRequest.value(forHTTPHeaderField: "Accept") == nil {
            enhancedRequest.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        }
        
        performRequest(enhancedRequest, currentRetry: 0, maxRetries: retries, completion: completion)
    }
    
    private func performRequest(_ request: URLRequest, 
                               currentRetry: Int, 
                               maxRetries: Int, 
                               completion: @escaping (Result<Data, Error>) -> Void) {
        
        // Create session with enhanced configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Config.requestTimeout
        config.timeoutIntervalForResource = Config.resourceTimeout
        config.waitsForConnectivity = false  // Changed to false to prevent hanging
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        // CRITICAL: Use HTTP/1.1 to prevent QUIC protocol violations
        config.httpAdditionalHeaders = ["Connection": "keep-alive"]
        
        let session = URLSession(configuration: config)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            defer {
                session.invalidateAndCancel()
            }
            
            guard let self = self else { return }
            
            // Handle errors
            if let error = error {
                
                // Check if we should retry
                if currentRetry < maxRetries && self.shouldRetryError(error) {
                    let delay = Config.baseRetryDelay * pow(2.0, Double(currentRetry)) // Exponential backoff
                    
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.performRequest(request, currentRetry: currentRetry + 1, maxRetries: maxRetries, completion: completion)
                    }
                } else {
                    // All retries exhausted
                    let finalError = currentRetry >= maxRetries ? NetworkError.tooManyRetries : error
                    completion(.failure(finalError))
                }
                return
            }
            
            // Check HTTP response status
            if let httpResponse = response as? HTTPURLResponse {
                
                // Handle different status codes
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - continue processing
                    break
                case 429, 500...599:
                    // Server errors that might be temporary - retry if possible
                    if currentRetry < maxRetries {
                        let delay = Config.baseRetryDelay * pow(2.0, Double(currentRetry))
                        
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                            self.performRequest(request, currentRetry: currentRetry + 1, maxRetries: maxRetries, completion: completion)
                        }
                        return
                    } else {
                        completion(.failure(NetworkError.invalidResponse))
                        return
                    }
                case 400...499:
                    // Client errors - don't retry
                    completion(.failure(NetworkError.invalidResponse))
                    return
                default:
                    // Other status codes - don't retry
                    completion(.failure(NetworkError.invalidResponse))
                    return
                }
            }
            
            // Validate data
            guard let data = data, !data.isEmpty else {
                if currentRetry < maxRetries {
                    let delay = Config.baseRetryDelay * pow(2.0, Double(currentRetry))
                    
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.performRequest(request, currentRetry: currentRetry + 1, maxRetries: maxRetries, completion: completion)
                    }
                } else {
                    completion(.failure(NetworkError.invalidResponse))
                }
                return
            }
            
            // Success
            completion(.success(data))
            
        }.resume()
    }
    
    private func shouldRetryError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Retry on network-related errors
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive,
             NSURLErrorDataNotAllowed,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }
}
