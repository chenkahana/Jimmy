import Foundation
import OSLog
import Combine

/// Request queue errors
enum RequestQueueError: Error {
    case processingFailed
    case workerUnavailable
    case invalidRequest
}

/// Unified request queue for episode fetching operations
/// Handles deduplication, priority management, and processing statistics
@MainActor
final class RequestQueue: ObservableObject {
    static let shared = RequestQueue()
    
    // MARK: - Published Properties
    
    @Published private(set) var queueCount: Int = 0
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var processingStats: ProcessingStats = ProcessingStats()
    
    // MARK: - Private Properties
    
    private var queue: PriorityQueue<FetchEpisodesRequest> = PriorityQueue()
    private var activeRequests: Set<UUID> = []
    private var completedRequests: Set<UUID> = []
    private let worker = EpisodeFetchWorker.shared
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "RequestQueue")
    #endif
    
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
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
        loadPersistedQueue()
    }
    
    // MARK: - Public Interface
    
    /// Enqueue a request with automatic deduplication
    func enqueue(_ request: FetchEpisodesRequest, completion: @escaping (Result<[Episode], Error>) -> Void = { _ in }) {
        // Check for duplicate requests
        if isDuplicateRequest(request) {
            #if canImport(OSLog)
            logger.info("🔄 Skipping duplicate request: \(request.requestType.rawValue)")
            #endif
            return
        }
        
        // Add to queue
        queue.enqueue(request)
        queueCount = queue.count
        
        // Update statistics
        processingStats.totalRequests += 1
        
        #if canImport(OSLog)
        logger.info("📥 Enqueued request: \(request.requestType.rawValue) (priority: \(request.priority.rawValue))")
        #endif
        
        // Start processing if not already running
        if !isProcessing {
            startProcessing()
        }
        
        // Persist queue state
        persistQueue()
    }
    
    /// Enqueue multiple requests
    func enqueue(_ requests: [FetchEpisodesRequest]) {
        for request in requests {
            enqueue(request)
        }
    }
    
    /// Clear all pending requests
    func clearQueue() {
        queue.removeAll()
        activeRequests.removeAll()
        queueCount = 0
        
        #if canImport(OSLog)
        logger.info("🗑️ Cleared request queue")
        #endif
        
        persistQueue()
    }
    
    /// Get current queue status
    func getQueueStatus() -> (count: Int, isProcessing: Bool, nextRequest: FetchEpisodesRequest?) {
        return (
            count: queue.count,
            isProcessing: isProcessing,
            nextRequest: queue.peek()
        )
    }
    
    /// Force process next request
    func processNext() {
        guard !queue.isEmpty else { return }
        
        if !isProcessing {
            startProcessing()
        }
    }
    
    // MARK: - Private Methods
    
    /// Check if request is duplicate
    private func isDuplicateRequest(_ request: FetchEpisodesRequest) -> Bool {
        // Check active requests
        if activeRequests.contains(request.id) {
            return true
        }
        
        // Check queue for similar requests
        let similarRequests = queue.filter { queuedRequest in
            queuedRequest.requestType == request.requestType &&
            queuedRequest.podcastID == request.podcastID
        }
        
        return !similarRequests.isEmpty
    }
    
    /// Start processing queue
    private func startProcessing() {
        guard !isProcessing && !queue.isEmpty else { return }
        
        isProcessing = true
        
        #if canImport(OSLog)
        logger.info("🚀 Starting request processing")
        #endif
        
        Task {
            await processQueue()
        }
    }
    
    /// Process queue asynchronously
    private func processQueue() async {
        while !queue.isEmpty {
            guard let request = queue.dequeue() else { break }
            
            queueCount = queue.count
            activeRequests.insert(request.id)
            
            let startTime = Date()
            
            #if canImport(OSLog)
            logger.info("⚡ Processing request: \(request.requestType.rawValue)")
            #endif
            
            do {
                // Process request through worker
                let episodes = try await processRequest(request)
                
                // Update statistics
                let processingTime = Date().timeIntervalSince(startTime)
                await updateProcessingStats(success: true, processingTime: processingTime)
                
                #if canImport(OSLog)
                logger.info("✅ Completed request: \(request.requestType.rawValue) (\(episodes.count) episodes)")
                #endif
                
            } catch {
                #if canImport(OSLog)
                logger.error("❌ Failed request: \(request.requestType.rawValue) - \(error.localizedDescription)")
                #endif
                
                // Handle retry logic
                if let retryRequest = request.createRetryRequest() {
                    queue.enqueue(retryRequest)
                    queueCount = queue.count
                    
                    #if canImport(OSLog)
                    logger.info("🔄 Retrying request (attempt \(retryRequest.retryCount + 1))")
                    #endif
                } else {
                    // Update statistics for failed request
                    await updateProcessingStats(success: false, processingTime: Date().timeIntervalSince(startTime))
                }
            }
            
            activeRequests.remove(request.id)
            completedRequests.insert(request.id)
            
            // Small delay between requests to prevent overwhelming
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        isProcessing = false
        
        #if canImport(OSLog)
        logger.info("🏁 Finished processing queue")
        #endif
        
        persistQueue()
    }
    
    /// Process individual request
    private func processRequest(_ request: FetchEpisodesRequest) async throws -> [Episode] {
        // Call the worker's public processRequest method
        let success = await worker.processRequest(request)
        if success {
            // Return empty array for now - the actual episodes are handled by the repository
            return []
        } else {
            throw RequestQueueError.processingFailed
        }
    }
    
    /// Update processing statistics
    private func updateProcessingStats(success: Bool, processingTime: TimeInterval) async {
        if success {
            processingStats.completedRequests += 1
        } else {
            processingStats.failedRequests += 1
        }
        
        // Update average processing time
        let totalCompleted = processingStats.completedRequests + processingStats.failedRequests
        if totalCompleted > 0 {
            processingStats.averageProcessingTime = 
                (processingStats.averageProcessingTime * Double(totalCompleted - 1) + processingTime) / Double(totalCompleted)
        }
        
        processingStats.lastProcessingTime = Date()
    }
    
    /// Setup notification observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .episodesUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Queue might need processing after episode updates
            Task { @MainActor in
                self?.processNext()
            }
        }
    }
    
    /// Persist queue to disk
    private func persistQueue() {
        let queueData = Array(self.queue)
        _ = FileStorage.shared.save(queueData, to: "requestQueue.json")
    }
    
    /// Load persisted queue from disk
    private func loadPersistedQueue() {
        let queueData: [FetchEpisodesRequest] = FileStorage.shared.load([FetchEpisodesRequest].self, from: "requestQueue.json") ?? []
        
        for request in queueData {
            // Only load non-expired requests
            if !request.isExpired {
                queue.enqueue(request)
            }
        }
        
        queueCount = queue.count
        
        #if canImport(OSLog)
        logger.info("📱 Loaded \(queueData.count) persisted requests (\(self.queue.count) valid)")
        #endif
    }
}

