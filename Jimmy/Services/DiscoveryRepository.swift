import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(OSLog)
import OSLog
#endif

/// Thread-safe repository for discovery data with reader-writer lock pattern
/// Follows the Background Data Synchronization Plan architecture
final class DiscoveryRepository: ObservableObject {
    static let shared = DiscoveryRepository()
    
    // MARK: - Published Properties
    
    @Published private(set) var trending: [TrendingEpisode] = []
    @Published private(set) var featured: [PodcastSearchResult] = []
    @Published private(set) var charts: [PodcastSearchResult] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var cacheStatus: CacheStatus = .empty
    
    // MARK: - Cache Status
    
    enum CacheStatus {
        case empty
        case loading
        case cached(age: TimeInterval)
        case fresh
        case error(String)
        
        var displayText: String {
            switch self {
            case .empty: return "No data"
            case .loading: return "Loading..."
            case .cached(let age): return "Cached \(Int(age/60))m ago"
            case .fresh: return "Up to date"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let dataQueue = DispatchQueue(label: "discovery-repository", qos: .userInitiated, attributes: .concurrent)
    private let cacheQueue = DispatchQueue(label: "discovery-cache", qos: .utility)
    private let changeSubject = PassthroughSubject<DiscoveryChanges, Never>()
    
    // Thread-safe internal storage (accessed only within dataQueue)
    private var _internalTrending: [TrendingEpisode] = []
    private var _internalFeatured: [PodcastSearchResult] = []
    private var _internalCharts: [PodcastSearchResult] = []
    private var _internalLastUpdated: Date?
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "DiscoveryRepository")
    #endif
    
    // MARK: - Cache Configuration
    
    private struct CacheConfig {
        static let cacheKey = "discovery_cache_v2"
        static let maxCacheAge: TimeInterval = 3600 // 1 hour
        static let staleThreshold: TimeInterval = 1800 // 30 minutes
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
        loadCachedData()
    }
    
    // MARK: - Public Interface
    
    /// Get all discovery data (thread-safe read)
    func getAllData() async -> (trending: [TrendingEpisode], featured: [PodcastSearchResult], charts: [PodcastSearchResult]) {
        return await withCheckedContinuation { continuation in
            dataQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: ([], [], []))
                    return
                }
                continuation.resume(returning: (self._internalTrending, self._internalFeatured, self._internalCharts))
            }
        }
    }
    
    /// Update trending episodes (thread-safe write)
    func updateTrending(_ episodes: [TrendingEpisode]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self._internalTrending = episodes
                self._internalLastUpdated = Date()
                
                Task { @MainActor in
                    self.trending = episodes
                    self.lastUpdated = Date()
                    self.updateCacheStatus()
                }
                
                continuation.resume()
            }
        }
        
        persistCacheData()
        notifyChanges(.trending(episodes))
    }
    
    /// Update featured podcasts (thread-safe write)
    func updateFeatured(_ podcasts: [PodcastSearchResult]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self._internalFeatured = podcasts
                self._internalLastUpdated = Date()
                
                Task { @MainActor in
                    self.featured = podcasts
                    self.lastUpdated = Date()
                    self.updateCacheStatus()
                }
                
                continuation.resume()
            }
        }
        
        persistCacheData()
        notifyChanges(.featured(podcasts))
    }
    
    /// Update charts (thread-safe write)
    func updateCharts(_ podcasts: [PodcastSearchResult]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self._internalCharts = podcasts
                self._internalLastUpdated = Date()
                
                Task { @MainActor in
                    self.charts = podcasts
                    self.lastUpdated = Date()
                    self.updateCacheStatus()
                }
                
                continuation.resume()
            }
        }
        
        persistCacheData()
        notifyChanges(.charts(podcasts))
    }
    
    /// Batch update all discovery data (atomic operation)
    func batchUpdate(trending: [TrendingEpisode], featured: [PodcastSearchResult], charts: [PodcastSearchResult]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self._internalTrending = trending
                self._internalFeatured = featured
                self._internalCharts = charts
                self._internalLastUpdated = Date()
                
                Task { @MainActor in
                    self.trending = trending
                    self.featured = featured
                    self.charts = charts
                    self.lastUpdated = Date()
                    self.updateCacheStatus()
                }
                
                continuation.resume()
            }
        }
        
        persistCacheData()
        notifyChanges(.batchUpdate(trending: trending, featured: featured, charts: charts))
    }
    
    /// Set loading state
    @MainActor
    func setLoading(_ loading: Bool) {
        self.isLoading = loading
        if loading {
            self.cacheStatus = .loading
        }
    }
    
    /// Check if cache is stale
    func isCacheStale() async -> Bool {
        let data = await getAllData()
        guard let lastUpdated = await getLastUpdated() else { return true }
        
        let cacheAge = Date().timeIntervalSince(lastUpdated)
        return cacheAge > CacheConfig.staleThreshold || (data.trending.isEmpty && data.featured.isEmpty && data.charts.isEmpty)
    }
    
    /// Get cache age
    func getCacheAge() async -> TimeInterval? {
        guard let lastUpdated = await getLastUpdated() else { return nil }
        return Date().timeIntervalSince(lastUpdated)
    }
    
    /// Clear all data
    func clearData() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self._internalTrending = []
                self._internalFeatured = []
                self._internalCharts = []
                self._internalLastUpdated = nil
                
                Task { @MainActor in
                    self.trending = []
                    self.featured = []
                    self.charts = []
                    self.lastUpdated = nil
                    self.cacheStatus = .empty
                }
                
                continuation.resume()
            }
        }
        
        clearCacheData()
        notifyChanges(.cleared)
    }
    
    // MARK: - Private Methods
    
    private func getLastUpdated() async -> Date? {
        return await withCheckedContinuation { continuation in
            dataQueue.async { [weak self] in
                continuation.resume(returning: self?._internalLastUpdated)
            }
        }
    }
    
    @MainActor
    private func updateCacheStatus() {
        guard let lastUpdated = lastUpdated else {
            cacheStatus = .empty
            return
        }
        
        let age = Date().timeIntervalSince(lastUpdated)
        if age < 300 { // 5 minutes
            cacheStatus = .fresh
        } else {
            cacheStatus = .cached(age: age)
        }
    }
    
    private func setupNotificationObservers() {
        // Listen for app lifecycle events
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.persistCacheData()
            }
        }
        #endif
    }
    
    private func notifyChanges(_ changes: DiscoveryChanges) {
        changeSubject.send(changes)
        
        #if canImport(OSLog)
        logger.info("📡 Discovery data updated: \(changes.description)")
        #endif
    }
    
    // MARK: - Cache Management
    
    private func loadCachedData() {
        cacheQueue.async { [weak self] in
            guard let data = UserDefaults.standard.data(forKey: CacheConfig.cacheKey),
                  let cached = try? JSONDecoder().decode(DiscoveryCacheData.self, from: data) else {
                return
            }
            
            // Check if cache is still valid
            let cacheAge = Date().timeIntervalSince(cached.timestamp)
            guard cacheAge < CacheConfig.maxCacheAge else {
                #if canImport(OSLog)
                self?.logger.info("🗑️ Discovery cache expired (age: \(Int(cacheAge))s)")
                #endif
                return
            }
            
            // Load cached data
            Task { @MainActor in
                self?.trending = cached.trending
                self?.featured = cached.featured
                self?.charts = cached.charts
                self?.lastUpdated = cached.timestamp
                self?.updateCacheStatus()
                
                #if canImport(OSLog)
                self?.logger.info("💾 Loaded discovery cache (age: \(Int(cacheAge))s)")
                #endif
            }
            
            // Update internal state
            self?.dataQueue.async(flags: .barrier) { [weak self] in
                self?._internalTrending = cached.trending
                self?._internalFeatured = cached.featured
                self?._internalCharts = cached.charts
                self?._internalLastUpdated = cached.timestamp
            }
        }
    }
    
    private func persistCacheData() {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            let cacheData = DiscoveryCacheData(
                trending: self._internalTrending,
                featured: self._internalFeatured,
                charts: self._internalCharts,
                timestamp: self._internalLastUpdated ?? Date()
            )
            
            self.cacheQueue.async {
                if let encoded = try? JSONEncoder().encode(cacheData) {
                    UserDefaults.standard.set(encoded, forKey: CacheConfig.cacheKey)
                    
                    #if canImport(OSLog)
                    self.logger.info("💾 Persisted discovery cache")
                    #endif
                }
            }
        }
    }
    
    private func clearCacheData() {
        cacheQueue.async {
            UserDefaults.standard.removeObject(forKey: CacheConfig.cacheKey)
        }
    }
}

// MARK: - Discovery Changes

enum DiscoveryChanges {
    case trending([TrendingEpisode])
    case featured([PodcastSearchResult])
    case charts([PodcastSearchResult])
    case batchUpdate(trending: [TrendingEpisode], featured: [PodcastSearchResult], charts: [PodcastSearchResult])
    case cleared
    
    var description: String {
        switch self {
        case .trending(let episodes): return "trending(\(episodes.count))"
        case .featured(let podcasts): return "featured(\(podcasts.count))"
        case .charts(let podcasts): return "charts(\(podcasts.count))"
        case .batchUpdate(let trending, let featured, let charts): 
            return "batch(trending: \(trending.count), featured: \(featured.count), charts: \(charts.count))"
        case .cleared: return "cleared"
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let discoveryDataUpdated = Notification.Name("discoveryDataUpdated")
    static let discoveryRepositoryError = Notification.Name("discoveryRepositoryError")
} 