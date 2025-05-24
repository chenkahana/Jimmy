import SwiftUI
import UIKit

// Error type for image loading failures
struct ImageLoadError: Error {
    let message: String
    
    init(_ message: String = "Failed to load image") {
        self.message = message
    }
}

/// A SwiftUI view that loads and caches images efficiently
/// Replacement for AsyncImage with better caching capabilities
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading: Bool = false
    @ObservedObject private var imageCache = ImageCache.shared
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onChange(of: url) { _, newURL in
            // Reset state when URL changes
            image = nil
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else { return }
        
        isLoading = true
        
        imageCache.loadImage(from: url) { [url] loadedImage in
            // Only update if the URL hasn't changed while loading
            if self.url == url {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.image = loadedImage
                }
                self.isLoading = false
            }
        }
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    /// Simplified initializer with default placeholder
    init(url: URL?) {
        self.init(
            url: url,
            content: { image in image },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension CachedAsyncImage where Placeholder == Color {
    /// Initializer with custom content but default placeholder
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension CachedAsyncImage where Content == Image {
    /// Initializer with custom placeholder but default content
    init(
        url: URL?,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: url,
            content: { image in image },
            placeholder: placeholder
        )
    }
}

// MARK: - Phase-based Implementation (AsyncImage compatibility)

enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)
    
    var image: Image? {
        if case .success(let image) = self {
            return image
        }
        return nil
    }
}

struct CachedAsyncImagePhase<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content
    
    @State private var phase: AsyncImagePhase = .empty
    @ObservedObject private var imageCache = ImageCache.shared
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }
    
    var body: some View {
        content(phase)
            .onAppear {
                loadImage()
            }
            .onChange(of: url) { _, newURL in
                phase = .empty
                loadImage()
            }
    }
    
    private func loadImage() {
        guard let url = url else {
            phase = .empty
            return
        }
        
        phase = .empty
        
        imageCache.loadImage(from: url) { [url] loadedImage in
            // Only update if the URL hasn't changed while loading
            if self.url == url {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let loadedImage = loadedImage {
                        self.phase = .success(Image(uiImage: loadedImage))
                    } else {
                        self.phase = .failure(ImageLoadError("Failed to load image"))
                    }
                }
            }
        }
    }
}

// MARK: - Podcast-specific Convenience Views

/// Specialized view for podcast artwork with standardized styling
struct PodcastArtworkView: View {
    let artworkURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    
    init(
        artworkURL: URL?,
        size: CGFloat = 60,
        cornerRadius: CGFloat = 8
    ) {
        self.artworkURL = artworkURL
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        CachedAsyncImage(url: artworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.3),
                        Color.accentColor.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: size * 0.3))
                        .foregroundColor(.white)
                )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Grid view for podcast thumbnails with optimized loading
struct PodcastGridArtwork: View {
    let artworkURL: URL?
    let isEditMode: Bool
    
    var body: some View {
        CachedAsyncImagePhase(url: artworkURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure(_):
                // Clean fallback for failed loads
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.title2)
                    )
            case .empty:
                // Loading state
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isEditMode ? 0.9 : 1.0)
    }
}

// MARK: - Image Preloading Utilities

struct ImagePreloader {
    static func preloadPodcastArtwork(_ podcasts: [Podcast]) {
        let urls = podcasts.compactMap { $0.artworkURL }
        ImageCache.shared.preloadImages(urls: urls)
    }
    
    static func preloadEpisodeArtwork(_ episodes: [Episode], fallbackPodcast: Podcast? = nil) {
        var urls: [URL] = []
        
        for episode in episodes {
            if let artworkURL = episode.artworkURL {
                urls.append(artworkURL)
            } else if let podcastArtwork = fallbackPodcast?.artworkURL {
                urls.append(podcastArtwork)
            }
        }
        
        ImageCache.shared.preloadImages(urls: urls)
    }
} 