import Foundation
import OSLog
import Network

/// High-performance network manager with aggressive caching and background processing
final class OptimizedNetworkManager {
    static let shared = OptimizedNetworkManager()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "optimized-network")
    
    // MARK: - Configuration
    fileprivate struct Config {
        static let maxConcurrentRequests = 6
        static let requestTimeout: TimeInterval = 45.0  // Increased from 30s
        static let resourceTimeout: TimeInterval = 90.0  // Increased from 60s
        static let cacheExpiry: TimeInterval = 15 * 60 // 15 minutes
        static let backgroundQueueQoS: DispatchQoS = .utility
        static let maxCacheSize = 50 // Maximum cached responses
        static let maxRetries = 3  // Maximum retry attempts
        static let baseRetryDelay: TimeInterval = 2.0  // Base delay for exponential backoff
    }
    
    // MARK: - Properties
    private let backgroundQueue = DispatchQueue(label: "optimized-network", qos: Config.backgroundQueueQoS, attributes: .concurrent)
    private let cacheQueue = DispatchQueue(label: "network-cache", qos: .utility)
    private let semaphore = DispatchSemaphore(value: Config.maxConcurrentRequests)
    
    // Advanced caching system
    private var responseCache: [String: CachedResponse] = [:]
    private var requestQueue: [String: [(Result<Data, Error>) -> Void]] = [:]
    private var activeRequests: Set<String> = []
    private var retryAttempts: [String: Int] = [:]
    
    // URLSession with optimized configuration
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024) // 20MB memory, 100MB disk
        config.timeoutIntervalForRequest = Config.requestTimeout
        config.timeoutIntervalForResource = Config.resourceTimeout
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }()
    
    private init() {
        setupCacheCleanup()
    }
    
    // MARK: - Public Interface
    
    /// Fetch RSS feed data with aggressive caching and background processing
    func fetchRSSFeed(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        let cacheKey = url.absoluteString
        
        // Check cache first (immediate return if available)
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let cachedResponse = self.responseCache[cacheKey], !cachedResponse.isExpired {
                Task { @MainActor in
                    completion(.success(cachedResponse.data))
                }
                return
            }
            
            // Check if request is already in progress
            if self.activeRequests.contains(cacheKey) {
                // Queue the completion handler
                if self.requestQueue[cacheKey] != nil {
                    self.requestQueue[cacheKey]?.append(completion)
                } else {
                    self.requestQueue[cacheKey] = [completion]
                }
                return
            }
            
            // Mark request as active and reset retry count
            self.activeRequests.insert(cacheKey)
            self.retryAttempts[cacheKey] = 0
            
            // Perform network request in background
            self.performNetworkRequestWithRetry(url: url, cacheKey: cacheKey, completion: completion)
        }
    }
    
    /// Prefetch RSS feeds in background for better performance
    func prefetchRSSFeeds(urls: [URL]) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            for url in urls {
                let cacheKey = url.absoluteString
                
                // Skip if already cached or in progress
                if self.responseCache[cacheKey]?.isExpired == false || self.activeRequests.contains(cacheKey) {
                    continue
                }
                
                self.fetchRSSFeed(url: url) { _ in
                    // Prefetch - we don't need to handle the result
                }
                
                // Small delay to prevent overwhelming the server - use Task.sleep for non-blocking delay
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
        }
    }
    
    /// Clear expired cache entries
    func clearExpiredCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let expiredKeys = self.responseCache.compactMap { key, value in
                value.isExpired ? key : nil
            }
            
            for key in expiredKeys {
                self.responseCache.removeValue(forKey: key)
            }
            
            self.logger.info("Cleared \(expiredKeys.count) expired cache entries")
        }
    }
    
    /// Get cache statistics
    func getCacheStats() -> (count: Int, memoryUsage: Int) {
        var count = 0
        var memoryUsage = 0
        
        cacheQueue.sync {
            count = responseCache.count
            memoryUsage = responseCache.values.reduce(0) { $0 + $1.data.count }
        }
        
        return (count: count, memoryUsage: memoryUsage)
    }
    
    // MARK: - Private Methods
    
    private func performNetworkRequestWithRetry(url: URL, cacheKey: String, completion: @escaping (Result<Data, Error>) -> Void) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Acquire semaphore to limit concurrent requests
            self.semaphore.wait()
            
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData // We handle caching ourselves
            request.setValue("Jimmy/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
            request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            
            let task = self.urlSession.dataTask(with: request) { [weak self] data, response, error in
                defer {
                    self?.semaphore.signal()
                }
                
                guard let self = self else { return }
                
                if let error = error {
                    self.handleNetworkError(error: error, url: url, cacheKey: cacheKey, completion: completion)
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    let error = NSError(domain: "OptimizedNetworkManager", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Empty response",
                        NSLocalizedRecoverySuggestionErrorKey: "The podcast feed returned no data. The feed may be temporarily unavailable."
                    ])
                    self.handleNetworkError(error: error, url: url, cacheKey: cacheKey, completion: completion)
                    return
                }
                
                // Validate RSS/XML content
                if let dataString = String(data: data, encoding: .utf8) {
                    if !dataString.contains("<rss") && !dataString.contains("<feed") && !dataString.contains("<?xml") {
                        let error = NSError(domain: "OptimizedNetworkManager", code: -2, userInfo: [
                            NSLocalizedDescriptionKey: "Invalid RSS/XML format",
                            NSLocalizedRecoverySuggestionErrorKey: "The response is not a valid RSS feed. The URL may be incorrect or the podcast may have moved."
                        ])
                        self.handleNetworkError(error: error, url: url, cacheKey: cacheKey, completion: completion)
                        return
                    }
                }
                
                // Success - cache and notify
                self.handleSuccessfulResponse(data: data, cacheKey: cacheKey)
            }
            
            task.resume()
        }
    }
    
    private func handleNetworkError(error: Error, url: URL, cacheKey: String, completion: @escaping (Result<Data, Error>) -> Void) {
        let currentAttempt = retryAttempts[cacheKey] ?? 0
        
        // Check if we should retry
        if currentAttempt < Config.maxRetries && shouldRetryError(error) {
            retryAttempts[cacheKey] = currentAttempt + 1
            let delay = Config.baseRetryDelay * pow(2.0, Double(currentAttempt)) // Exponential backoff
            
            logger.warning("Network request failed (attempt \(currentAttempt + 1)/\(Config.maxRetries + 1)): \(error.localizedDescription). Retrying in \(delay)s")
            
            // Retry after delay
            backgroundQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.performNetworkRequestWithRetry(url: url, cacheKey: cacheKey, completion: completion)
            }
        } else {
            // All retries exhausted, try fallback
            logger.error("All retry attempts exhausted. Attempting fallback request.")
            attemptFallbackRequest(url: url, cacheKey: cacheKey, completion: completion)
        }
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
             NSURLErrorDataNotAllowed:
            return true
        default:
            // Don't retry on client errors (4xx) or server errors that are unlikely to resolve
            if let httpResponse = error as? URLError,
               let statusCode = (httpResponse.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)?.contains("4") {
                return false
            }
            return true
        }
    }
    
    private func handleSuccessfulResponse(data: Data, cacheKey: String) {
        // Cache successful response
        let cachedResponse = CachedResponse(data: data, timestamp: Date())
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.responseCache[cacheKey] = cachedResponse
            self.clearExpiredCache()
        }
        
        // Clean up retry tracking
        retryAttempts.removeValue(forKey: cacheKey)
        
        // Notify all waiters
        notifyAllWaiters(cacheKey: cacheKey, result: .success(data))
        cleanupRequest(cacheKey: cacheKey)
    }
    
    private func notifyAllWaiters(cacheKey: String, result: Result<Data, Error>) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Notify all queued completion handlers
            if let queuedCompletions = self.requestQueue[cacheKey] {
                for completion in queuedCompletions {
                    completion(result)
                }
                self.requestQueue.removeValue(forKey: cacheKey)
            }
        }
    }
    
    private func cleanupRequest(cacheKey: String) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.activeRequests.remove(cacheKey)
            self.retryAttempts.removeValue(forKey: cacheKey)
        }
    }
    
    private func removeOldestCacheEntry() {
        guard let oldestKey = responseCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key else { return }
        responseCache.removeValue(forKey: oldestKey)
    }
    
    private func setupCacheCleanup() {
        // Clean up expired cache entries every 10 minutes
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.clearExpiredCache()
        }
    }
    
    // MARK: - Enhanced Fallback Network Request
    
    private func attemptFallbackRequest(url: URL, cacheKey: String, completion: @escaping (Result<Data, Error>) -> Void) {
        logger.info("Attempting fallback request for: \(url.absoluteString)")
        
        // Create multiple fallback configurations to try
        let fallbackConfigs = createFallbackConfigurations()
        
        attemptFallbackWithConfigs(url: url, cacheKey: cacheKey, configs: fallbackConfigs, configIndex: 0, completion: completion)
    }
    
    private func createFallbackConfigurations() -> [URLSessionConfiguration] {
        var configs: [URLSessionConfiguration] = []
        
        // Config 1: Simple with longer timeout
        let config1 = URLSessionConfiguration.default
        config1.timeoutIntervalForRequest = 90.0
        config1.timeoutIntervalForResource = 180.0
        config1.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config1.urlCache = nil
        config1.waitsForConnectivity = true
        configs.append(config1)
        
        // Config 2: Ephemeral session (no caching, no cookies)
        let config2 = URLSessionConfiguration.ephemeral
        config2.timeoutIntervalForRequest = 120.0
        config2.timeoutIntervalForResource = 240.0
        config2.waitsForConnectivity = true
        configs.append(config2)
        
        // Config 3: Background session for persistent downloads
        let config3 = URLSessionConfiguration.default
        config3.timeoutIntervalForRequest = 150.0
        config3.timeoutIntervalForResource = 300.0
        config3.allowsCellularAccess = true
        config3.allowsExpensiveNetworkAccess = true
        config3.allowsConstrainedNetworkAccess = true
        config3.waitsForConnectivity = true
        configs.append(config3)
        
        return configs
    }
    
    private func attemptFallbackWithConfigs(url: URL, cacheKey: String, configs: [URLSessionConfiguration], configIndex: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        guard configIndex < configs.count else {
            // All fallback attempts failed
            let finalError = NSError(domain: "OptimizedNetworkManager", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "All network attempts failed",
                NSLocalizedRecoverySuggestionErrorKey: "Unable to connect to the podcast feed. Please check your internet connection and try again later."
            ])
            notifyAllWaiters(cacheKey: cacheKey, result: .failure(finalError))
            cleanupRequest(cacheKey: cacheKey)
            return
        }
        
        let config = configs[configIndex]
        let session = URLSession(configuration: config)
        
        var request = URLRequest(url: url)
        // Try different User-Agent strings
        let userAgents = [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "Jimmy/1.0 (iOS Podcast Client)",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        ]
        request.setValue(userAgents[configIndex % userAgents.count], forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        
        logger.info("Trying fallback config \(configIndex + 1)/\(configs.count)")
        
        session.dataTask(with: request) { [weak self] data, response, error in
            defer {
                session.invalidateAndCancel()
            }
            
            guard let self = self else { return }
            
            if let error = error {
                self.logger.warning("Fallback config \(configIndex + 1) failed: \(error.localizedDescription)")
                // Try next configuration
                self.attemptFallbackWithConfigs(url: url, cacheKey: cacheKey, configs: configs, configIndex: configIndex + 1, completion: completion)
                return
            }
            
            guard let data = data, !data.isEmpty else {
                self.logger.warning("Fallback config \(configIndex + 1) returned empty data")
                // Try next configuration
                self.attemptFallbackWithConfigs(url: url, cacheKey: cacheKey, configs: configs, configIndex: configIndex + 1, completion: completion)
                return
            }
            
            self.logger.info("✅ Fallback config \(configIndex + 1) succeeded: \(data.count) bytes")
            
            // Success - handle the response
            self.handleSuccessfulResponse(data: data, cacheKey: cacheKey)
        }.resume()
    }
}

// MARK: - Supporting Types

private struct CachedResponse {
    let data: Data
    let timestamp: Date
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > OptimizedNetworkManager.Config.cacheExpiry
    }
} 