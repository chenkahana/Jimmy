import Foundation

/// FetchWorker handles background episode fetching operations
class FetchWorker {
    static let shared = FetchWorker()
    
    private init() {}
    
    func batchFetchEpisodes(for podcasts: [Podcast]) async -> [UUID: [Episode]] {
        guard !podcasts.isEmpty else {
            return [:]
        }
        
        var results: [UUID: [Episode]] = [:]
        
        // Use TaskGroup for concurrent fetching
        await withTaskGroup(of: (UUID, [Episode]).self) { group in
            for podcast in podcasts {
                group.addTask {
                    do {
                        let parser = RSSParser(podcastID: podcast.id)
                        let (episodes, _) = try await parser.parse(from: podcast.feedURL)
                        return (podcast.id, episodes)
                    } catch {
                        return (podcast.id, [])
                    }
                }
            }
            
            for await (podcastID, episodes) in group {
                results[podcastID] = episodes
            }
        }
        
        return results
    }
} 