import Foundation

enum CacheStatus {
    case loading
    case loaded
    case error
    case fresh
    case stale
    
    var displayText: String {
        switch self {
        case .loading: return "Loading"
        case .loaded: return "Loaded"
        case .error: return "Error"
        case .fresh: return "Fresh"
        case .stale: return "Stale"
        }
    }
}

/// Temporary EnhancedEpisodeController stub for build compatibility
@MainActor
class EnhancedEpisodeController: ObservableObject {
    static let shared = EnhancedEpisodeController()
    
    @Published var cacheStatus: CacheStatus = .loaded
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String?
    
    var episodeCount: Int = 0
    
    private init() {}
    
    func refreshEpisodes() async {
        // Stub implementation
        print("🔄 Refreshing episodes")
        isRefreshing = true
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        isRefreshing = false
    }
    
    func getDebugInfo() -> String {
        // Stub implementation
        return "Debug info: Cache status = \(cacheStatus.displayText), Episode count = \(episodeCount)"
    }
} 