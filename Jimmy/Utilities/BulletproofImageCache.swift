import os
import Foundation
import SwiftUI
import UIKit

/// Bulletproof image caching system that combines the reliability of AsyncImage 
/// with advanced caching, retry logic, and fallback mechanisms
/// Based on the original working AsyncImage pattern but made bulletproof
final class BulletproofImageCache: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "BulletproofImageCache")
    static let shared = BulletproofImageCache()
    
    // MARK: - Configuration
    
    private struct Config {
        static let memoryCapacity = 50 * 1024 * 1024  // 50MB memory cache
        static let diskCapacity = 200 * 1024 * 1024   // 200MB disk cache
        static let maxRetries = 3
        static let baseRetryDelay: TimeInterval = 1.0
        static let requestTimeout: TimeInterval = 30.0
        static let maxConcurrentDownloads = 5
    }
    
    // MARK: - Storage
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache: URLCache
    private let downloadQueue = DispatchQueue(label: "bulletproof-image-downloads", qos: .userInitiated, attributes: .concurrent)
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    // Track ongoing downloads to prevent duplicates
    private var activeDownloads: [URL: Task<UIImage?, Never>] = [:]
    private let activeDownloadsLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Setup memory cache
        memoryCache.totalCostLimit = Config.memoryCapacity
        memoryCache.countLimit = 200 // Reasonable number of images
        
        // Setup disk cache using URLCache (proven reliable)
        diskCache = URLCache(
            memoryCapacity: 0, // We handle memory caching separately
            diskCapacity: Config.diskCapacity,
            diskPath: "BulletproofImageCache"
        )
        
        // Create cache directory
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheDir.appendingPathComponent("BulletproofImages")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Handle memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
            Self.logger.info("BulletproofImageCache: Cleared memory cache due to memory warning")
        }
    }
    
    // MARK: - Public API
    
    /// Load image with bulletproof caching and retry logic
    func loadImage(from url: URL) async -> UIImage? {
        // 1. Check memory cache first (fastest)
        let cacheKey = cacheKeyForURL(url)
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        // 2. Check if download is already in progress
        activeDownloadsLock.lock()
        if let existingTask = activeDownloads[url] {
            activeDownloadsLock.unlock()
            return await existingTask.value
        }
        
        // 3. Start new download task
        let downloadTask = Task<UIImage?, Never> {
            await self.downloadImageWithRetries(from: url)
        }
        activeDownloads[url] = downloadTask
        activeDownloadsLock.unlock()
        
        // 4. Wait for download and cleanup
        let result = await downloadTask.value
        
        activeDownloadsLock.lock()
        activeDownloads.removeValue(forKey: url)
        activeDownloadsLock.unlock()
        
        return result
    }
    
    /// Load image with completion handler (for SwiftUI compatibility)
    func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        Task {
            let image = await loadImage(from: url)
            await MainActor.run {
                completion(image)
            }
        }
    }
    
    /// Check if image is cached (memory or disk)
    func isImageCached(url: URL) -> Bool {
        let cacheKey = cacheKeyForURL(url)
        
        // Check memory cache
        if memoryCache.object(forKey: cacheKey) != nil {
            return true
        }
        
        // Check disk cache
        let request = URLRequest(url: url)
        return diskCache.cachedResponse(for: request) != nil
    }
    
    /// Clear all caches (memory and disk)
    func clearAllCaches() {
        memoryCache.removeAllObjects()
        diskCache.removeAllCachedResponses()
        Self.logger.info("BulletproofImageCache: Cleared all caches")
    }

    /// Preload images in background
    func preloadImages(urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        
        Task.detached(priority: .background) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    // Only preload if not already cached
                    if !self.isImageCached(url: url) {
                        group.addTask {
                            _ = await self.loadImage(from: url)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func downloadImageWithRetries(from url: URL) async -> UIImage? {
        var lastError: Error?
        
        for attempt in 0..<Config.maxRetries {
            do {
                // Use the bulletproof approach: Multiple fallback strategies
                let image = try await downloadImageWithFallbacks(from: url)
                
                // Cache successful download
                if let image = image {
                    cacheImage(image, for: url)
                    return image
                }
            } catch {
                lastError = error
                
                // If not the last attempt, wait with exponential backoff
                if attempt < Config.maxRetries - 1 {
                    let delay = Config.baseRetryDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        let errDesc = lastError?.localizedDescription ?? "unknown error"
        Self.logger.error("BulletproofImageCache: Failed to load \(url.absoluteString) after \(Config.maxRetries) attempts - \(errDesc)")
        return nil
    }
    
    private func downloadImageWithFallbacks(from url: URL) async throws -> UIImage? {
        // Strategy 1: Use URLSession.shared (the original working approach)
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Validate response
            if let httpResponse = response as? HTTPURLResponse {
                guard 200...299 ~= httpResponse.statusCode else {
                    throw URLError(.badServerResponse)
                }
            }
            
            // Create image
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            
            // Cache response in URLCache for future use
            let request = URLRequest(url: url)
            let cachedResponse = CachedURLResponse(response: response, data: data)
            diskCache.storeCachedResponse(cachedResponse, for: request)
            
            return image
            
        } catch {
            Self.logger.warning("BulletproofImageCache: URLSession.shared failed for \(url.absoluteString), trying custom session")
            
            // Strategy 2: Use custom session with conservative settings
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Config.requestTimeout
            config.timeoutIntervalForResource = Config.requestTimeout * 2
            config.httpMaximumConnectionsPerHost = 2
            config.waitsForConnectivity = false
            
            // Force HTTP/1.1 for problematic URLs (like imgix in simulator)
            if url.absoluteString.contains("imgix") {
                config.httpAdditionalHeaders = [
                    "Connection": "close",
                    "HTTP-Version": "1.1"
                ]
            }
            
            let customSession = URLSession(configuration: config)
            
            let (data, response) = try await customSession.data(from: url)
            
            // Validate response
            if let httpResponse = response as? HTTPURLResponse {
                guard 200...299 ~= httpResponse.statusCode else {
                    throw URLError(.badServerResponse)
                }
            }
            
            // Create image
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            
            return image
        }
    }
    
    private func cacheImage(_ image: UIImage, for url: URL) {
        let cacheKey = cacheKeyForURL(url)
        
        // Cache in memory
        memoryCache.setObject(image, forKey: cacheKey)
        
        Self.logger.debug("BulletproofImageCache: Cached image for \(url.absoluteString)")
    }
    
    private func cacheKeyForURL(_ url: URL) -> NSString {
        return url.absoluteString as NSString
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - SwiftUI Integration

/// Bulletproof replacement for AsyncImage that combines reliability with advanced caching
/// Uses the original AsyncImage pattern but with bulletproof networking underneath
struct BulletproofAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = false
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
        Group {
            if let image = image {
                content(Image(uiImage: image))
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            await loadImage()
        }
        .animation(.easeInOut(duration: 0.2), value: image != nil)
    }
    
    private func loadImage() async {
        guard let url = url else {
            image = nil
            return
        }
        
        isLoading = true
        let loadedImage = await imageCache.loadImage(from: url)
        
        await MainActor.run {
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

// MARK: - Convenience Extensions

extension BulletproofAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension BulletproofAsyncImage where Placeholder == Color {
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.init(
            url: url,
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

// MARK: - Phase-Based API Support

/// Use SwiftUI's built-in AsyncImagePhase instead of redefining it
/// This prevents naming conflicts and type ambiguity issues

/// Phase-based BulletproofAsyncImage that matches AsyncImage's phase API exactly
struct BulletproofAsyncImagePhase<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasError = false
    @ObservedObject private var imageCache = BulletproofImageCache.shared
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(.success(Image(uiImage: image)))
            } else if hasError {
                content(.failure(URLError(.networkConnectionLost)))
            } else {
                content(.empty)
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else { 
            image = nil
            return 
        }
        
        isLoading = true
        hasError = false
        
        imageCache.loadImage(from: url) { loadedImage in
            DispatchQueue.main.async {
                self.image = loadedImage
                self.isLoading = false
                self.hasError = loadedImage == nil
            }
        }
    }
}
