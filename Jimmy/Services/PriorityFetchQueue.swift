import Foundation
import OSLog

/// Priority-based fetch queue with intelligent scheduling and resource management
final class PriorityFetchQueue {
    private let logger = Logger(subsystem: "Jimmy.PriorityQueue", category: "FetchQueue")
    
    // MARK: - Configuration
    private struct Config {
        static let maxConcurrentOperations = 8
        static let highPrioritySlots = 4
        static let normalPrioritySlots = 3
        static let lowPrioritySlots = 1
        static let queueTimeout: TimeInterval = 300 // 5 minutes
        static let starvationPreventionThreshold = 10
    }
    
    // MARK: - Queue Management
    private var criticalQueue: [QueuedOperation] = []
    private var highQueue: [QueuedOperation] = []
    private var normalQueue: [QueuedOperation] = []
    private var lowQueue: [QueuedOperation] = []
    
    // MARK: - Resource Management
    private let semaphore = PriorityAsyncSemaphore(value: Config.maxConcurrentOperations)
    private var activeOperations: Set<UUID> = []
    private var operationStartTimes: [UUID: Date] = [:]
    
    // MARK: - Starvation Prevention
    private var lowPriorityWaitCount = 0
    private var normalPriorityWaitCount = 0
    
    // MARK: - Concurrency
    private let queueLock = NSLock()
    private let processingQueue = DispatchQueue(label: "PriorityFetchQueue", qos: .userInitiated, attributes: .concurrent)
    
    // MARK: - Statistics
    private var totalOperations: Int64 = 0
    private var completedOperations: Int64 = 0
    private var failedOperations: Int64 = 0
    
    init() {
        startQueueProcessor()
        // Priority Fetch Queue initialized
    }
    
    // MARK: - Public API
    
    /// Execute operation with priority-based scheduling
    func execute<T>(
        request: FetchRequest,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        
        let queuedOp = QueuedOperation(
            id: request.id,
            priority: request.priority,
            type: request.type,
            timestamp: request.timestamp,
            operation: operation
        )
        
        // Queuing operation
        
        // Add to appropriate queue
        enqueueOperation(queuedOp)
        
        // Wait for execution
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            queuedOp.continuation = continuation
        }
    }
    
    /// Get queue statistics
    func getStatistics() -> QueueStatistics {
        return queueLock.withLock {
            QueueStatistics(
                criticalQueueSize: criticalQueue.count,
                highQueueSize: highQueue.count,
                normalQueueSize: normalQueue.count,
                lowQueueSize: lowQueue.count,
                activeOperations: activeOperations.count,
                totalOperations: totalOperations,
                completedOperations: completedOperations,
                failedOperations: failedOperations,
                averageWaitTime: calculateAverageWaitTime()
            )
        }
    }
    
    /// Cancel operation by ID
    func cancelOperation(_ operationID: UUID) {
        queueLock.withLock {
            // Remove from queues
            criticalQueue.removeAll { $0.id == operationID }
            highQueue.removeAll { $0.id == operationID }
            normalQueue.removeAll { $0.id == operationID }
            lowQueue.removeAll { $0.id == operationID }
            
            // Remove from active operations
            activeOperations.remove(operationID)
            operationStartTimes.removeValue(forKey: operationID)
        }
        
        // Cancelled operation
    }
    
    /// Clear all queues (emergency stop)
    func clearAllQueues() {
        queueLock.withLock {
            // Cancel all queued operations
            let allOperations = criticalQueue + highQueue + normalQueue + lowQueue
            
            for operation in allOperations {
                if let continuation = operation.continuation as? CheckedContinuation<Any, Error> {
                    continuation.resume(throwing: PriorityQueueError.operationCancelled)
                }
            }
            
            criticalQueue.removeAll()
            highQueue.removeAll()
            normalQueue.removeAll()
            lowQueue.removeAll()
        }
        
        // Cleared all queues
    }
    
    // MARK: - Private Methods
    
    private func enqueueOperation(_ operation: QueuedOperation) {
        queueLock.withLock {
            OSAtomicIncrement64(&totalOperations)
            
            switch operation.priority {
            case .critical:
                criticalQueue.append(operation)
                
            case .high:
                highQueue.append(operation)
                
            case .normal:
                normalQueue.append(operation)
                normalPriorityWaitCount += 1
                
            case .low:
                lowQueue.append(operation)
                lowPriorityWaitCount += 1
            }
            
            // Sort queues by timestamp (FIFO within priority)
            criticalQueue.sort { $0.timestamp < $1.timestamp }
            highQueue.sort { $0.timestamp < $1.timestamp }
            normalQueue.sort { $0.timestamp < $1.timestamp }
            lowQueue.sort { $0.timestamp < $1.timestamp }
        }
    }
    
    private func dequeueNextOperation() -> QueuedOperation? {
        return queueLock.withLock {
            // Check for starvation prevention
            let shouldBoostLowPriority = lowPriorityWaitCount >= Config.starvationPreventionThreshold
            let shouldBoostNormalPriority = normalPriorityWaitCount >= Config.starvationPreventionThreshold / 2
            
            // Priority selection with starvation prevention
            if shouldBoostLowPriority && !lowQueue.isEmpty {
                lowPriorityWaitCount = 0
                return lowQueue.removeFirst()
            }
            
            if shouldBoostNormalPriority && !normalQueue.isEmpty {
                normalPriorityWaitCount = 0
                return normalQueue.removeFirst()
            }
            
            // Normal priority order
            if !criticalQueue.isEmpty {
                return criticalQueue.removeFirst()
            }
            
            if !highQueue.isEmpty {
                return highQueue.removeFirst()
            }
            
            if !normalQueue.isEmpty {
                normalPriorityWaitCount = max(0, normalPriorityWaitCount - 1)
                return normalQueue.removeFirst()
            }
            
            if !lowQueue.isEmpty {
                lowPriorityWaitCount = max(0, lowPriorityWaitCount - 1)
                return lowQueue.removeFirst()
            }
            
            return nil
        }
    }
    
    private func startQueueProcessor() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.processQueue()
        }
    }
    
    private func processQueue() async {
        // Queue processor started
        
        while true {
            // Check if there are operations to process
            guard let operation = dequeueNextOperation() else {
                // No operations, wait a bit
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                continue
            }
            
            // Wait for available slot
            await semaphore.wait()
            
            // Execute operation
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.executeOperation(operation)
            }
        }
    }
    
    private func executeOperation(_ queuedOperation: QueuedOperation) async {
        let operationID = queuedOperation.id
        let startTime = Date()
        
        // Track active operation
        queueLock.withLock {
            activeOperations.insert(operationID)
            operationStartTimes[operationID] = startTime
        }
        
        // Executing operation
        
        do {
            // Check for timeout
            let waitTime = startTime.timeIntervalSince(queuedOperation.timestamp)
            if waitTime > Config.queueTimeout {
                throw PriorityQueueError.operationTimeout
            }
            
            // Execute the actual operation
            let result = try await queuedOperation.operation()
            
            // Success
            (queuedOperation.continuation as? CheckedContinuation<Any, Error>)?.resume(returning: result)
            OSAtomicIncrement64(&completedOperations)
            
            let duration = Date().timeIntervalSince(startTime)
            // Operation completed
            
        } catch {
            // Failure
            (queuedOperation.continuation as? CheckedContinuation<Any, Error>)?.resume(throwing: error)
            OSAtomicIncrement64(&failedOperations)
            
            logger.error("❌ Operation failed: \(operationID) - \(error.localizedDescription)")
        }
        
        // Cleanup
        queueLock.withLock {
            activeOperations.remove(operationID)
            operationStartTimes.removeValue(forKey: operationID)
        }
        
        // Release semaphore
        semaphore.signal()
    }
    
    private func calculateAverageWaitTime() -> TimeInterval {
        let now = Date()
        let currentOperations = criticalQueue + highQueue + normalQueue + lowQueue
        
        guard !currentOperations.isEmpty else { return 0.0 }
        
        let totalWaitTime = currentOperations.reduce(0.0) { total, operation in
            return total + now.timeIntervalSince(operation.timestamp)
        }
        
        return totalWaitTime / Double(currentOperations.count)
    }
}

