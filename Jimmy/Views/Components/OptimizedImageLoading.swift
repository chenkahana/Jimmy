import SwiftUI
import UIKit

// MARK: - Optimized Image Loading System

/// High-performance image loading with progressive enhancement and smart caching
struct OptimizedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadingProgress: Double = 0.0
    @ObservedObject private var imageCache = BulletproofImageCache.shared
    
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
        ZStack {
            if let image = image {
                content(Image(uiImage: image))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                placeholder()
                    .overlay(
                        // Progressive loading indicator
                        Group {
                            if isLoading && loadingProgress > 0 {
                                ProgressView(value: loadingProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .scaleEffect(0.8)
                                    .opacity(0.7)
                            }
                        }
                    )
            }
        }
        .task(id: url) {
            await loadImageOptimized()
        }
        .animation(.easeInOut(duration: 0.25), value: image != nil)
    }
    
    private func loadImageOptimized() async {
        guard let url = url else {
            image = nil
            return
        }
        
        // Check if already cached for instant display
        if imageCache.isImageCached(url: url) {
            let cachedImage = await imageCache.loadImage(from: url)
            await MainActor.run {
                self.image = cachedImage
            }
            return
        }
        
        // Show loading state for non-cached images
        await MainActor.run {
            isLoading = true
            loadingProgress = 0.1
        }
        
        // Simulate progressive loading for better UX
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            Task { @MainActor in
                if loadingProgress < 0.8 {
                    loadingProgress += 0.1
                } else {
                    timer.invalidate()
                }
            }
        }
        
        // Load image
        let loadedImage = await imageCache.loadImage(from: url)
        
        await MainActor.run {
            progressTimer.invalidate()
            self.image = loadedImage
            self.isLoading = false
            self.loadingProgress = 1.0
        }
    }
}

// MARK: - Convenience Initializers

extension OptimizedAsyncImage where Content == Image, Placeholder == OptimizedImagePlaceholder {
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { OptimizedImagePlaceholder() }
        )
    }
}

extension OptimizedAsyncImage where Placeholder == OptimizedImagePlaceholder {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            content: content,
            placeholder: { OptimizedImagePlaceholder() }
        )
    }
}

// MARK: - Optimized Placeholder Component

struct OptimizedImagePlaceholder: View {
    @State private var isShimmering = false
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(.systemGray6),
                        Color(.systemGray5),
                        Color(.systemGray6)
                    ],
                    startPoint: isShimmering ? .leading : .trailing,
                    endPoint: isShimmering ? .trailing : .leading
                )
            )
            .overlay(
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .opacity(0.6)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isShimmering = true
                }
            }
    }
}

// MARK: - Smart Image Preloader

/// Intelligent image preloader that prioritizes visible content
class SmartImagePreloader: ObservableObject {
    static let shared = SmartImagePreloader()
    
    private let imageCache = BulletproofImageCache.shared
    private var preloadQueue: Set<URL> = []
    private let preloadLimit = 20 // Maximum images to preload at once
    
    private init() {}
    
    /// Preload images with priority system
    func preloadImages(urls: [URL], priority: PreloadPriority = .normal) {
        let urlsToPreload = Array(urls.prefix(preloadLimit))
        
        Task.detached(priority: priority.taskPriority) { [weak self] in
            await self?.performPreload(urls: urlsToPreload)
        }
    }
    
    /// Preload images for visible content area
    func preloadVisibleContent(urls: [URL]) {
        preloadImages(urls: urls, priority: .high)
    }
    
    /// Preload images for upcoming content
    func preloadUpcomingContent(urls: [URL]) {
        preloadImages(urls: urls, priority: .low)
    }
    
    private func performPreload(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                // Skip if already cached or in queue
                guard !imageCache.isImageCached(url: url),
                      !preloadQueue.contains(url) else { continue }
                
                preloadQueue.insert(url)
                
                group.addTask { [weak self] in
                    _ = await self?.imageCache.loadImage(from: url)
                    let _ = await MainActor.run {
                        self?.preloadQueue.remove(url)
                    }
                }
            }
        }
    }
}

enum PreloadPriority {
    case low
    case normal
    case high
    
    var taskPriority: TaskPriority {
        switch self {
        case .low: return .background
        case .normal: return .utility
        case .high: return .userInitiated
        }
    }
}

// MARK: - Optimized Podcast Artwork Component

/// Specialized podcast artwork view with smart loading and caching
struct OptimizedPodcastArtwork: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    
    @State private var hasAppeared = false
    
    init(url: URL?, size: CGFloat = 60, cornerRadius: CGFloat = 8) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        OptimizedAsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } placeholder: {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray6))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size / 3))
                        .foregroundColor(.secondary)
                )
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                // Preload surrounding images when this one appears
                preloadSurroundingImages()
            }
        }
    }
    
    private func preloadSurroundingImages() {
        // This would be implemented based on the context where the artwork is used
        // For now, it's a placeholder for future smart preloading logic
    }
}

// MARK: - Image Loading Performance Monitor

class ImageLoadingPerformanceMonitor: ObservableObject {
    static let shared = ImageLoadingPerformanceMonitor()
    
    @Published var averageLoadTime: TimeInterval = 0
    @Published var cacheHitRate: Double = 0
    @Published var totalImagesLoaded: Int = 0
    
    private var loadTimes: [TimeInterval] = []
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    
    private init() {}
    
    func recordImageLoad(duration: TimeInterval, fromCache: Bool) {
        DispatchQueue.main.async {
            self.loadTimes.append(duration)
            self.totalImagesLoaded += 1
            
            if fromCache {
                self.cacheHits += 1
            } else {
                self.cacheMisses += 1
            }
            
            // Keep only recent measurements
            if self.loadTimes.count > 100 {
                self.loadTimes.removeFirst()
            }
            
            self.updateMetrics()
        }
    }
    
    private func updateMetrics() {
        averageLoadTime = loadTimes.isEmpty ? 0 : loadTimes.reduce(0, +) / Double(loadTimes.count)
        
        let totalRequests = cacheHits + cacheMisses
        cacheHitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0
    }
    
    func getPerformanceReport() -> String {
        """
        📊 Image Loading Performance
        Average Load Time: \(String(format: "%.2f", averageLoadTime * 1000))ms
        Cache Hit Rate: \(String(format: "%.1f", cacheHitRate * 100))%
        Total Images Loaded: \(totalImagesLoaded)
        """
    }
}

// MARK: - View Modifiers for Image Optimization

struct ImageOptimizationModifier: ViewModifier {
    let preloadUrls: [URL]
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                SmartImagePreloader.shared.preloadVisibleContent(urls: preloadUrls)
            }
    }
}

extension View {
    /// Preload images when view appears
    func preloadImages(_ urls: [URL]) -> some View {
        modifier(ImageOptimizationModifier(preloadUrls: urls))
    }
}