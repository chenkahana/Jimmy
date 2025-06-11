import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(OSLog)
import OSLog
#endif

/// Specialized request queue for discovery data fetching operations
/// Handles deduplication, priority management, and processing statistics
@MainActor
final class DiscoveryRequestQueue: ObservableObject {
    static let shared = DiscoveryRequestQueue()
    
    // MARK: - Published Properties
    
    @Published private(set) var queueCount: Int = 0
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var processingStats: ProcessingStats = ProcessingStats()
    
    // MARK: - Processing Statistics
    
    struct ProcessingStats: Codable {
        var totalRequests: Int = 0
        var completedRequests: Int = 0
        var failedRequests: Int = 0
        var averageProcessingTime: TimeInterval = 0
        var lastProcessingTime: Date?
        
        var successRate: Double {
            guard totalRequests > 0 else { return 0 }
            return Double(completedRequests) / Double(totalRequests)
        }
        
        mutating func recordSuccess(processingTime: TimeInterval) {
            totalRequests += 1
            completedRequests += 1
            updateAverageTime(processingTime)
            lastProcessingTime = Date()
        }
        
        mutating func recordFailure(processingTime: TimeInterval) {
            totalRequests += 1
            failedRequests += 1
            updateAverageTime(processingTime)
            lastProcessingTime = Date()
        }
        
        private mutating func updateAverageTime(_ newTime: TimeInterval) {
            let totalCompleted = completedRequests + failedRequests
            if totalCompleted > 0 {
                averageProcessingTime = (averageProcessingTime * Double(totalCompleted - 1) + newTime) / Double(totalCompleted)
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var queue: PriorityQueue<FetchDiscoveryRequest> = PriorityQueue()
    private var activeRequests: Set<UUID> = []
    private var completedRequests: Set<UUID> = []
    private let worker = DiscoveryFetchWorker.shared
    private let repository = DiscoveryRepository.shared
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "DiscoveryRequestQueue")
    #endif
    
    // MARK: - Configuration
    
    private struct Config {
        static let maxConcurrentRequests = 3
        static let queuePersistenceKey = "discoveryRequestQueue"
        static let maxQueueSize = 50
        static let requestTimeoutInterval: TimeInterval = 30
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
        loadPersistedQueue()
    }
    
    // MARK: - Public Interface
    
    /// Enqueue a request with automatic deduplication
    func enqueue(_ request: FetchDiscoveryRequest) async {
        // Check for duplicate requests
        guard !queue.contains(where: { $0.requestType == request.requestType && !$0.isExpired }) else {
            #if canImport(OSLog)
            logger.info("🔄 Skipping duplicate request: \(request.requestType.rawValue)")
            #endif
            return
        }
        
        // Remove expired requests
        queue.removeAll { $0.isExpired }
        
        // Limit queue size
        if queue.count >= Config.maxQueueSize {
            _ = queue.dequeue() // Remove oldest request
        }
        
        queue.enqueue(request)
        queueCount = queue.count
        
        #if canImport(OSLog)
        logger.info("📥 Enqueued discovery request: \(request.requestType.rawValue) (priority: \(request.priority.rawValue))")
        #endif
        
        persistQueue()
        
        // Start processing if not already running
        if !isProcessing {
            await processNext()
        }
    }
    
    /// Process all queued requests immediately (for user-initiated actions)
    func processImmediately() async {
        await processNext()
    }
    
    /// Clear all queued requests
    func clearQueue() async {
        queue.removeAll()
        queueCount = 0
        persistQueue()
        
        #if canImport(OSLog)
        logger.info("🗑️ Cleared discovery request queue")
        #endif
    }
    
    /// Get current queue status
    func getQueueStatus() -> (count: Int, processing: Bool, nextRequest: FetchDiscoveryRequest?) {
        return (
            count: queue.count,
            processing: isProcessing,
            nextRequest: queue.peek()
        )
    }
    
    /// Reset processing statistics
    func resetStats() async {
        processingStats = ProcessingStats()
    }
    
    // MARK: - Private Methods
    
    /// Process next request in queue
    private func processNext() async {
        guard !isProcessing else { return }
        guard !queue.isEmpty else { return }
        
        isProcessing = true
        
        #if canImport(OSLog)
        logger.info("🚀 Starting discovery request processing")
        #endif
        
        while !queue.isEmpty && activeRequests.count < Config.maxConcurrentRequests {
            guard let request = queue.dequeue() else { break }
            
            // Skip expired requests
            if request.isExpired {
                #if canImport(OSLog)
                logger.info("⏰ Skipping expired request: \(request.requestType.rawValue)")
                #endif
                continue
            }
            
            // Skip already completed requests
            if completedRequests.contains(request.id) {
                continue
            }
            
            queueCount = queue.count
            
            // Process request concurrently
            Task.detached(priority: request.priority.taskPriority) { [weak self] in
                await self?.processRequest(request)
            }
            
            // Small delay between requests to prevent overwhelming
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Wait for all active requests to complete
        while !activeRequests.isEmpty {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        isProcessing = false
        
        #if canImport(OSLog)
        logger.info("🏁 Finished processing discovery queue")
        #endif
        
        persistQueue()
    }
    
    /// Process individual request
    private func processRequest(_ request: FetchDiscoveryRequest) async {
        let startTime = Date()
        activeRequests.insert(request.id)
        
        defer {
            activeRequests.remove(request.id)
            completedRequests.insert(request.id)
        }
        
        do {
            let success = try await worker.processRequest(request)
            let processingTime = Date().timeIntervalSince(startTime)
            
            await updateProcessingStats(success: success, processingTime: processingTime)
            
            if success {
                #if canImport(OSLog)
                logger.info("✅ Discovery request completed: \(request.requestType.rawValue) (\(String(format: "%.2f", processingTime))s)")
                #endif
            } else {
                #if canImport(OSLog)
                logger.warning("⚠️ Discovery request failed: \(request.requestType.rawValue)")
                #endif
                
                // Attempt retry if possible
                if let retryRequest = request.createRetryRequest() {
                    await enqueue(retryRequest)
                }
            }
            
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            await updateProcessingStats(success: false, processingTime: processingTime)
            
            #if canImport(OSLog)
            logger.error("❌ Discovery request error: \(request.requestType.rawValue) - \(error.localizedDescription)")
            #endif
            
            // Attempt retry if possible
            if let retryRequest = request.createRetryRequest() {
                await enqueue(retryRequest)
            }
        }
    }
    
    /// Update processing statistics
    private func updateProcessingStats(success: Bool, processingTime: TimeInterval) async {
        if success {
            processingStats.recordSuccess(processingTime: processingTime)
        } else {
            processingStats.recordFailure(processingTime: processingTime)
        }
    }
    
    /// Setup notification observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .discoveryDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Queue might need processing after discovery updates
            Task { @MainActor in
                await self?.processNext()
            }
        }
        
        // Listen for app lifecycle events
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.persistQueue()
            }
        }
    }
    
