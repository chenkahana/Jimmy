import Foundation
import CryptoKit

/// Deterministic UUID generation for podcasts and episodes.
///
/// This is an exact port of `Jimmy/Utilities/DeterministicUUIDGenerator.swift`: same
/// inputs hashed in the same order, same SHA-256-prefix-to-UUID construction. Episode
/// and podcast IDs produced here MUST be byte-identical to the ones the app already has
/// in its database, or existing libraries will stop matching their episodes. Do not
/// change the hashing strategy without re-verifying against the original generator.
nonisolated public enum FeedIDs: Sendable {
    /// Generate a deterministic UUID for an episode based on feed URL and episode identifiers.
    ///
    /// - Parameters:
    ///   - feedURL: The podcast's RSS feed URL.
    ///   - audioURL: The episode's audio URL (primary identifier).
    ///   - title: The episode title (fallback identifier).
    ///   - publishedDate: The episode's published date (additional identifier).
    public static func generateEpisodeID(
        feedURL: URL,
        audioURL: URL?,
        title: String,
        publishedDate: Date?
    ) -> UUID {
        // Primary strategy: use the audio URL if available (most reliable).
        if let audioURL {
            return generateDeterministicUUID(from: audioURL.absoluteString)
        }

        // Fallback strategy: combine feed URL + title + date for uniqueness.
        let dateString = publishedDate?.timeIntervalSince1970.description ?? "unknown"
        let combinedString = "\(feedURL.absoluteString)|\(title)|\(dateString)"
        return generateDeterministicUUID(from: combinedString)
    }

    /// Generate a deterministic UUID for a podcast based on its feed URL.
    public static func generatePodcastID(from feedURL: URL) -> UUID {
        generateDeterministicUUID(from: feedURL.absoluteString)
    }

    // MARK: - Private Implementation

    /// Core deterministic UUID generation using SHA-256. Same input always produces the same UUID.
    private static func generateDeterministicUUID(from string: String) -> UUID {
        let data = string.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        let hashData = Data(hash)
        return createUUIDFromHash(hashData)
    }

    /// Create a UUID from the first 16 bytes of a hash.
    private static func createUUIDFromHash(_ hashData: Data) -> UUID {
        let uuidBytes = Array(hashData.prefix(16))
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}
