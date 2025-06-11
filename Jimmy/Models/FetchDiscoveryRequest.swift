import Foundation

/// Lightweight request object for discovery data fetching operations
/// Designed to be queued and processed by background workers
struct FetchDiscoveryRequest: Identifiable, Codable {
    var id = UUID()
    let requestType: RequestType
    let priority: Priority
    let timestamp: Date
    let retryCount: Int
    let maxRetries: Int
    let limit: Int?
    
    // MARK: - Request Types
    
    enum RequestType: String, Codable, CaseIterable {
        case trending = "trending"
        case featured = "featured" 
        case charts = "charts"
        case all = "all"
        case userInitiated = "user_initiated"
        case backgroundRefresh = "background_refresh"
        case silentRefresh = "silent_refresh"
        case cacheRefresh = "cache_refresh"
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
        
        var taskPriority: TaskPriority {
            switch self {
            case .critical: return .userInitiated
            case .high: return .userInitiated
            case .normal: return .utility
            case .low: return .background
            }
        }
    }
    
    init(
        requestType: RequestType,
        priority: Priority = .normal,
        maxRetries: Int = 3,
        limit: Int? = nil
    ) {
        self.requestType = requestType
        self.priority = priority
        self.timestamp = Date()
        self.retryCount = 0
        self.maxRetries = maxRetries
        self.limit = limit
    }
    
    /// Create a retry request with incremented retry count
    func createRetryRequest() -> FetchDiscoveryRequest? {
        guard retryCount < maxRetries else { return nil }
        
        return FetchDiscoveryRequest(
            requestType: requestType,
            priority: priority,
            maxRetries: maxRetries,
            limit: limit,
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
    
    /// Get timeout for this request type
    var timeout: TimeInterval {
        switch requestType {
        case .userInitiated: return 30.0
        case .backgroundRefresh: return 15.0
        case .silentRefresh: return 10.0
        case .cacheRefresh: return 5.0
        case .trending, .featured, .charts, .all: return 20.0
        }
    }
    
    private init(
        requestType: RequestType,
        priority: Priority,
        maxRetries: Int,
        limit: Int?,
        retryCount: Int,
        timestamp: Date
    ) {
        self.requestType = requestType
        self.priority = priority
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.maxRetries = maxRetries
        self.limit = limit
    }
    
    static func == (lhs: FetchDiscoveryRequest, rhs: FetchDiscoveryRequest) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Convenience Initializers

extension FetchDiscoveryRequest {
    /// Create a user-initiated request for all discovery data
    static func userInitiatedRefresh() -> FetchDiscoveryRequest {
        return FetchDiscoveryRequest(
            requestType: .userInitiated,
            priority: .high,
            maxRetries: 2
        )
    }
    
    /// Create a background refresh request
    static func backgroundRefresh() -> FetchDiscoveryRequest {
        return FetchDiscoveryRequest(
            requestType: .backgroundRefresh,
            priority: .low,
            maxRetries: 1
        )
    }
    
    /// Create a silent refresh request
    static func silentRefresh() -> FetchDiscoveryRequest {
        return FetchDiscoveryRequest(
            requestType: .silentRefresh,
            priority: .low,
            maxRetries: 1
        )
    }
    
    /// Create a trending episodes request
    static func trending(limit: Int = 8) -> FetchDiscoveryRequest {
        return FetchDiscoveryRequest(
            requestType: .trending,
            priority: .normal,
            maxRetries: 2,
            limit: limit
        )
    }
    
    /// Create a featured podcasts request
    static func featured(limit: Int = 12) -> FetchDiscoveryRequest {
        return FetchDiscoveryRequest(
            requestType: .featured,
            priority: .normal,
            maxRetries: 2,
            limit: limit
        )
    }
    
    /// Create a charts request
    static func charts(limit: Int = 20) -> FetchDiscoveryRequest {
        return FetchDiscoveryRequest(
            requestType: .charts,
            priority: .normal,
            maxRetries: 2,
            limit: limit
        )
    }
    
    /// Create a cache refresh request
    static func refreshCache() -> FetchDiscoveryRequest {
        return FetchDiscoveryRequest(
            requestType: .cacheRefresh,
            priority: .normal,
            maxRetries: 1
        )
    }
} 