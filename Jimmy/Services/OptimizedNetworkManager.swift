import Foundation
import OSLog
import Network

// MARK: - Network Errors
enum FetchError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(statusCode: Int)
    case emptyData
    case decodingFailed(Error)
    case timeout
    case allRetriesFailed
    case nonRetryableError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The provided URL is invalid."
        case .requestFailed(let error): return "Network request failed: \(error.localizedDescription)"
        case .invalidResponse(let statusCode): return "Received an invalid server response: \(statusCode)"
        case .emptyData: return "The server returned no data."
        case .decodingFailed(let error): return "Failed to decode the response: \(error.localizedDescription)"
        case .timeout: return "The request timed out."
        case .allRetriesFailed: return "All retry attempts for the network request have failed."
        case .nonRetryableError(let statusCode): return "Request failed with a non-retryable status code: \(statusCode)."
        }
    }
}

/// High-performance network manager with aggressive caching and background processing
final class OptimizedNetworkManager {
    static let shared = OptimizedNetworkManager()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "optimized-network")
    
    // MARK: - Configuration
    fileprivate struct Config {
        static let maxConcurrentRequests = 6
        static let requestTimeout: TimeInterval = 45.0
        static let resourceTimeout: TimeInterval = 90.0
        static let cacheExpiry: TimeInterval = 15 * 60 // 15 minutes
        static let backgroundQueueQoS: DispatchQoS = .utility
        static let maxCacheSize = 50
        static let maxRetries = 3
        static let baseRetryDelay: TimeInterval = 2.0
    }
    
    // MARK: - Properties
    private let backgroundQueue = DispatchQueue(label: "optimized-network", qos: Config.backgroundQueueQoS, attributes: .concurrent)
    private let cacheQueue = DispatchQueue(label: "network-cache", qos: .utility)
    private let semaphore = DispatchSemaphore(value: Config.maxConcurrentRequests)
    
    private var responseCache: [String: CachedResponse] = [:]
    private var requestQueue: [String: [(Result<Data, Error>) -> Void]] = [:]
    private var activeRequests: Set<String> = []
    private var retryAttempts: [String: Int] = [:]
    
    private lazy var ephemeralSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Config.requestTimeout
        config.timeoutIntervalForResource = Config.resourceTimeout
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - Public Interface
    
    func fetch<T: Decodable>(
        url: URL,
        as type: T.Type,
        timeout: TimeInterval = Config.requestTimeout,
        retries: Int = Config.maxRetries,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await fetchData(url: url, timeout: timeout, retries: retries)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding failed for \(url.absoluteString): \(error.localizedDescription)")
            throw FetchError.decodingFailed(error)
        }
    }
    
    func fetchData(url: URL, timeout: TimeInterval = Config.requestTimeout, retries: Int = Config.maxRetries) async throws -> Data {
        var lastError: Error?
        let requestID = UUID().uuidString.prefix(8)

        for attempt in 0...retries {
            do {
                var request = URLRequest(url: url, timeoutInterval: timeout)
                request.setValue("Jimmy/2.0 (iOS Podcast Client)", forHTTPHeaderField: "User-Agent")
                
                logger.info("[\(requestID)] Attempt \(attempt + 1)/\(retries + 1) fetching URL: \(url.absoluteString)")

                let (data, response) = try await ephemeralSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FetchError.invalidResponse(statusCode: -1)
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    if (400...499).contains(httpResponse.statusCode) {
                        logger.error("[\(requestID)] Non-retryable HTTP status \(httpResponse.statusCode) for URL: \(url.absoluteString)")
                        throw FetchError.nonRetryableError(statusCode: httpResponse.statusCode)
                    }
                    throw FetchError.invalidResponse(statusCode: httpResponse.statusCode)
                }

                guard !data.isEmpty else { throw FetchError.emptyData }
                return data
            } catch {
                lastError = error
                if let fetchError = error as? FetchError, case .nonRetryableError = fetchError {
                    throw error
                }
                logger.warning("[\(requestID)] Attempt \(attempt + 1) failed for \(url.absoluteString): \(error.localizedDescription)")
                if attempt < retries {
                    try await Task.sleep(nanoseconds: UInt64((Config.baseRetryDelay * pow(2.0, Double(attempt))) * 1_000_000_000))
                }
            }
        }
        logger.error("[\(requestID)] All retries failed for URL \(url.absoluteString). Last error: \(lastError?.localizedDescription ?? "Unknown error")")
        throw lastError ?? FetchError.allRetriesFailed
    }
}

private struct CachedResponse {
    let data: Data
    let timestamp: Date
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > OptimizedNetworkManager.Config.cacheExpiry
    }
}