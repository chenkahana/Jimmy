import Foundation

struct ProcessingStats {
    var totalRequests: Int = 0
    var failedRequests: Int = 0
    var averageProcessingTime: Double = 0.0
    var successRate: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(totalRequests - failedRequests) / Double(totalRequests)
    }
}

/// Temporary EpisodeFetchWorker stub for build compatibility
@MainActor
class EpisodeFetchWorker: ObservableObject {
    static let shared = EpisodeFetchWorker()
    
    @Published var queueCount: Int = 0
    @Published var isProcessing: Bool = false
    
    var lastProcessedTime: Date?
    var processingStats = ProcessingStats()
    
    private init() {}
    
    func getQueueStatus() -> (count: Int, processing: Bool, nextRequest: FetchEpisodesRequest?) {
        return (0, false, nil)
    }
    
    func processImmediately() async {
        // Stub implementation
    }
    
    func clearQueue() async {
        // Stub implementation
        queueCount = 0
    }
    
    func resetProcessingStats() async {
        // Stub implementation
        processingStats = ProcessingStats()
    }
} 