    /// Persist queue to disk
    private func persistQueue() {
        let queueData = queue.elements
        if let encoded = try? JSONEncoder().encode(queueData) {
            UserDefaults.standard.set(encoded, forKey: Config.queuePersistenceKey)
        }
    }
    
    /// Load persisted queue from disk
    private func loadPersistedQueue() {
        guard let data = UserDefaults.standard.data(forKey: Config.queuePersistenceKey),
              let requests = try? JSONDecoder().decode([FetchDiscoveryRequest].self, from: data) else {
            return
        }
        
        // Filter out expired requests
        let validRequests = requests.filter { !$0.isExpired }
        
        for request in validRequests {
            queue.enqueue(request)
        }
        
        queueCount = queue.count
        
        #if canImport(OSLog)
        logger.info("📱 Loaded \(validRequests.count) persisted discovery requests (\(requests.count - validRequests.count) expired)")
        #endif
    }
}

// MARK: - Priority Queue Implementation

private struct PriorityQueue<T: Comparable> {
    private var heap: [T] = []
    
    var count: Int { heap.count }
    var isEmpty: Bool { heap.isEmpty }
    var elements: [T] { heap }
    
    mutating func enqueue(_ element: T) {
        heap.append(element)
        siftUp(heap.count - 1)
    }
    
    mutating func dequeue() -> T? {
        guard !heap.isEmpty else { return nil }
        
        if heap.count == 1 {
            return heap.removeFirst()
        }
        
        let result = heap[0]
        heap[0] = heap.removeLast()
        siftDown(0)
        return result
    }
    
    func peek() -> T? {
        return heap.first
    }
    
    mutating func removeAll() {
        heap.removeAll()
    }
    
    mutating func removeAll(where predicate: (T) -> Bool) {
        heap.removeAll(where: predicate)
        // Rebuild heap property
        for i in stride(from: heap.count / 2 - 1, through: 0, by: -1) {
            siftDown(i)
        }
    }
    
    func contains(where predicate: (T) -> Bool) -> Bool {
        return heap.contains(where: predicate)
    }
    
    private mutating func siftUp(_ index: Int) {
        let parent = (index - 1) / 2
        if index > 0 && heap[index] > heap[parent] {
            heap.swapAt(index, parent)
            siftUp(parent)
        }
    }
    
    private mutating func siftDown(_ index: Int) {
        let leftChild = 2 * index + 1
        let rightChild = 2 * index + 2
        var largest = index
        
        if leftChild < heap.count && heap[leftChild] > heap[largest] {
            largest = leftChild
        }
        
        if rightChild < heap.count && heap[rightChild] > heap[largest] {
            largest = rightChild
        }
        
        if largest != index {
            heap.swapAt(index, largest)
            siftDown(largest)
        }
    }
}

// MARK: - FetchDiscoveryRequest Comparable Conformance

extension FetchDiscoveryRequest: Comparable {
    static func < (lhs: FetchDiscoveryRequest, rhs: FetchDiscoveryRequest) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.timestamp < rhs.timestamp
    }
} 