import Foundation

enum EpisodeUpdate {
    case updatePlaybackPosition(UUID, Double)
}

struct CacheStats {
    let count: Int
    let lastUpdated: Date?
    let needsRefresh: Bool
}

/// Temporary EpisodeRepository stub for build compatibility
@MainActor
class EpisodeRepository: ObservableObject {
    static let shared = EpisodeRepository()
    
    @Published var episodes: [Episode] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    var lastUpdateTime: Date?
    
    private init() {}
    
    func addNewEpisodes(_ episodes: [Episode]) async throws {
        // Stub implementation
    }
    
    func markEpisodeAsPlayed(_ episodeId: UUID) async throws {
        // Stub implementation
    }
    
    func batchUpdateEpisodes(_ updates: [EpisodeUpdate]) async throws {
        // Stub implementation
        for update in updates {
            switch update {
            case .updatePlaybackPosition(_, _):
                break
                // Migrate critical log to Logger if needed
            }
        }
    }
    
    func clearAllEpisodes() async throws {
        // Stub implementation
        print("🗑️ EpisodeRepository: Clearing all episodes")
        episodes.removeAll()
    }
    
    func getCacheStats() async -> CacheStats {
        // Stub implementation
        return CacheStats(
            count: episodes.count,
            lastUpdated: lastUpdateTime,
            needsRefresh: false
        )
    }
} 