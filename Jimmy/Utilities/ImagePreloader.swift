import Foundation
import SwiftUI

/// A utility to proactively preload and cache image assets to ensure they are available instantly when the UI needs them.
/// This is critical for a smooth user experience, especially in scrollable lists.
struct ImagePreloader {
    
    /// Preloads artwork for an array of podcasts.
    /// It iterates through the podcasts and triggers a cache operation for each artwork URL.
    static func preloadPodcastArtwork(_ podcasts: [Podcast]) {
        let urls = podcasts.compactMap { $0.artworkURL }
        ImageCache.shared.preloadImages(urls: Set(urls))
    }
    
    /// Preloads artwork for an array of episodes.
    /// It uses the episode's artwork URL or falls back to the podcast's artwork if the episode-specific one is missing.
    static func preloadEpisodeArtwork(_ episodes: [Episode], fallbackPodcast: Podcast) {
        let urls = episodes.compactMap { $0.artworkURL ?? fallbackPodcast.artworkURL }
        ImageCache.shared.preloadImages(urls: Set(urls))
    }
} 