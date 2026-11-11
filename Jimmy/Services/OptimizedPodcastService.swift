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
                    let parser = ConcreteRSSParser()
                    let (data, _, _) = try await UnifiedNetworkService.shared.fetchRSSFeed(from: podcast.feedURL, etag: nil, lastModified: nil)
                    let (episodes, _) = try await parser.parse(data: data, podcastID: podcast.id, feedURL: podcast.feedURL)
                    
                    lock.lock()
                    results[podcast.id] = episodes
                    lock.unlock()
                } catch {
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