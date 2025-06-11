import Foundation

/// Lightweight request object for episode fetching operations
/// Designed to be queued and processed by background workers
struct FetchEpisodesRequest: Identifiable, Codable {
    var id = UUID()
    let podcastID: UUID?
    let requestType: RequestType
    let priority: Priority
    let timestamp: Date
    let retryCount: Int
    let maxRetries: Int
    
    // MARK: - Request Types
    
    enum RequestType: String, Codable, CaseIterable {
        case allPodcasts = "all_podcasts"
        case singlePodcast = "single_podcast"
        case userInitiated = "user_initiated"
        case backgroundRefresh = "background_refresh"
        case refreshCache = "refresh_cache"
    }
    
    // MARK: - Priority Levels
    
    enum Priority: Int, Codable, CaseIterable, Comparable {
        case low = 1
        case normal = 2
        case high = 3
        case critical = 4
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    init(
        podcastID: UUID? = nil,
        requestType: RequestType,
        priority: Priority = .normal,
        maxRetries: Int = 3
    ) {
        self.podcastID = podcastID
        self.requestType = requestType
        self.priority = priority
        self.timestamp = Date()
        self.retryCount = 0
        self.maxRetries = maxRetries
    }
    
    /// Create a retry request with incremented retry count
    func createRetryRequest() -> FetchEpisodesRequest? {
        guard retryCount < maxRetries else { return nil }
        
        return FetchEpisodesRequest(
            podcastID: podcastID,
            requestType: requestType,
            priority: priority,
            maxRetries: maxRetries,
            retryCount: retryCount + 1,
            timestamp: Date()
        )
    }
    
    /// Check if request has expired (older than 5 minutes)
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 300 // 5 minutes
    }
    
    /// Get exponential backoff delay for retries
    var retryDelay: TimeInterval {
        return pow(2.0, Double(retryCount)) // 1s, 2s, 4s, 8s...
    }
    
    private init(
        podcastID: UUID?,
        requestType: RequestType,
        priority: Priority,
        maxRetries: Int,
        retryCount: Int,
        timestamp: Date
    ) {
        self.podcastID = podcastID
        self.requestType = requestType
        self.priority = priority
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.maxRetries = maxRetries
    }
    
    static func == (lhs: FetchEpisodesRequest, rhs: FetchEpisodesRequest) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Convenience Initializers

extension FetchEpisodesRequest {
    /// Create a user-initiated request for all podcasts
    static func userInitiatedRefresh() -> FetchEpisodesRequest {
        return FetchEpisodesRequest(
            requestType: .userInitiated,
            priority: .high,
            maxRetries: 2
        )
    }
    
    /// Create a background refresh request
    static func backgroundRefresh() -> FetchEpisodesRequest {
        return FetchEpisodesRequest(
            requestType: .backgroundRefresh,
            priority: .low,
            maxRetries: 1
        )
    }
    
    /// Create a request for a specific podcast
    static func singlePodcast(_ podcastID: UUID, priority: Priority = .normal) -> FetchEpisodesRequest {
        return FetchEpisodesRequest(
            podcastID: podcastID,
            requestType: .singlePodcast,
            priority: priority,
            maxRetries: 2
        )
    }
    
    /// Create a cache refresh request
    static func refreshCache() -> FetchEpisodesRequest {
        return FetchEpisodesRequest(
            requestType: .refreshCache,
            priority: .normal,
            maxRetries: 1
        )
    }
} 