import Foundation
import OSLog
import Combine

/// Circuit Breaker pattern implementation for podcast feed reliability
/// Prevents cascading failures and provides intelligent fallback mechanisms
final class CircuitBreaker: ObservableObject {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "CircuitBreaker")
    
    // MARK: - Configuration
    private struct Config {
        static let failureThreshold = 5
        static let successThreshold = 3
        static let timeout: TimeInterval = 300 // 5 minutes
        static let halfOpenMaxAttempts = 2
        static let exponentialBackoffBase: TimeInterval = 60 // 1 minute base
        static let maxBackoffTime: TimeInterval = 3600 // 1 hour max
    }
    
    // MARK: - State Management
    @Published private(set) var globalState: CircuitState = .closed
    private var feedStates: [URL: FeedCircuitState] = [:]
    private let stateQueue = DispatchQueue(label: "CircuitBreakerState", attributes: .concurrent)
    
    // MARK: - Publishers
    let statePublisher = PassthroughSubject<CircuitState, Never>()
    
    init() {
        logger.info("🔧 Circuit Breaker initialized")
    }
    
    // MARK: - Public API
    
    /// Check if operations are allowed (throws if circuit is open)
    func checkState() throws {
        let currentState = globalState
        
        switch currentState {
        case .open(let openTime):
            let timeoutExpired = Date().timeIntervalSince(openTime) > Config.timeout
            if timeoutExpired {
                transitionToHalfOpen()
                logger.info("🔄 Circuit breaker transitioning to half-open")
            } else {
                throw CircuitBreakerError.circuitOpen
            }
            
        case .halfOpen:
            // Allow limited attempts in half-open state
            break
            
        case .closed:
            // Normal operation
            break
        }
    }
    
    /// Check state for a specific feed
    func checkFeedState(_ feedURL: URL) throws {
        let feedState = getFeedState(feedURL)
        
        switch feedState.state {
        case .open(let openTime):
            let backoffTime = calculateBackoffTime(feedState.consecutiveFailures)
            let timeoutExpired = Date().timeIntervalSince(openTime) > backoffTime
            
            if timeoutExpired {
                transitionFeedToHalfOpen(feedURL)
                logger.info("🔄 Feed circuit breaker transitioning to half-open: \(feedURL)")
            } else {
                throw CircuitBreakerError.feedCircuitOpen(feedURL)
            }
            
        case .halfOpen:
            // Allow limited attempts
            break
            
        case .closed:
            // Normal operation
            break
        }
    }
    
    /// Record a successful operation
    func recordSuccess(for feedURL: URL? = nil) {
        if let feedURL = feedURL {
            recordFeedSuccess(feedURL)
        }
        
        // Update global state
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            switch self.globalState {
            case .halfOpen:
                self.transitionToClosed()
                
            case .closed:
                // Already closed, nothing to do
                break
                
            case .open:
                // Success during open state shouldn't happen, but handle gracefully
                self.logger.warning("⚠️ Received success during open circuit state")
                break
            }
        }
    }
    
    /// Record a failed operation
    func recordFailure(for feedURL: URL? = nil) {
        if let feedURL = feedURL {
            recordFeedFailure(feedURL)
        }
        
        // Update global state
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let failedFeeds = self.feedStates.values.filter { feedState in
                if case .open = feedState.state {
                    return true
                }
                return feedState.consecutiveFailures >= Config.failureThreshold
            }
            
            // If too many feeds are failing, open global circuit
            let failureRate = Double(failedFeeds.count) / max(1.0, Double(self.feedStates.count))
            
            if failureRate > 0.3 { // 30% failure rate threshold
                self.transitionToOpen()
            }
        }
    }
    
    /// Get circuit breaker statistics
    func getStatistics() -> CircuitBreakerStatistics {
        return stateQueue.sync {
            let totalFeeds = feedStates.count
            let openFeeds = feedStates.values.filter { 
                if case .open = $0.state { return true }
                return false
            }.count
            let halfOpenFeeds = feedStates.values.filter {
                if case .halfOpen = $0.state { return true }
                return false
            }.count
            
            let totalFailures = feedStates.values.reduce(0) { $0 + $1.totalFailures }
            let totalSuccesses = feedStates.values.reduce(0) { $0 + $1.totalSuccesses }
            
            return CircuitBreakerStatistics(
                globalState: globalState,
                totalFeeds: totalFeeds,
                openFeeds: openFeeds,
                halfOpenFeeds: halfOpenFeeds,
                totalFailures: totalFailures,
                totalSuccesses: totalSuccesses
            )
        }
    }
    
    /// Reset circuit breaker for a specific feed
    func resetFeed(_ feedURL: URL) {
        stateQueue.async(flags: .barrier) { [weak self] in
            self?.feedStates[feedURL] = FeedCircuitState()
            self?.logger.info("🔄 Reset circuit breaker for feed: \(feedURL)")
        }
    }
    
    /// Reset all circuit breakers
    func resetAll() {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.feedStates.removeAll()
            self.transitionToClosed()
            self.logger.info("🔄 Reset all circuit breakers")
        }
    }
    
    // MARK: - Private Methods
    
    private func getFeedState(_ feedURL: URL) -> FeedCircuitState {
        return stateQueue.sync {
            return feedStates[feedURL] ?? FeedCircuitState()
        }
    }
    
    private func recordFeedSuccess(_ feedURL: URL) {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var feedState = self.feedStates[feedURL] ?? FeedCircuitState()
            feedState.recordSuccess()
            
            // Check if we should close the circuit
            switch feedState.state {
            case .halfOpen:
                if feedState.consecutiveSuccesses >= Config.successThreshold {
                    feedState.state = .closed
                    self.logger.info("✅ Feed circuit closed after successful recovery: \(feedURL)")
                }
                
            case .open:
                // Success during open state - transition to half-open
                feedState.state = .halfOpen
                feedState.consecutiveSuccesses = 1
                self.logger.info("🔄 Feed circuit transitioning to half-open after success: \(feedURL)")
                
            case .closed:
                // Already closed, just update stats
                break
            }
            
            self.feedStates[feedURL] = feedState
        }
    }
    
    private func recordFeedFailure(_ feedURL: URL) {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var feedState = self.feedStates[feedURL] ?? FeedCircuitState()
            feedState.recordFailure()
            
            // Check if we should open the circuit
            switch feedState.state {
            case .closed:
                if feedState.consecutiveFailures >= Config.failureThreshold {
                    feedState.state = .open(Date())
                    self.logger.warning("🚨 Feed circuit opened due to failures: \(feedURL)")
                }
                
            case .halfOpen:
                // Failure in half-open state - back to open
                feedState.state = .open(Date())
                self.logger.warning("🚨 Feed circuit reopened after half-open failure: \(feedURL)")
                
            case .open:
                // Already open, just update stats
                break
            }
            
            self.feedStates[feedURL] = feedState
        }
    }
    
    private func transitionToClosed() {
        globalState = .closed
        statePublisher.send(.closed)
        logger.info("✅ Global circuit breaker closed")
    }
    
    private func transitionToOpen() {
        globalState = .open(Date())
        statePublisher.send(globalState)
        logger.warning("🚨 Global circuit breaker opened")
    }
    
    private func transitionToHalfOpen() {
        globalState = .halfOpen
        statePublisher.send(.halfOpen)
        logger.info("🔄 Global circuit breaker half-open")
    }
    
    private func transitionFeedToHalfOpen(_ feedURL: URL) {
        stateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var feedState = self.feedStates[feedURL] ?? FeedCircuitState()
            feedState.state = .halfOpen
            feedState.consecutiveSuccesses = 0
            self.feedStates[feedURL] = feedState
        }
    }
    
    private func calculateBackoffTime(_ consecutiveFailures: Int) -> TimeInterval {
        // Exponential backoff with jitter
        let exponentialTime = Config.exponentialBackoffBase * pow(2.0, Double(min(consecutiveFailures - Config.failureThreshold, 6)))
        let jitter = Double.random(in: 0.8...1.2) // ±20% jitter
        let backoffTime = min(exponentialTime * jitter, Config.maxBackoffTime)
        
        return backoffTime
    }
}

