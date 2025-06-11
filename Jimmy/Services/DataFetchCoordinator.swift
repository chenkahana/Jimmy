import Foundation
import OSLog

/// Thread-safe coordinator for all background data fetching operations
/// Implements critical section management with actor-based thread safety for async contexts
class DataFetchCoordinator {
    static let shared = DataFetchCoordinator()
    
    // MARK: - Thread-Safe State Management
    private let stateLock = NSLock()
    private var _activeFetches: Set<String> = []
    private let maxConcurrentFetches = 5
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "DataFetchCoordinator")
    
    private init() {}
    
    // MARK: - Thread-Safe State Access
    
    private func withLock<T>(_ operation: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation()
    }
    
    private func canStartFetch(id: String) -> Bool {
        return withLock {
            let isAlreadyActive = _activeFetches.contains(id)
            let canStartNewFetch = _activeFetches.count < maxConcurrentFetches
            if !isAlreadyActive && canStartNewFetch {
                _activeFetches.insert(id)
                return true
            }
            return false
        }
    }
    
    private func removeFetch(id: String) {
        withLock {
            _ = _activeFetches.remove(id)
        }
    }
    
    // MARK: - Public Interface
    
    /// Start a basic fetch operation with thread-safe state management
    func startFetch<T>(
        id: String,
        operation: @escaping () async throws -> T,
        onComplete: @escaping (Result<T, Error>) -> Void
    ) {
        // Check if we can start the fetch
        guard canStartFetch(id: id) else {
            let isActive = withLock { _activeFetches.contains(id) }
            if isActive {
                logger.warning("🚫 Fetch already active: \(id)")
                onComplete(.failure(DataFetchError.alreadyActive))
            } else {
                logger.warning("🚫 Max concurrent fetches reached: \(self.maxConcurrentFetches)")
                onComplete(.failure(DataFetchError.maxConcurrentReached))
            }
            return
        }
        
        logger.info("🔄 Starting fetch: \(id)")
        
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try await operation()
                
                // Update state on completion
                self?.removeFetch(id: id)
                
                // Dispatch completion to main thread
                DispatchQueue.main.async {
                    onComplete(.success(result))
                }
                
                self?.logger.info("✅ Fetch completed: \(id)")
                
            } catch {
                // Update state on error
                self?.removeFetch(id: id)
                
                // Dispatch error to main thread
                DispatchQueue.main.async {
                    onComplete(.failure(error))
                }
                
                self?.logger.error("❌ Fetch failed: \(id) - \(error.localizedDescription)")
            }
        }
    }
    
    /// Start a progressive fetch operation that provides incremental updates
    /// - Parameters:
    ///   - id: Unique identifier for the fetch operation
    ///   - operation: The async operation that provides progressive updates
    ///   - onProgress: Called for each incremental update (on main thread)
    ///   - onComplete: Called when operation completes (on main thread)
    func startProgressiveFetch<T, U>(
        id: String,
        operation: @escaping (@escaping (T) -> Void) async throws -> U,
        onProgress: @escaping (T) -> Void,
        onComplete: @escaping (Result<U, Error>) -> Void
    ) {
        // Check if we can start the fetch
        guard canStartFetch(id: id) else {
            let isActive = withLock { _activeFetches.contains(id) }
            if isActive {
                logger.warning("🚫 Progressive fetch already active: \(id)")
                onComplete(.failure(DataFetchError.alreadyActive))
            } else {
                logger.warning("🚫 Max concurrent fetches reached for progressive fetch: \(self.maxConcurrentFetches)")
                onComplete(.failure(DataFetchError.maxConcurrentReached))
            }
            return
        }
        
        logger.info("🔄 Starting progressive fetch: \(id)")
        
        // Execute progressive operation on background thread
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // Progress callback that dispatches to main thread
                let progressCallback: (T) -> Void = { progressData in
                    DispatchQueue.main.async {
                        onProgress(progressData)
                    }
                }
                
                let result = try await operation(progressCallback)
                
                // Update state on completion
                self?.removeFetch(id: id)
                
                // Call completion on main thread
                DispatchQueue.main.async {
                    onComplete(.success(result))
                }
                
                self?.logger.info("✅ Progressive fetch completed: \(id)")
                
            } catch {
                // Update state on error
                self?.removeFetch(id: id)
                
                // Call completion on main thread
                DispatchQueue.main.async {
                    onComplete(.failure(error))
                }
                
                self?.logger.error("❌ Progressive fetch failed: \(id) - \(error.localizedDescription)")
            }
        }
    }
    
    /// Cancel a specific fetch operation
    func cancelFetch(id: String) {
        let wasActive = withLock {
            _activeFetches.remove(id) != nil
        }
        
        if wasActive {
            logger.info("🚫 Cancelled fetch: \(id)")
        } else {
            logger.warning("🚫 Attempted to cancel non-active fetch: \(id)")
        }
    }
    
    /// Cancel all active fetch operations
    func cancelAllFetches() {
        let cancelledCount = withLock {
            let count = _activeFetches.count
            _activeFetches.removeAll()
            return count
        }
        
        logger.info("🚫 Cancelled all fetches: \(cancelledCount) operations")
    }
    
    /// Start a batch fetch operation with progress tracking
    func startBatchFetch<T>(
        batchId: String,
        operations: [(id: String, operation: () async throws -> T)],
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping ([String: Result<T, Error>]) -> Void
    ) {
        // Check if we can start the batch fetch
        guard canStartFetch(id: batchId) else {
            let isActive = withLock { _activeFetches.contains(batchId) }
            if isActive {
                logger.warning("🚫 Batch fetch already active: \(batchId)")
            } else {
                logger.warning("🚫 Max concurrent fetches reached for batch: \(self.maxConcurrentFetches)")
            }
            return
        }
        
        logger.info("🔄 Starting batch fetch: \(batchId) with \(operations.count) operations")
        
        Task.detached(priority: .userInitiated) { [weak self] in
            var results: [String: Result<T, Error>] = [:]
            let total = Double(operations.count)
            
            for (index, operation) in operations.enumerated() {
                do {
                    let result = try await operation.operation()
                    results[operation.id] = .success(result)
                } catch {
                    results[operation.id] = .failure(error)
                }
                
                let progress = Double(index + 1) / total
                DispatchQueue.main.async {
                    onProgress(progress)
                }
            }
            
            // Update state on completion
            self?.removeFetch(id: batchId)
            
            DispatchQueue.main.async {
                onComplete(results)
            }
            
            self?.logger.info("✅ Batch fetch completed: \(batchId)")
        }
    }
    
    // MARK: - State Inspection (Thread-Safe)
    
    /// Get the current number of active fetches
    var activeFetchCount: Int {
        withLock { _activeFetches.count }
    }
    
    /// Check if a specific fetch is active
    func isFetchActive(id: String) -> Bool {
        withLock { _activeFetches.contains(id) }
    }
    
    /// Get all active fetch IDs
    var activeFetchIds: Set<String> {
        withLock { _activeFetches }
    }
}

// MARK: - Error Types

enum DataFetchError: LocalizedError {
    case alreadyActive
    case maxConcurrentReached
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .alreadyActive:
            return "Fetch operation is already active"
        case .maxConcurrentReached:
            return "Maximum concurrent fetch operations reached"
        case .cancelled:
            return "Fetch operation was cancelled"
        }
    }
} 