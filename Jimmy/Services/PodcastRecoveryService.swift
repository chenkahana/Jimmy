import Foundation
import OSLog

/// Service to recover missing podcasts from orphaned episodes
/// This handles cases where episodes exist but their parent podcasts are missing
class PodcastRecoveryService {
    static let shared = PodcastRecoveryService()
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "PodcastRecovery")
    #endif
    
    /// Flag to disable recovery service (used when clearing all data)
    private var isRecoveryDisabled: Bool {
        return UserDefaults.standard.bool(forKey: "disablePodcastRecovery")
    }
    
    private init() {}
    
    /// Disable the recovery service
    func disableRecovery() {
        UserDefaults.standard.set(true, forKey: "disablePodcastRecovery")
        #if canImport(OSLog)
        logger.info("🚫 Podcast recovery service disabled")
        #endif
    }
    
    /// Enable the recovery service
    func enableRecovery() {
        UserDefaults.standard.set(false, forKey: "disablePodcastRecovery")
        #if canImport(OSLog)
        logger.info("✅ Podcast recovery service enabled")
        #endif
    }
    
    /// Recover missing podcasts from orphaned episodes
    func recoverMissingPodcasts() async {
        // Check if recovery is disabled
        guard !isRecoveryDisabled else {
            #if canImport(OSLog)
            logger.info("🚫 Podcast recovery is disabled - skipping recovery")
            #endif
            return
        }
        
        #if canImport(OSLog)
        logger.info("🔧 Starting podcast recovery from orphaned episodes")
        #endif
        
        let libraryViewModel = await LibraryViewModel.shared
        let podcastService = PodcastService.shared
        
        // Get all episodes and existing podcasts
        let allEpisodes = await LibraryViewModel.shared.allEpisodes
        let existingPodcasts = await podcastService.loadPodcastsAsync()
        let existingPodcastIDs = Set(existingPodcasts.map(\.id))
        
        #if canImport(OSLog)
        logger.info("📊 Found \(allEpisodes.count) episodes and \(existingPodcasts.count) existing podcasts")
        #endif
        
        // Find unique podcast IDs from episodes that don't have corresponding podcasts
        let episodePodcastIDs = Set(allEpisodes.compactMap { $0.podcastID })
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
            let lastEpisodeDate = episodesForPodcast.compactMap { $0.publishedDate }.max()
            
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
        let titles = episodes.map { $0.title }
        
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
        // Try to extract author from episode descriptions or metadata
        for episode in episodes {
            // Look for common author patterns in episode descriptions
            if let description = episode.description {
                // Look for patterns like "by Author Name" or "with Author Name"
                let patterns = [
                    #"(?:by|with|hosted by)\s+([A-Za-z\s]+)"#,
                    #"Author:\s*([A-Za-z\s]+)"#,
                    #"Host:\s*([A-Za-z\s]+)"#
                ]
                
                for pattern in patterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                        let range = NSRange(description.startIndex..<description.endIndex, in: description)
                        if let match = regex.firstMatch(in: description, options: [], range: range) {
                            if let authorRange = Range(match.range(at: 1), in: description) {
                                let author = String(description[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !author.isEmpty && author.count > 2 {
                                    return author
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // If no author found in descriptions, try to extract from episode titles
        // Look for consistent patterns across episodes
        let titles = episodes.map { $0.title }
        
        // Look for patterns like "Show Name with Author Name - Episode Title"
        for title in titles {
            if let regex = try? NSRegularExpression(pattern: #"with\s+([A-Za-z\s]+)\s*[-–]"#, options: .caseInsensitive) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, options: [], range: range) {
                    if let authorRange = Range(match.range(at: 1), in: title) {
                        let author = String(title[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !author.isEmpty && author.count > 2 {
                            return author
                        }
                    }
                }
            }
        }
        
        return nil
    }
} 