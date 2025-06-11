import Foundation
import BackgroundTasks
import UIKit
#if canImport(OSLog)
import OSLog
#endif

/// Background worker that processes episode fetch requests
/// Integrates with BGAppRefreshTask for proper iOS background scheduling
@MainActor
class EpisodeFetchWorker: ObservableObject {
    static let shared = EpisodeFetchWorker()
    
    // MARK: - Configuration
    
    private struct Config {
        static let backgroundTaskIdentifier = "com.chenkahana.Jimmy.episodeFetch"
        static let maxConcurrentRequests = 3
        static let requestTimeoutInterval: TimeInterval = 30
        static let maxBackgroundTime: TimeInterval = 25 // Leave 5s buffer for iOS
        static let queuePersistenceKey = "episodeFetchQueue"
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var queueCount: Int = 0
    @Published private(set) var lastProcessedTime: Date?
    @Published private(set) var processingStats: ProcessingStats = ProcessingStats()
    
    // MARK: - Private Properties
    
    /// Priority queue for fetch requests
    private var requestQueue: PriorityQueue<FetchEpisodesRequest> = PriorityQueue()
    
    /// Currently processing requests
    private var activeRequests: Set<UUID> = []
    
    /// Queue management
    private let queueLock = NSLock()
    private let processingQueue = DispatchQueue(label: "episode-fetch-worker", qos: .userInitiated)
    private let persistenceQueue = DispatchQueue(label: "episode-fetch-persistence", qos: .utility)
    
    /// Services
    private let repository = EpisodeRepository.shared
    private let podcastService = PodcastService.shared
    private let optimizedPodcastService = OptimizedPodcastService.shared
    private let networkManager = OptimizedNetworkManager.shared
    
    /// Background task management
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTaskStartTime: Date?
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "com.jimmy.app", category: "fetch-worker")
    #endif
    
    // MARK: - Processing Statistics
    
    struct ProcessingStats: Codable {
        var totalRequests: Int = 0
        var successfulRequests: Int = 0
        var failedRequests: Int = 0
        var averageProcessingTime: TimeInterval = 0
        var lastResetTime: Date = Date()
        
        var successRate: Double {
            guard totalRequests > 0 else { return 0 }
            return Double(successfulRequests) / Double(totalRequests)
        }
        
        mutating func recordSuccess(processingTime: TimeInterval) {
            totalRequests += 1
            successfulRequests += 1
            updateAverageProcessingTime(processingTime)
        }
        
        mutating func recordFailure(processingTime: TimeInterval) {
            totalRequests += 1
            failedRequests += 1
            updateAverageProcessingTime(processingTime)
        }
        
        private mutating func updateAverageProcessingTime(_ newTime: TimeInterval) {
            averageProcessingTime = (averageProcessingTime * Double(totalRequests - 1) + newTime) / Double(totalRequests)
        }
        