// MARK: - Supporting Types

enum CircuitState: Equatable {
    case closed
    case open(Date)
    case halfOpen
    
    var description: String {
        switch self {
        case .closed:
            return "Closed"
        case .open(let date):
            return "Open (since \(date))"
        case .halfOpen:
            return "Half-Open"
        }
    }
}

private struct FeedCircuitState {
    var state: CircuitState = .closed
    var consecutiveFailures: Int = 0
    var consecutiveSuccesses: Int = 0
    var totalFailures: Int = 0
    var totalSuccesses: Int = 0
    var lastFailureTime: Date?
    var lastSuccessTime: Date?
    
    mutating func recordSuccess() {
        consecutiveSuccesses += 1
        consecutiveFailures = 0
        totalSuccesses += 1
        lastSuccessTime = Date()
    }
    
    mutating func recordFailure() {
        consecutiveFailures += 1
        consecutiveSuccesses = 0
        totalFailures += 1
        lastFailureTime = Date()
    }
}

struct CircuitBreakerStatistics {
    let globalState: CircuitState
    let totalFeeds: Int
    let openFeeds: Int
    let halfOpenFeeds: Int
    let totalFailures: Int
    let totalSuccesses: Int
    
    var successRate: Double {
        let total = totalFailures + totalSuccesses
        return total > 0 ? Double(totalSuccesses) / Double(total) : 0.0
    }
    
    var healthyFeedsPercentage: Double {
        let healthyFeeds = totalFeeds - openFeeds
        return totalFeeds > 0 ? Double(healthyFeeds) / Double(totalFeeds) : 1.0
    }
}

