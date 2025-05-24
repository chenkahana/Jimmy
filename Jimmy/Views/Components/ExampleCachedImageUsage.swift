import SwiftUI

/// Example view demonstrating how to use the new caching system
/// This file shows the different ways to use CachedAsyncImage throughout the app
struct ExampleCachedImageUsage: View {
    let podcast: Podcast
    let episode: Episode
    
    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Basic Usage
            Text("Basic Cached Image")
                .font(.headline)
            
            CachedAsyncImage(url: podcast.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ProgressView()
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // MARK: - Using Specialized Podcast Artwork View
            Text("Specialized Podcast Artwork")
                .font(.headline)
            
            PodcastArtworkView(
                artworkURL: podcast.artworkURL,
                size: 120,
                cornerRadius: 16
            )
            
            // MARK: - Using Grid Artwork (for library views)
            Text("Grid Artwork")
                .font(.headline)
            
            PodcastGridArtwork(
                artworkURL: podcast.artworkURL,
                isEditMode: false
            )
            
            // MARK: - Phase-based Usage (AsyncImage compatibility)
            Text("Phase-based Usage")
                .font(.headline)
            
            CachedAsyncImagePhase(url: episode.artworkURL ?? podcast.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure(_):
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                        )
                case .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .overlay(
                            ProgressView()
                        )
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Cached Image Examples")
    }
}

// MARK: - Migration Guide Comments

/*
 MIGRATION GUIDE: Replace AsyncImage with CachedAsyncImage
 
 OLD CODE:
 AsyncImage(url: podcast.artworkURL) { image in
     image.resizable().aspectRatio(contentMode: .fill)
 } placeholder: {
     ProgressView()
 }
 
 NEW CODE:
 CachedAsyncImage(url: podcast.artworkURL) { image in
     image.resizable().aspectRatio(contentMode: .fill)
 } placeholder: {
     ProgressView()
 }
 
 OR use the specialized views:
 
 PodcastArtworkView(artworkURL: podcast.artworkURL, size: 60)
 
 OR for phase-based usage:
 
 CachedAsyncImagePhase(url: podcast.artworkURL) { phase in
     switch phase {
     case .success(let image): image.resizable()
     case .failure(_): Color.red
     case .empty: ProgressView()
     }
 }
 
 BENEFITS:
 - Images are cached in memory and disk
 - No re-downloading when navigating between views
 - Automatic cleanup of expired cache entries
 - Better performance and reduced network usage
 - Prevents duplicate downloads for the same URL
 */ 