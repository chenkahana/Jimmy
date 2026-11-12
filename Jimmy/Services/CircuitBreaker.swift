import Foundation
import OSLog

/// State of a circuit breaker.
enum CircuitState: Equatable {
    case closed
    case open(Date)
    case halfOpen
}

enum CircuitBreakerError: Error, LocalizedError {
    case hostCircuitOpen(String)

    var errorDescription: String? {
        switch self {
        case .hostCircuitOpen(let host):
            return "Circuit breaker is open for host: \(host)"
        }
    }
}

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