// MARK: - Supporting Types

private class QueuedOperation {
    let id: UUID
    let priority: FetchPriority
    let type: FetchType
    let timestamp: Date
    let operation: () async throws -> Any
    var continuation: Any?
    
    init<T>(
        id: UUID,
        priority: FetchPriority,
        type: FetchType,
        timestamp: Date,
        operation: @escaping () async throws -> T
    ) {
        self.id = id
        self.priority = priority
        self.type = type
        self.timestamp = timestamp
        self.operation = {
            return try await operation()
        }
    }
}

struct QueueStatistics {
    let criticalQueueSize: Int
    let highQueueSize: Int
    let normalQueueSize: Int
    let lowQueueSize: Int
    let activeOperations: Int
    let totalOperations: Int64
    let completedOperations: Int64
    let failedOperations: Int64
    let averageWaitTime: TimeInterval
    
    var totalQueueSize: Int {
        return criticalQueueSize + highQueueSize + normalQueueSize + lowQueueSize
    }
    
    var successRate: Double {
        let total = completedOperations + failedOperations
        return total > 0 ? Double(completedOperations) / Double(total) : 0.0
    }
    
    var throughput: Double {
        // Operations per minute
        return Double(completedOperations) / max(1.0, averageWaitTime / 60.0)
    }
}

enum PriorityQueueError: Error, LocalizedError {
    case operationTimeout
    case operationCancelled
    case queueFull
    
    var errorDescription: String? {
        switch self {
        case .operationTimeout:
            return "Operation timed out in queue"
        case .operationCancelled:
            return "Operation was cancelled"
        case .queueFull:
            return "Queue is full"
        }
    }
}

// MARK: - Async Semaphore (if not already defined elsewhere)

class PriorityAsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int) {
        self.value = value
    }
    
    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}

// MARK: - NSLock Extension

private extension NSLock {
    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}
