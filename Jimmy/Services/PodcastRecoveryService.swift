import Foundation
import OSLog

/// Service to recover missing podcasts from orphaned episodes
/// This handles cases where episodes exist but their parent podcasts are missing
class PodcastRecoveryService {
    static let shared = PodcastRecoveryService()
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "PodcastRecovery")
    #endif
    
    private init() {}
    
    /// Recover missing podcasts from orphaned episodes
    func recoverMissingPodcasts() async {
        #if canImport(OSLog)
        logger.info("🔧 Starting podcast recovery from orphaned episodes")
        #endif
        
        let episodeController = await UnifiedEpisodeController.shared
        let podcastService = PodcastService.shared
        
        // Get all episodes and existing podcasts
        let allEpisodes = await episodeController.getAllEpisodes()
        let existingPodcasts = await podcastService.loadPodcastsAsync()
        let existingPodcastIDs = Set(existingPodcasts.map(\.id))
        
        #if canImport(OSLog)
        logger.info("📊 Found \(allEpisodes.count) episodes and \(existingPodcasts.count) existing podcasts")
        #endif
        
        // Find unique podcast IDs from episodes that don't have corresponding podcasts
        let episodePodcastIDs = Set(allEpisodes.compactMap(\.podcastID))
        let orphanedPodcastIDs = episodePodcastIDs.subtracting(existingPodcastIDs)
        
        #if canImport(OSLog)
        logger.info("🔍 Found \(orphanedPodcastIDs.count) orphaned podcast IDs")
        #endif
        
        guard !orphanedPodcastIDs.isEmpty else {
            #if canImport(OSLog)
            logger.info("✅ No orphaned podcasts found - recovery not needed")
            #endif
            return
        }
        
        // Create placeholder podcasts for orphaned episodes
        var recoveredPodcasts = existingPodcasts
        
        for podcastID in orphanedPodcastIDs {
            let episodesForPodcast = allEpisodes.filter { $0.podcastID == podcastID }
            
            guard !episodesForPodcast.isEmpty else { continue }
            
            // Use the first episode to extract podcast information
            let firstEpisode = episodesForPodcast.first!
            
            // Try to extract podcast title from episode metadata or use a default
            let podcastTitle = extractPodcastTitle(from: episodesForPodcast) ?? "Recovered Podcast"
            let podcastAuthor = extractPodcastAuthor(from: episodesForPodcast) ?? "Unknown Author"
            let lastEpisodeDate = episodesForPodcast.compactMap(\.publishedDate).max()
            
            // Create a placeholder podcast
            let recoveredPodcast = Podcast(
                id: podcastID,
                title: podcastTitle,
                author: podcastAuthor,
                description: "Recovered podcast with \(episodesForPodcast.count) episodes",
                feedURL: URL(string: "https://recovered.podcast/\(podcastID.uuidString)")!,
                artworkURL: firstEpisode.artworkURL,
                lastEpisodeDate: lastEpisodeDate
            )
            
            recoveredPodcasts.append(recoveredPodcast)
            
            #if canImport(OSLog)
            logger.info("🔧 Recovered podcast: \(podcastTitle) with \(episodesForPodcast.count) episodes")
            #endif
        }
        
        // Save the recovered podcasts
        podcastService.savePodcasts(recoveredPodcasts)
        
        #if canImport(OSLog)
        logger.info("✅ Recovery complete: \(orphanedPodcastIDs.count) podcasts recovered")
        #endif
    }
    
    /// Extract podcast title from episodes (try to find common patterns)
    private func extractPodcastTitle(from episodes: [Episode]) -> String? {
        // Look for common prefixes in episode titles
        let titles = episodes.map(\.title)
        
        // Try to find the longest common prefix
        guard let firstTitle = titles.first else { return nil }
        
        var commonPrefix = firstTitle
        for title in titles.dropFirst() {
            commonPrefix = String(commonPrefix.commonPrefix(with: title))
        }
        
        // Clean up the prefix (remove trailing separators, numbers, etc.)
        let cleanedPrefix = commonPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-|#0123456789"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanedPrefix.isEmpty ? nil : cleanedPrefix
    }
    
    /// Extract podcast author from episodes
    private func extractPodcastAuthor(from episodes: [Episode]) -> String? {
        // For now, return nil - we don't have author info in episodes
        // This could be enhanced to parse from episode descriptions or other metadata
        return nil
    }
} 