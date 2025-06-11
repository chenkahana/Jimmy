import Foundation
import OSLog

/// FetchWorker following CHAT_HELP.md specification
/// Uses Task.detached(priority:.utility) + GCD concurrent queue + barrier writes
final class FetchWorker {
    static let shared = FetchWorker()
    
    // MARK: - Configuration
    private struct Config {
        static let maxConcurrentFetches = 4
        static let batchSize = 10
    }
    
    // MARK: - Properties
    private let fetchQueue = DispatchQueue(label: "com.app.podcast.fetch", attributes: .concurrent)
    private let repository = PodcastRepository.shared
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "FetchWorker")
    #endif
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Batch fetch episodes for multiple podcasts (≥ 1,000 episodes/sec goal)
    func batchFetchEpisodes(for podcasts: [Podcast]) async -> [UUID: [Episode]] {
        #if canImport(OSLog)
        logger.info("🚀 Starting batch fetch for \(podcasts.count) podcasts")
        #endif
        
        let startTime = Date()
        
        // Process podcasts in batches using Task.detached
        let batches = podcasts.chunked(into: Config.batchSize)
        var allResults: [UUID: [Episode]] = [:]
        
        for batch in batches {
            let batchResults = await withTaskGroup(of: [UUID: [Episode]].self) { group in
                for podcast in batch {
                    group.addTask(priority: .utility) {
                        await self.fetchEpisodesForPodcast(podcast)
                    }
                }
                
                var results: [UUID: [Episode]] = [:]
                for await batchResult in group {
                    results.merge(batchResult) { _, new in new }
                }
                return results
            }
            
            allResults.merge(batchResults) { _, new in new }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let totalEpisodes = allResults.values.reduce(0) { $0 + $1.count }
        let throughput = Double(totalEpisodes) / duration
        
        #if canImport(OSLog)
        logger.info("✅ Batch fetch completed: \(totalEpisodes) episodes in \(String(format: "%.2f", duration))s (throughput: \(String(format: "%.0f", throughput)) episodes/sec)")
        #endif
        
        return allResults
    }
    
    /// Fetch episodes for single podcast using Task.detached
    private func fetchEpisodesForPodcast(_ podcast: Podcast) async -> [UUID: [Episode]] {
        return await Task.detached(priority: .utility) {
            await self.performFetch(for: podcast)
        }.value
    }
    
    /// Core fetch implementation with concurrency control
    private func performFetch(for podcast: Podcast) async -> [UUID: [Episode]] {
        // Note: Concurrency is controlled by TaskGroup in batchFetchEpisodes
        
        #if canImport(OSLog)
        logger.debug("📡 Fetching episodes for podcast: \(podcast.title)")
        #endif
        
        do {
            // 1. URLSession.shared.data(for: request)
            let rssURL = podcast.feedURL
            
            let request = URLRequest(url: rssURL, timeoutInterval: 30.0)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                #if canImport(OSLog)
                logger.error("❌ HTTP error for \(podcast.title): \(response)")
                #endif
                return [:]
            }
            
            // 2. Decode JSON/RSS to [EpisodeDTO]
            let episodes = try await parseRSSFeed(data: data, podcastID: podcast.id)
            
            // 3. Compute diff vs. cache IDs & timestamps
            let currentEpisodes = await repository.getEpisodes(for: podcast.id)
            let changes = computeDiff(current: currentEpisodes, new: episodes, podcastID: podcast.id)
            
            // Apply changes with barrier write
            if !changes.isEmpty {
                await repository.applyChanges(changes)
            }
            
            return [podcast.id: episodes]
            
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Fetch failed for \(podcast.title): \(error.localizedDescription)")
            #endif
            return [:]
        }
    }
    
    /// Parse RSS feed data to episodes
    private func parseRSSFeed(data: Data, podcastID: UUID) async throws -> [Episode] {
        return try await Task.detached(priority: .utility) {
            // Use existing RSS parser from Utilities
            let parser = RSSParser(podcastID: podcastID)
            return try await parser.parseEpisodesAsync(from: data, podcastID: podcastID)
        }.value
    }
    
    /// Compute diff vs. cache IDs & timestamps
    private func computeDiff(current: [Episode], new: [Episode], podcastID: UUID) -> EpisodeChanges {
        let currentDict = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        
        let inserted = new.filter { currentDict[$0.id] == nil }
        let deleted = current.compactMap { episode in
            new.contains(where: { $0.id == episode.id }) ? nil : episode.id
        }
        let updated = new.filter { episode in
            if let currentEpisode = currentDict[episode.id] {
                return !episode.isEqual(to: currentEpisode)
            }
            return false
        }
        
        return EpisodeChanges(inserted: inserted, updated: updated, deleted: deleted)
    }
}

// MARK: - Array Extension for Chunking
// Note: chunked(into:) extension is defined in EpisodeUpdateService.swift

// MARK: - RSS Parser
// Note: Using existing RSSParser from Jimmy/Utilities/RSSParser.swift 