import Foundation
import CryptoKit
import CommonCrypto

/// Centralized utility for generating deterministic UUIDs for episodes
/// This ensures consistent episode IDs across the entire app
public struct DeterministicUUIDGenerator {
    
    /// Generate a deterministic UUID for an episode based on feed URL and episode identifiers
    /// This is the primary method that should be used throughout the app
    /// 
    /// - Parameters:
    ///   - feedURL: The podcast's RSS feed URL
    ///   - audioURL: The episode's audio URL (primary identifier)
    ///   - title: The episode title (fallback identifier)
    ///   - publishedDate: The episode's published date (additional identifier)
    /// - Returns: A deterministic UUID that will always be the same for the same episode
    public static func generateEpisodeID(
        feedURL: URL,
        audioURL: URL?,
        title: String,
        publishedDate: Date?
    ) -> UUID {
        // Primary strategy: Use audio URL if available (most reliable)
        if let audioURL = audioURL {
            return generateDeterministicUUID(from: audioURL.absoluteString)
        }
        
        // Fallback strategy: Combine feed URL + title + date for uniqueness
        let dateString = publishedDate?.timeIntervalSince1970.description ?? "unknown"
        let combinedString = "\(feedURL.absoluteString)|\(title)|\(dateString)"
        return generateDeterministicUUID(from: combinedString)
    }
    
    /// Generate a deterministic UUID for an episode based on audio URL only
    /// This is used when we have a reliable audio URL
    /// 
    /// - Parameter audioURL: The episode's audio URL
    /// - Returns: A deterministic UUID based on the audio URL
    public static func generateEpisodeID(from audioURL: URL) -> UUID {
        return generateDeterministicUUID(from: audioURL.absoluteString)
    }
    
    /// Generate a deterministic UUID for an episode based on feed URL and episode data
    /// This is used when audio URL is not available
    /// 
    /// - Parameters:
    ///   - feedURL: The podcast's RSS feed URL
    ///   - episodeData: Combined episode data (title, description, etc.)
    /// - Returns: A deterministic UUID based on the combined data
    public static func generateEpisodeID(feedURL: URL, episodeData: String) -> UUID {
        let combinedString = "\(feedURL.absoluteString)|\(episodeData)"
        return generateDeterministicUUID(from: combinedString)
    }
    
    /// Generate a deterministic UUID for a podcast based on its feed URL
    /// 
    /// - Parameter feedURL: The podcast's RSS feed URL
    /// - Returns: A deterministic UUID for the podcast
    public static func generatePodcastID(from feedURL: URL) -> UUID {
        return generateDeterministicUUID(from: feedURL.absoluteString)
    }
    
    // MARK: - Private Implementation
    
    /// Core deterministic UUID generation using SHA-256
    /// This method ensures the same input always produces the same UUID
    private static func generateDeterministicUUID(from string: String) -> UUID {
        // Use SHA-256 hash of the string to create a deterministic UUID
        let data = string.data(using: .utf8) ?? Data()
        
        // Use CryptoKit for iOS 13+ or CommonCrypto for older versions
        if #available(iOS 13.0, *) {
            let hash = SHA256.hash(data: data)
            let hashData = Data(hash)
            return createUUIDFromHash(hashData)
        } else {
            // Fallback to CommonCrypto
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes { bytes in
                _ = CC_SHA256(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), &hash)
            }
            let hashData = Data(hash)
            return createUUIDFromHash(hashData)
        }
    }
    
    /// Create a UUID from the first 16 bytes of a hash
    private static func createUUIDFromHash(_ hashData: Data) -> UUID {
        // Take first 16 bytes of hash to create UUID
        let uuidBytes = Array(hashData.prefix(16))
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}

// MARK: - Migration Helpers

extension DeterministicUUIDGenerator {
    
    /// Generate a deterministic UUID for an existing episode during migration
    /// This method handles episodes that may not have all the required data
    /// 
    /// - Parameters:
    ///   - episode: The existing episode
    ///   - feedURL: The podcast's feed URL
    /// - Returns: A deterministic UUID for the episode
    public static func generateMigrationID(for episode: Episode, feedURL: URL) -> UUID {
        // Try to use audio URL first (most reliable)
        if let audioURL = episode.audioURL {
            return generateEpisodeID(from: audioURL)
        }
        
        // Fallback to combined data approach
        let episodeData = "\(episode.title)|\(episode.publishedDate?.timeIntervalSince1970.description ?? "unknown")"
        return generateEpisodeID(feedURL: feedURL, episodeData: episodeData)
    }
    
    /// Check if an episode ID is deterministic (not a random UUID)
    /// This is used during migration to identify episodes that need ID updates
    /// 
    /// - Parameters:
    ///   - episode: The episode to check
    ///   - feedURL: The podcast's feed URL
    /// - Returns: True if the episode ID is already deterministic
    public static func isEpisodeIDDeterministic(episode: Episode, feedURL: URL) -> Bool {
        let expectedID = generateMigrationID(for: episode, feedURL: feedURL)
        return episode.id == expectedID
    }
} 