// MARK: - Priority Queue Implementation

private struct PriorityQueue<T: Comparable> {
    private var elements: [T] = []
    
    var isEmpty: Bool {
        return elements.isEmpty
    }
    
    var count: Int {
        return elements.count
    }
    
    mutating func enqueue(_ element: T) {
        elements.append(element)
        elements.sort { $0 > $1 } // Higher priority first
    }
    
    mutating func dequeue() -> T? {
        return isEmpty ? nil : elements.removeFirst()
    }
    
    func peek() -> T? {
        return elements.first
    }
    
    mutating func removeAll() {
        elements.removeAll()
    }
    
    func filter(_ predicate: (T) -> Bool) -> [T] {
        return elements.filter(predicate)
    }
}

extension PriorityQueue: Sequence {
    func makeIterator() -> Array<T>.Iterator {
        return elements.makeIterator()
    }
}

// Note: FetchEpisodesRequest Comparable conformance is defined in EpisodeFetchWorker.swift

// MARK: - Convenience Methods

extension RequestQueue {
    /// Enqueue user-initiated refresh
    func enqueueUserRefresh() {
        enqueue(.userInitiatedRefresh())
    }
    
    /// Enqueue background refresh
    func enqueueBackgroundRefresh() {
        enqueue(.backgroundRefresh())
    }
    
    /// Enqueue single podcast refresh
    func enqueuePodcastRefresh(_ podcastID: UUID, priority: FetchEpisodesRequest.Priority = .normal) {
        enqueue(.singlePodcast(podcastID, priority: priority))
    }
    
    /// Enqueue cache refresh
    func enqueueCacheRefresh() {
        enqueue(.refreshCache())
    }
} 