enum CircuitBreakerError: Error, LocalizedError {
    case circuitOpen
    case feedCircuitOpen(URL)
    case hostCircuitOpen(String)
    
    var errorDescription: String? {
        switch self {
        case .circuitOpen:
            return "Circuit breaker is open - operations temporarily disabled"
        case .feedCircuitOpen(let url):
            return "Circuit breaker is open for feed: \(url.absoluteString)"
        case .hostCircuitOpen(let host):
            return "Circuit breaker is open for host: \(host)"
        }
    }
    
    var isRetryable: Bool {
        return true // Circuit breaker errors are always retryable after timeout
    }
}

// MARK: - PERF-05: Host Circuit Breaker

/// Actor that tracks failures per-host to isolate network failures.
/// One failing podcast feed won't block requests to other hosts.
actor HostCircuitBreaker {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "HostCircuitBreaker")

    /// Host state tracking
    struct HostState {
        var failureCount: Int = 0
        var lastFailure: Date?
        var state: CircuitState = .closed
        var consecutiveSuccesses: Int = 0
        
        mutating func recordSuccess() {
            consecutiveSuccesses += 1
            if consecutiveSuccesses >= 2 { // Reset after 2 successful requests
                failureCount = 0
                state = .closed
            }
        }
        
        mutating func recordFailure() {
            failureCount += 1
            consecutiveSuccesses = 0
            lastFailure = Date()
        }
    }
    
    // MARK: - Configuration
    private let failureThreshold = 3
    private let resetTimeout: TimeInterval = 60 // 1 minute

    // MARK: - State
    private var hostStates: [String: HostState] = [:]
    
    // MARK: - Singleton
    static let shared = HostCircuitBreaker()
    
    private init() {
        logger.debug("HostCircuitBreaker initialized (per-host failure tracking)")
    }
    
    // MARK: - Public API
    
    /// Check if a request to this URL should be allowed
    /// - Parameter url: The URL to check
    /// - Returns: true if request should proceed, false if circuit is open for this host
    func shouldAllow(url: URL) -> Bool {
        guard let host = url.host else { return true }
        guard var state = hostStates[host] else { return true }
        
        switch state.state {
        case .closed:
            return true
            
        case .open(let openTime):
            // Check if reset timeout has passed
            if Date().timeIntervalSince(openTime) > resetTimeout {
                state.state = .halfOpen
                state.consecutiveSuccesses = 0
                hostStates[host] = state
                logger.info("Host circuit half-open: \(host)")
                return true
            }
            logger.warning("Host circuit open, blocking request to: \(host)")
            return false
            
        case .halfOpen:
            return true
        }
    }
    
    /// Record a successful request for the given URL's host
    /// - Parameter url: The URL that succeeded
    func recordSuccess(for url: URL) {
        guard let host = url.host else { return }
        
        var state = hostStates[host] ?? HostState()
        let previousState = state.state
        state.recordSuccess()
        
        // If transitioning from half-open to closed, log it
        if case .halfOpen = previousState, case .closed = state.state {
            logger.info("Host circuit closed, recovered: \(host)")
        }
        
        hostStates[host] = state
    }
    
    /// Record a failed request for the given URL's host
    /// - Parameter url: The URL that failed
    func recordFailure(for url: URL) {
        guard let host = url.host else { return }
        
        var state = hostStates[host] ?? HostState()
        state.recordFailure()
        
        // Check if we should open the circuit
        if state.failureCount >= failureThreshold && state.state != .open(state.lastFailure ?? Date()) {
            state.state = .open(Date())
            logger.error("Host circuit opened after \(state.failureCount) failures: \(host)")
        }
        
        hostStates[host] = state
    }
    
    /// Throws an error if the circuit is open for the given URL's host
    /// - Parameter url: The URL to check
    /// - Throws: CircuitBreakerError.hostCircuitOpen if circuit is open
    func checkHost(url: URL) throws {
        guard shouldAllow(url: url) else {
            throw CircuitBreakerError.hostCircuitOpen(url.host ?? "unknown")
        }
    }
    
    /// Get statistics about host circuit breakers
    func getStatistics() -> (totalHosts: Int, openCircuits: Int, halfOpenCircuits: Int) {
        let openCount = hostStates.values.filter {
            if case .open = $0.state { return true }
            return false
        }.count
        
        let halfOpenCount = hostStates.values.filter {
            if case .halfOpen = $0.state { return true }
            return false
        }.count
        
        return (hostStates.count, openCount, halfOpenCount)
    }
    
    /// Reset circuit for a specific host
    func resetHost(_ host: String) {
        hostStates[host] = HostState()
        logger.info("Reset host circuit: \(host)")
    }
    
    /// Reset all host circuits
    func resetAll() {
        hostStates.removeAll()
        logger.info("Reset all host circuits")
    }
}
