import Foundation
import Network

/// Service for diagnosing network connectivity issues
/// Helps troubleshoot TCP connection problems and provides detailed error reporting
final class NetworkDiagnosticService {
    static let shared = NetworkDiagnosticService()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkDiagnostic")
    
    private init() {
        startMonitoring()
    }
    
    // MARK: - Network Monitoring
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.logNetworkStatus(path)
        }
        monitor.start(queue: queue)
    }
    
    private func logNetworkStatus(_ path: NWPath) {
        let status = path.status
        let isExpensive = path.isExpensive
        let isConstrained = path.isConstrained
        // Log available interfaces
        for interface in path.availableInterfaces {
        }
        
        if status != .satisfied {
        }
    }
    
    // MARK: - Connection Testing
    
    /// Tests connectivity to a specific host
    /// - Parameters:
    ///   - host: Host to test (e.g., "example.com")
    ///   - port: Port to test (default: 80)
    /// - Returns: Connection test result
    func testConnection(to host: String, port: UInt16 = 80) async -> ConnectionTestResult {
        
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .http,
                using: .tcp
            )
            
            var hasResumed = false
            
            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }
                
                switch state {
                case .ready:
                    hasResumed = true
                    continuation.resume(returning: .success(duration: 0)) // TODO: Measure actual duration
                    connection.cancel()
                    
                case .failed(let error):
                    hasResumed = true
                    continuation.resume(returning: .failure(error))
                    connection.cancel()
                    
                case .cancelled:
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: .cancelled)
                    }
                    
                default:
                    break
                }
            }
            
            connection.start(queue: queue)
            
            // Set a timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: .timeout)
                    connection.cancel()
                }
            }
        }
    }
    
    /// Tests RSS feed connectivity specifically
    /// - Parameter feedURL: RSS feed URL to test
    /// - Returns: Detailed diagnostic result
    func diagnoseFeedConnectivity(_ feedURL: URL) async -> FeedDiagnosticResult {
        
        guard let host = feedURL.host else {
            return .invalidURL
        }
        
        let port: UInt16 = {
            if let portNumber = feedURL.port {
                return UInt16(portNumber)
            }
            return feedURL.scheme?.lowercased() == "https" ? 443 : 80
        }()
        
        // Test basic connectivity
        let connectionResult = await testConnection(to: host, port: port)
        
        switch connectionResult {
        case .success:
            // If basic connection works, test HTTP request
            return await testHTTPRequest(feedURL)
        case .failure(let error):
            return .connectionFailed(error)
        case .timeout:
            return .connectionTimeout
        case .cancelled:
            return .connectionCancelled
        }
    }
    
    private func testHTTPRequest(_ url: URL) async -> FeedDiagnosticResult {
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10.0
            config.timeoutIntervalForResource = 15.0
            
            let session = URLSession(configuration: config)
            
            var request = URLRequest(url: url, timeoutInterval: 10.0)
            request.httpMethod = "HEAD" // Use HEAD to avoid downloading content
            request.setValue("Jimmy/2.0 (iOS Podcast Client)", forHTTPHeaderField: "User-Agent")
            
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                
                if (200...299).contains(httpResponse.statusCode) {
                    return .httpSuccess(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields)
                } else {
                    return .httpError(statusCode: httpResponse.statusCode)
                }
            } else {
                return .invalidResponse
            }
            
        } catch {
            return .httpRequestFailed(error)
        }
    }
    
    // MARK: - Error Analysis
    
    /// Analyzes an error and provides diagnostic information
    /// - Parameter error: Error to analyze
    /// - Returns: Diagnostic information
    func analyzeError(_ error: Error) -> ErrorDiagnostic {
        if let urlError = error as? URLError {
            return analyzeURLError(urlError)
        } else {
            return ErrorDiagnostic(
                category: .unknown,
                description: error.localizedDescription,
                isRetryable: false,
                suggestedAction: "Try again later"
            )
        }
    }
    
    private func analyzeURLError(_ error: URLError) -> ErrorDiagnostic {
        switch error.code {
        case .timedOut:
            return ErrorDiagnostic(
                category: .timeout,
                description: "Request timed out",
                isRetryable: true,
                suggestedAction: "Check network connection and try again"
            )
            
        case .cannotConnectToHost:
            return ErrorDiagnostic(
                category: .connectionFailed,
                description: "Cannot connect to server",
                isRetryable: true,
                suggestedAction: "Check if the server is accessible and try again"
            )
            
        case .networkConnectionLost:
            return ErrorDiagnostic(
                category: .connectionLost,
                description: "Network connection was lost",
                isRetryable: true,
                suggestedAction: "Check network connection and try again"
            )
            
        case .notConnectedToInternet:
            return ErrorDiagnostic(
                category: .noInternet,
                description: "No internet connection",
                isRetryable: true,
                suggestedAction: "Connect to the internet and try again"
            )
            
        default:
            return ErrorDiagnostic(
                category: .networkError,
                description: error.localizedDescription,
                isRetryable: false,
                suggestedAction: "Try again later"
            )
        }
    }
    
}

// MARK: - Supporting Types

enum ConnectionTestResult {
    case success(duration: TimeInterval)
    case failure(Error)
    case timeout
    case cancelled
}

enum FeedDiagnosticResult {
    case invalidURL
    case connectionFailed(Error)
    case connectionTimeout
    case connectionCancelled
    case httpSuccess(statusCode: Int, headers: [AnyHashable: Any])
    case httpError(statusCode: Int)
    case httpRequestFailed(Error)
    case invalidResponse
    
    var isSuccessful: Bool {
        if case .httpSuccess = self {
            return true
        }
        return false
    }
    
    var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .connectionTimeout:
            return "Connection timed out"
        case .connectionCancelled:
            return "Connection was cancelled"
        case .httpSuccess(let statusCode, _):
            return "HTTP success: \(statusCode)"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .httpRequestFailed(let error):
            return "HTTP request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response"
        }
    }
}

struct ErrorDiagnostic {
    let category: ErrorCategory
    let description: String
    let isRetryable: Bool
    let suggestedAction: String
}

enum ErrorCategory {
    case timeout
    case connectionFailed
    case connectionLost
    case noInternet
    case networkError
    case httpError
    case parsingError
    case unknown
}

// MARK: - Extensions

extension NWPath.Status {
    var description: String {
        switch self {
        case .satisfied:
            return "satisfied"
        case .unsatisfied:
            return "unsatisfied"
        case .requiresConnection:
            return "requires connection"
        @unknown default:
            return "unknown"
        }
    }
}

extension NWInterface.InterfaceType {
    var description: String {
        switch self {
        case .wifi:
            return "WiFi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        case .other:
            return "Other"
        @unknown default:
            return "Unknown"
        }
    }
} 