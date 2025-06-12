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
                    .transition(.opacity.combined(with: .scale))
            } else {
                placeholder()
                    .transition(.opacity)
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .animation(.proMotionEaseInOut(duration: 0.2), value: image)
        .onChange(of: url) { _, newURL in
            // Only reset image if the new URL is different and not cached
            if let newURL = newURL, !imageCache.isImageCached(url: newURL) {
                image = nil
            }
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else { return }
        
        // Check if image is already cached to avoid showing loading state
        let isCached = imageCache.isImageCached(url: url)
        if isCached {
            // Image is cached, load it directly
            imageCache.loadImage(from: url) { [url] loadedImage in
                // Only update if the URL hasn't changed while loading
                if self.url == url {
                    self.image = loadedImage
                    self.isLoading = false
                }
            }
        } else {
            // Image not cached, show loading state
            isLoading = true
            
            imageCache.loadImage(from: url) { [url] loadedImage in
                // Only update if the URL hasn't changed while loading
                if self.url == url {
                    withAnimation(.proMotionEaseInOut(duration: 0.2)) {
                        self.image = loadedImage
                    }
                    self.isLoading = false
                }
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
                // Only reset to empty if the new URL is different and not cached
                if let newURL = newURL, !imageCache.isImageCached(url: newURL) {
                    phase = .empty
                }
                loadImage()
            }
    }
    
    private func loadImage() {
        guard let url = url else {
            phase = .empty
            return
        }
        
        // Check if image is already cached before showing loading state
        let isCached = imageCache.isImageCached(url: url)
        if isCached {
            // Image is cached, load it directly without showing empty state first
            imageCache.loadImage(from: url) { [url] loadedImage in
                // Only update if the URL hasn't changed while loading
                if self.url == url {
                    if let loadedImage = loadedImage {
                        self.phase = .success(Image(uiImage: loadedImage))
                    } else {
                        self.phase = .failure(ImageLoadError("Failed to load image"))
                    }
                }
            }
        } else {
            // Image not cached, show loading state first
            phase = .empty
            
            imageCache.loadImage(from: url) { [url] loadedImage in
                // Only update if the URL hasn't changed while loading
                if self.url == url {
                    withAnimation(.proMotionEaseInOut(duration: 0.2)) {
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
}

// MARK: - Podcast-specific Convenience Views

/// Specialized view for podcast artwork with standardized styling
struct PodcastArtworkView: View {
    let artworkURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    
    @State private var retryCount = 0
    @State private var hasFailedToLoad = false
    
    private let maxRetries = 2
    
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
        ZStack {
            Rectangle()
                .fill(Color(.systemBackground))
                .frame(width: size, height: size)
            
            CachedAsyncImage(url: artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: size / 4))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.clear,
                            Color.black.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
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
                    )
            case .empty:
                // Clean loading state
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isEditMode {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.4))
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Gallery View for Preloading

struct ImageGalleryView: View {
    let imageURLs: [URL]
    @State private var currentIndex: Int = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(imageURLs.indices, id: \.self) { index in
                CachedAsyncImagePhase(url: imageURLs[index]) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        VStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Failed to load image")
                        }
                    case .empty:
                        ProgressView()
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle())
        .onChange(of: currentIndex) { _, newIndex in
            preloadSurroundingImages(currentIndex: newIndex)
        }
        .onAppear {
            preloadAllImages()
        }
    }

    // Preload all images in the collection
    private func preloadAllImages() {
        let urls = Set(imageURLs)
        ImageCache.shared.preloadImages(urls: urls)
    }

    // Preload surrounding images for a smoother scrolling experience
    private func preloadSurroundingImages(currentIndex: Int) {
        let urls = imageURLs
        guard currentIndex < urls.count else { return }
        
        let preloadRange = 2 // Preload 2 images before and after the current one
        let startIndex = max(0, currentIndex - preloadRange)
        let endIndex = min(urls.count - 1, currentIndex + preloadRange)
        
        let urlsToPreload = Set(Array(urls[startIndex...endIndex]))
        ImageCache.shared.preloadImages(urls: urlsToPreload)
    }
}

// MARK: - Unified Empty State Component

/// Unified empty state view for consistent styling across Library, Queue, and Now Playing views
struct UnifiedEmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconSize: CGFloat
    let spacing: CGFloat
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        iconSize: CGFloat = 64,
        spacing: CGFloat = 20
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconSize = iconSize
        self.spacing = spacing
    }
    
    var body: some View {
        VStack(spacing: spacing) {
            Spacer()
            
            VStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .thin))
                    .foregroundStyle(Color(.systemGray3))
                
                // Text content
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Library Empty State") {
    UnifiedEmptyStateView(
        icon: "rectangle.grid.3x2",
        title: "No Podcasts Yet",
        subtitle: "Your subscribed podcasts will appear here. Go to Discover to find and subscribe to podcasts."
    )
}

#Preview("Queue Empty State") {
    UnifiedEmptyStateView(
        icon: "list.bullet",
        title: "Your queue is empty",
        subtitle: "Add episodes from your podcasts to build your listening queue"
    )
}

#Preview("Now Playing Empty State") {
    UnifiedEmptyStateView(
        icon: "music.note.house",
        title: "No Episode Playing",
        subtitle: "Choose an episode from your queue or library to start listening",
        iconSize: 72,
        spacing: 24
    )
} 