        mutating func reset() {
            totalRequests = 0
            successfulRequests = 0
            failedRequests = 0
            averageProcessingTime = 0
            lastResetTime = Date()
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupBackgroundTaskHandler()
        loadPersistedQueue()
        
        // Start processing immediately if there are queued requests
        if !requestQueue.isEmpty {
            Task {
                await startProcessing()
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Enqueue a fetch request
    func enqueue(_ request: FetchEpisodesRequest) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                // Check for duplicate requests
                if !requestQueue.contains(where: { $0.id == request.id }) {
                    requestQueue.enqueue(request)
                    
                    #if canImport(OSLog)
                    logger.info("📥 Enqueued request: \(request.requestType.rawValue) (priority: \(request.priority.rawValue))")
                    #endif
                    
                    self.queueCount = self.requestQueue.count
                    
                    // Persist queue
                    persistQueue()
                    
                    // Start processing if not already running
                    if !isProcessing {
                        Task {
                            await startProcessing()
                        }
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Process all queued requests immediately (for user-initiated actions)
    func processImmediately() async {
        await startProcessing()
    }
    
    /// Clear all queued requests
    func clearQueue() async {
        await MainActor.run { [weak self] in
            self?.requestQueue.removeAll()
            self?.queueCount = 0
        }
        
        persistQueue()
        
        #if canImport(OSLog)
        logger.info("🗑️ Cleared all queued requests")
        #endif
    }
    
    /// Get current queue status
    func getQueueStatus() -> (count: Int, processing: Bool, nextRequest: FetchEpisodesRequest?) {
        return (
            count: requestQueue.count,
            processing: isProcessing,
            nextRequest: requestQueue.peek()
        )
    }
    
    /// Reset processing statistics
    func resetProcessingStats() async {
        await MainActor.run { [weak self] in
            self?.processingStats.reset()
        }
        
        #if canImport(OSLog)
        logger.info("📊 Processing stats reset")
        #endif
    }
    
    // MARK: - Background Task Integration
    
    private func setupBackgroundTaskHandler() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Config.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        #if canImport(OSLog)
        logger.info("🔄 Background fetch task started")
        #endif
        
        backgroundTaskStartTime = Date()
        
        // Set expiration handler
        task.expirationHandler = { [weak self] in
            #if canImport(OSLog)
            self?.logger.warning("⏰ Background task expired")
            #endif
            task.setTaskCompleted(success: false)
            Task { @MainActor in
                await self?.stopProcessing()
            }
        }
        
        // Process background requests
        Task {
            let success = await processBackgroundRequests()
            task.setTaskCompleted(success: success)
            
            #if canImport(OSLog)
            self.logger.info("✅ Background task completed with success: \(success)")
            #endif
        }
    }
    
    private func processBackgroundRequests() async -> Bool {
        // Add a background refresh request if queue is empty
        if requestQueue.isEmpty {
            await enqueue(.backgroundRefresh())
        }
        
        // Process with time limit
        let startTime = Date()
        var success = true
        
        while !requestQueue.isEmpty && 
              Date().timeIntervalSince(startTime) < Config.maxBackgroundTime {
            
            guard let request = await dequeueNextRequest() else { break }
            
            let requestSuccess = await processRequest(request)
            if !requestSuccess {
                success = false
            }
            
            // Small delay between requests in background
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        return success
    }
    
    // MARK: - Request Processing
    
    private func startProcessing() async {
        guard !isProcessing else { return }
        
        await MainActor.run { [weak self] in
            self?.isProcessing = true
        }
        
        #if canImport(OSLog)
        logger.info("🚀 Starting episode fetch processing")
        #endif
        
        // Start background task for foreground processing
        startBackgroundTask()
        
        await processAllRequests()
        
        await MainActor.run { [weak self] in
            self?.isProcessing = false
            self?.lastProcessedTime = Date()
        }
        
        endBackgroundTask()
        
        #if canImport(OSLog)
        logger.info("🏁 Finished episode fetch processing")
        #endif
    }
    
    private func stopProcessing() async {
        await MainActor.run { [weak self] in
            self?.isProcessing = false
        }
        
        endBackgroundTask()
    }
    
    private func processAllRequests() async {
        while !requestQueue.isEmpty {
            guard let request = await dequeueNextRequest() else { break }
            
            // Check if we're running out of background time
            if let startTime = backgroundTaskStartTime,
               Date().timeIntervalSince(startTime) > Config.maxBackgroundTime - 5 {
                // Re-queue the request for later
                await MainActor.run { [weak self] in
                    self?.requestQueue.enqueue(request)
                }
                break
            }
            
            let _ = await processRequest(request)
            
            // Update queue count
            await MainActor.run { [weak self] in
                self?.queueCount = self?.requestQueue.count ?? 0
            }
        }
    }
    
    func processRequest(_ request: FetchEpisodesRequest) async -> Bool {
        let startTime = Date()
        
        #if canImport(OSLog)
        logger.info("🔄 Processing request: \(request.requestType.rawValue)")
        #endif
        
        // Mark as active
        activeRequests.insert(request.id)
        defer { activeRequests.remove(request.id) }
        
        do {
            let success = try await executeRequest(request)
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            if success {
                await MainActor.run { [weak self] in
                    self?.processingStats.recordSuccess(processingTime: processingTime)
                }
                
                #if canImport(OSLog)
                logger.info("✅ Request completed successfully in \(processingTime)s")
                #endif
                
                return true
            } else {
                await handleRequestFailure(request, processingTime: Date().timeIntervalSince(startTime))
                return false
            }
            
        } catch {
            await handleRequestError(request, error: error, processingTime: Date().timeIntervalSince(startTime))
            return false
        }
    }
    
    private func executeRequest(_ request: FetchEpisodesRequest) async throws -> Bool {
        await repository.setLoading(true)
        defer {
            Task {
                await repository.setLoading(false)
            }
        }
        
        switch request.requestType {
        case .allPodcasts, .userInitiated, .backgroundRefresh:
            return await fetchAllPodcastEpisodes()
            
        case .singlePodcast:
            guard let podcastID = request.podcastID else { return false }
            return await fetchSinglePodcastEpisodes(podcastID: podcastID)
            
        case .refreshCache:
            return await refreshCacheFromRepository()
        }
    }
    
    private func fetchAllPodcastEpisodes() async -> Bool {
        let podcasts = podcastService.loadPodcasts()
        guard !podcasts.isEmpty else { return true }
        
        var allEpisodes: [Episode] = []
        
        // Process podcasts in batches
        let batchSize = 3
        let batches = podcasts.chunked(into: batchSize)
        
        for batch in batches {
            let batchEpisodes = await withTaskGroup(of: [Episode].self) { group in
                for podcast in batch {
                    group.addTask {
                        await self.fetchEpisodesForPodcast(podcast)
                    }
                }
                
                var episodes: [Episode] = []
                for await batchResult in group {
                    episodes.append(contentsOf: batchResult)
                }
                return episodes
            }
            
            allEpisodes.append(contentsOf: batchEpisodes)
            
            // Small delay between batches
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        // Update repository
        do {
            try await repository.updateEpisodes(allEpisodes, source: .backgroundRefresh)
            
            // Post notification
            NotificationCenter.default.post(name: .episodeRepositoryUpdated, object: nil)
            
            return true
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Failed to update repository: \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    private func fetchSinglePodcastEpisodes(podcastID: UUID) async -> Bool {
        let podcasts = podcastService.loadPodcasts()
        guard let podcast = podcasts.first(where: { $0.id == podcastID }) else { return false }
        
        let episodes = await fetchEpisodesForPodcast(podcast)
        
        if !episodes.isEmpty {
            do {
                try await repository.addNewEpisodes(episodes)
                NotificationCenter.default.post(name: .episodeRepositoryUpdated, object: nil)
                return true
            } catch {
                #if canImport(OSLog)
                logger.error("❌ Failed to add new episodes: \(error.localizedDescription)")
                #endif
                return false
            }
        }
        
        return false
    }
    
    private func refreshCacheFromRepository() async -> Bool {
        // This is a lightweight operation that just refreshes the cache metadata
        let stats = await repository.getCacheStats()
        
        #if canImport(OSLog)
        logger.info("📊 Cache refresh: \(stats.count) episodes, needs refresh: \(stats.needsRefresh)")
        #endif
        
        return true
    }
    
    private func fetchEpisodesForPodcast(_ podcast: Podcast) async -> [Episode] {
        return await withCheckedContinuation { continuation in
            podcastService.fetchEpisodes(for: podcast) { episodes in
                continuation.resume(returning: episodes)
            }
        }
    }
    
    // MARK: - Error Handling
    
    private func handleRequestFailure(_ request: FetchEpisodesRequest, processingTime: TimeInterval) async {
        await MainActor.run { [weak self] in
            self?.processingStats.recordFailure(processingTime: processingTime)
        }
        
        // Attempt retry if possible
        if let retryRequest = request.createRetryRequest() {
            #if canImport(OSLog)
            logger.info("🔄 Retrying request (attempt \(retryRequest.retryCount + 1)/\(retryRequest.maxRetries))")
            #endif
            
            // Add delay before retry
            try? await Task.sleep(nanoseconds: UInt64(request.retryDelay * 1_000_000_000))
            
            await MainActor.run { [weak self] in
                self?.requestQueue.enqueue(retryRequest)
            }
        } else {
            #if canImport(OSLog)
            logger.error("❌ Request failed after all retries: \(request.requestType.rawValue)")
            #endif
            
            NotificationCenter.default.post(
                name: .episodeRepositoryError,
                object: "Failed to fetch episodes after \(request.maxRetries) attempts"
            )
        }
    }
    
    private func handleRequestError(_ request: FetchEpisodesRequest, error: Error, processingTime: TimeInterval) async {
        #if canImport(OSLog)
        logger.error("❌ Request error: \(error.localizedDescription)")
        #endif
        
        await handleRequestFailure(request, processingTime: processingTime)
    }
    
    // MARK: - Queue Management
    
    private func dequeueNextRequest() async -> FetchEpisodesRequest? {
        return await MainActor.run { [weak self] in
            return self?.requestQueue.dequeue()
        }
    }
    
    private func persistQueue() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            let queueData = await MainActor.run {
                return Array(self.requestQueue)
            }
            
            _ = FileStorage.shared.save(queueData, to: "fetchRequestQueue.json")
            
            #if canImport(OSLog)
            self.logger.info("💾 Persisted \(queueData.count) requests to disk")
            #endif
        }
    }
    
    private func loadPersistedQueue() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            let queueData: [FetchEpisodesRequest] = FileStorage.shared.load([FetchEpisodesRequest].self, from: "fetchRequestQueue.json") ?? []
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // Filter out expired requests
                let validRequests = queueData.filter { !$0.isExpired }
                
                for request in validRequests {
                    self.requestQueue.enqueue(request)
                }
                
                self.queueCount = self.requestQueue.count
                
                #if canImport(OSLog)
                self.logger.info("📱 Loaded \(queueData.count) persisted requests (\(self.requestQueue.count) valid)")
                #endif
            }
        }
    }
    
    // MARK: - Background Task Management
    
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "EpisodeFetch") { [weak self] in
            self?.endBackgroundTask()
        }
        backgroundTaskStartTime = Date()
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        backgroundTaskStartTime = nil
    }
}

// MARK: - Priority Queue Implementation

private struct PriorityQueue<T: Comparable> {
    private var elements: [T] = []
    
    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }
    
    mutating func enqueue(_ element: T) {
        elements.append(element)
        elements.sort { $0 > $1 } // Higher priority first
    }
    
    mutating func dequeue() -> T? {
        return elements.isEmpty ? nil : elements.removeFirst()
    }
    
    func peek() -> T? {
        return elements.first
    }
    
    mutating func removeAll() {
        elements.removeAll()
    }
    
    func contains(where predicate: (T) -> Bool) -> Bool {
        return elements.contains(where: predicate)
    }
    
    mutating func removeExpired() where T == FetchEpisodesRequest {
        elements.removeAll { $0.isExpired }
    }
}

extension PriorityQueue: Collection {
    var startIndex: Int { elements.startIndex }
    var endIndex: Int { elements.endIndex }
    
    subscript(index: Int) -> T {
        return elements[index]
    }
    
    func index(after i: Int) -> Int {
        return elements.index(after: i)
    }
}

// MARK: - FetchEpisodesRequest Comparable Conformance

extension FetchEpisodesRequest: Comparable {
    static func < (lhs: FetchEpisodesRequest, rhs: FetchEpisodesRequest) -> Bool {
        // Higher priority first, then newer timestamp
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.timestamp < rhs.timestamp
    }
} 