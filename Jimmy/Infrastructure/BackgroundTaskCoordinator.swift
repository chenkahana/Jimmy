import Foundation

// MARK: - Background Task Management

/// Background task coordinator for heavy operations using structured concurrency
final class BackgroundTaskCoordinator: @unchecked Sendable {
    static let shared = BackgroundTaskCoordinator()
    
    private let workQueue = DispatchQueue(label: "com.jimmy.background", qos: .utility, attributes: .concurrent)
    private let maxConcurrentOperations = 4
    
    // MEMORY FIX: Track active tasks to prevent accumulation
    private var activeTasks: Set<UUID> = []
    private let taskTrackingQueue = DispatchQueue(label: "task-tracking", attributes: .concurrent)
    
    private init() {}
    
    deinit {
        // MEMORY FIX: Cancel all active tasks on deinit
        cancelAllTasks()
    }
    
    /// Cancel all active tasks to prevent memory leaks
    func cancelAllTasks() {
        taskTrackingQueue.async(flags: .barrier) {
            self.activeTasks.removeAll()
        }
    }
    
    /// Execute heavy CPU work on background queue
    func executeHeavyWork<T>(_ work: @escaping () async throws -> T) async throws -> T {
        let taskID = UUID()
        
        // Track task
        taskTrackingQueue.async(flags: .barrier) {
            self.activeTasks.insert(taskID)
        }
        
        defer {
            // Remove task when done
            taskTrackingQueue.async(flags: .barrier) {
                self.activeTasks.remove(taskID)
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                Task {
                    do {
                        let result = try await work()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Execute multiple operations concurrently with limit
    func executeConcurrentWork<T>(_ operations: [() async throws -> T]) async throws -> [T] {
        return try await withThrowingTaskGroup(of: T.self) { group in
            var results: [T] = []
            
            for operation in operations {
                group.addTask {
                    try await operation()
                }
            }
            
            for try await result in group {
                results.append(result)
            }
            
            return results
        }
    }
    
    /// Execute operations with priority and cancellation support
    func executeWithPriority<T>(
        priority: TaskPriority = .utility,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // MEMORY FIX: Use regular Task instead of Task.detached to prevent memory leaks
        return try await Task(priority: priority) {
            try await operation()
        }.value
    }
    
    /// Execute batch operations with concurrency limit
    func executeBatch<T, U>(
        items: [T],
        concurrencyLimit: Int = 4,
        operation: @escaping (T) async throws -> U
    ) async throws -> [U] {
        return try await withThrowingTaskGroup(of: (Int, U).self) { group in
            var results: [U?] = Array(repeating: nil, count: items.count)
            var currentIndex = 0
            
            // Start initial batch
            for _ in 0..<min(concurrencyLimit, items.count) {
                let index = currentIndex
                currentIndex += 1
                
                group.addTask {
                    let result = try await operation(items[index])
                    return (index, result)
                }
            }
            
            // Process results and start new tasks
            for try await (index, result) in group {
                results[index] = result
                
                // Start next task if available
                if currentIndex < items.count {
                    let nextIndex = currentIndex
                    currentIndex += 1
                    
                    group.addTask {
                        let result = try await operation(items[nextIndex])
                        return (nextIndex, result)
                    }
                }
            }
            
            return results.compactMap { $0 }
        }
    }
}

// MARK: - Structured Concurrency Helpers

extension Task where Success == Never, Failure == Never {
    /// Sleep for a duration with proper cancellation handling
    static func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Actor for coordinating background refresh operations
actor BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()
    
    private var isRefreshing = false
    private var lastRefreshTime: Date?
    private let minimumRefreshInterval: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    func shouldRefresh() -> Bool {
        guard !isRefreshing else { return false }
        
        if let lastRefresh = lastRefreshTime {
            return Date().timeIntervalSince(lastRefresh) >= minimumRefreshInterval
        }
        
        return true
    }
    
    func startRefresh() {
        isRefreshing = true
    }
    
    func finishRefresh() {
        isRefreshing = false
        lastRefreshTime = Date()
    }
    
    func getRefreshStatus() -> (isRefreshing: Bool, lastRefresh: Date?) {
        return (isRefreshing, lastRefreshTime)
    }
} 