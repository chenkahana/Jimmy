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
        static let requestTimeout: TimeInterval = 30.0
        static let cacheExpiry: TimeInterval = 15 * 60 // 15 minutes
        static let backgroundQueueQoS: DispatchQoS = .utility
        static let maxCacheSize = 50 // Maximum cached responses
    }
    
    // MARK: - Properties
    private let backgroundQueue = DispatchQueue(label: "optimized-network", qos: Config.backgroundQueueQoS, attributes: .concurrent)
    private let cacheQueue = DispatchQueue(label: "network-cache", qos: .utility)
    private let semaphore = DispatchSemaphore(value: Config.maxConcurrentRequests)
    
    // Advanced caching system
    private var responseCache: [String: CachedResponse] = [:]
    private var requestQueue: [String: [(Result<Data, Error>) -> Void]] = [:]
    private var activeRequests: Set<String> = []
    
    // URLSession with optimized configuration
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024) // 20MB memory, 100MB disk
        config.timeoutIntervalForRequest = Config.requestTimeout
        config.timeoutIntervalForResource = Config.requestTimeout * 2
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
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
            
            // Mark request as active
            self.activeRequests.insert(cacheKey)
            
            // Perform network request in background
            self.performNetworkRequest(url: url, cacheKey: cacheKey, completion: completion)
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
    
    private func performNetworkRequest(url: URL, cacheKey: String, completion: @escaping (Result<Data, Error>) -> Void) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Acquire semaphore to limit concurrent requests
            self.semaphore.wait()
            
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData // We handle caching ourselves
            request.setValue("Jimmy/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
            
            let task = self.urlSession.dataTask(with: request) { [weak self] data, response, error in
                defer {
                    self?.semaphore.signal()
                    self?.cleanupRequest(cacheKey: cacheKey)
                }
                
                guard let self = self else { return }
                
                if let error = error {
                    // If main URLSession fails, try with a simple fallback
                    self.attemptFallbackRequest(url: url, cacheKey: cacheKey, completion: completion)
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    let error = NSError(domain: "OptimizedNetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"])
                    self.notifyAllWaiters(cacheKey: cacheKey, result: .failure(error))
                    return
                }
                
                // Validate RSS/XML content
                if let dataString = String(data: data, encoding: .utf8) {
                    if !dataString.contains("<rss") && !dataString.contains("<feed") && !dataString.contains("<?xml") {
                        let error = NSError(domain: "OptimizedNetworkManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid RSS/XML format"])
                        self.notifyAllWaiters(cacheKey: cacheKey, result: .failure(error))
                        return
                    }
                }
                
                // Cache successful response
                let cachedResponse = CachedResponse(data: data, timestamp: Date())
                self.cacheQueue.async {
                    self.responseCache[cacheKey] = cachedResponse
                    self.clearExpiredCache()
                }
                
                self.notifyAllWaiters(cacheKey: cacheKey, result: .success(data))
            }
            
            task.resume()
        }
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
            self?.activeRequests.remove(cacheKey)
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
    
    // MARK: - Fallback Network Request
    
    private func attemptFallbackRequest(url: URL, cacheKey: String, completion: @escaping (Result<Data, Error>) -> Void) {
        // Create a simple URLSession with minimal configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0  // Longer timeout
        config.timeoutIntervalForResource = 120.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil  // Disable caching
        
        let simpleSession = URLSession(configuration: config)
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        simpleSession.dataTask(with: request) { [weak self] data, response, error in
            defer {
                simpleSession.invalidateAndCancel()
            }
            
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Fallback request also failed: \(error.localizedDescription)")
                self.notifyAllWaiters(cacheKey: cacheKey, result: .failure(error))
                return
            }
            
            guard let data = data, !data.isEmpty else {
                let error = NSError(domain: "OptimizedNetworkManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response from fallback"])
                self.notifyAllWaiters(cacheKey: cacheKey, result: .failure(error))
                return
            }
            
            print("✅ Fallback request succeeded: \(data.count) bytes")
            
            // Cache successful response
            let cachedResponse = CachedResponse(data: data, timestamp: Date())
            self.cacheQueue.async {
                self.responseCache[cacheKey] = cachedResponse
                self.clearExpiredCache()
            }
            
            self.notifyAllWaiters(cacheKey: cacheKey, result: .success(data))
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