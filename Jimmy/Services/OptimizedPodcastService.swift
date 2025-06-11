import Foundation

/// OptimizedPodcastService handles batch podcast operations with performance optimizations
class OptimizedPodcastService {
    static let shared = OptimizedPodcastService()
    
    private init() {}
    
    func batchFetchEpisodes(for podcasts: [Podcast], completion: @escaping ([UUID: [Episode]]) -> Void) {
        guard !podcasts.isEmpty else {
            completion([:])
            return
        }
        
        var results: [UUID: [Episode]] = [:]
        let group = DispatchGroup()
        let lock = NSLock()
        
        // Fetch episodes for each podcast concurrently
        for podcast in podcasts {
            group.enter()
            
            Task {
                do {
                    let parser = RSSParser(podcastID: podcast.id)
                    let (episodes, _) = try await parser.parse(from: podcast.feedURL)
                    
                    lock.lock()
                    results[podcast.id] = episodes
                    lock.unlock()
                    
                    print("✅ Fetched \(episodes.count) episodes for \(podcast.title)")
                } catch {
                    print("❌ Failed to fetch episodes for \(podcast.title): \(error.localizedDescription)")
                    
                    lock.lock()
                    results[podcast.id] = []
                    lock.unlock()
                }
                
                group.leave()
            }
        }
        
        // Wait for all fetches to complete
        group.notify(queue: .main) {
            completion(results)
        }
    }
} 