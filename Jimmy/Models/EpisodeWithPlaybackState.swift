import Foundation

/// A wrapper that combines an Episode with its PlaybackState.
/// This is used to pass around the UI layer to avoid managing two separate objects.
struct EpisodeWithPlaybackState: Identifiable, Codable, Equatable {
    var id = UUID()
    var episode: Episode
    var playbackState: PlaybackState

    static func == (lhs: EpisodeWithPlaybackState, rhs: EpisodeWithPlaybackState) -> Bool {
        lhs.episode.id == rhs.episode.id && lhs.playbackState == rhs.playbackState
    }
}

/// Episode status enumeration for the unified Episode Card (renamed to avoid conflicts)
enum EpisodeCardStatus: Int, Codable, CaseIterable {
    case none = 0
    case played = 1
    case queued = 2
    case playing = 3
}

/// Data contract for the unified Episode Card component
struct EpisodeWithStatus: Equatable, Identifiable {
    let id: UUID          // Episode ID
    let title: String
    let podcastTitle: String
    let duration: TimeInterval
    let playProgress: Double // 0…1.0
    let status: EpisodeCardStatus
    let artworkURL: URL?
    let podcastArtworkURL: URL?
    let description: String?
    let publishedDate: Date?
    
    /// Create EpisodeWithStatus from Episode and additional data
    init(
        episode: Episode,
        podcastTitle: String,
        playProgress: Double = 0.0,
        status: EpisodeCardStatus = .none,
        podcastArtworkURL: URL? = nil
    ) {
        self.id = episode.id
        self.title = episode.title
        self.podcastTitle = podcastTitle
        self.duration = episode.duration ?? 0
        self.playProgress = playProgress
        self.status = status
        self.artworkURL = episode.artworkURL
        self.podcastArtworkURL = podcastArtworkURL
        self.description = episode.description
        self.publishedDate = episode.publishedDate
    }
    
    /// Derive status from episode data and external state
    static func deriveStatus(
        episode: Episode,
        playProgress: Double,
        isQueued: Bool,
        isCurrentlyPlaying: Bool
    ) -> EpisodeCardStatus {
        // Priority: playing > queued > played > none
        if isCurrentlyPlaying {
            return .playing
        } else if isQueued {
            return .queued
        } else if playProgress >= 0.95 || episode.status.contains(.played) {
            // CRITICAL FIX: Check both progress AND episode status for played state
            return .played
        } else {
            return .none
        }
    }
    
    /// Convert EpisodeWithStatus back to Episode for operations that require full Episode object
    func toEpisode() -> Episode {
        // Convert EpisodeCardStatus back to EpisodeStatus
        var episodeStatus: EpisodeStatus = []
        switch status {
        case .played:
            episodeStatus.insert(.played)
        case .queued:
            episodeStatus.insert(.queued)
        case .playing:
            episodeStatus.insert(.playing)
        case .none:
            break // Leave empty
        }
        
        return Episode(
            id: id,
            title: title,
            publishedDate: publishedDate,
            duration: duration,
            artworkURL: artworkURL,
            description: description,
            played: status == .played,
            playbackPosition: duration * playProgress,
            status: episodeStatus
        )
    }
} 