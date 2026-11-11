import Foundation
import os
import SwiftUI
import UIKit
import CryptoKit
import Combine

/// A comprehensive image caching solution for podcast artwork
/// Handles both memory and disk caching with proper cache expiration
/// CRITICAL MEMORY FIX: Reduced memory limits to prevent excessive usage
public class ImageCache: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ImageCache")
    public static let shared = ImageCache()
    
    // MARK: - Cache Configuration (REDUCED FOR MEMORY OPTIMIZATION)
    
    struct CacheConfig {
        // CRITICAL FIX: Reduced memory capacity from 50MB to 20MB
        static let memoryCapacity = 20 * 1024 * 1024 // 20MB memory cache (was 50MB)
        static let diskCapacity = 100 * 1024 * 1024 // 100MB disk cache (reduced from 200MB)
        static let maxConcurrentDownloads = 3 // Reduced from 5 to prevent memory spikes
        static let downloadTimeout: TimeInterval = 15.0
        static let cacheExpiration: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        static let memoryWarningCleanupRatio: Double = 0.7 // Remove 70% on memory warning (increased from 50%)
        static let maxMemoryImages = 50 // Reduced from 100 to prevent memory bloat
    }
    
    // MARK: - Cache Storage
    
    private let memoryCache = NSCache<NSString, CachedImage>()
    private let diskCacheQueue = DispatchQueue(label: "image-cache-disk", qos: .utility)
    private let downloadQueue = DispatchQueue(label: "image-cache-download", qos: .userInitiated, attributes: .concurrent)
    private let operationQueue: OperationQueue
    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    // Notification token for memory warning observer
    private var memoryWarningObserver: NSObjectProtocol?
    
    // Track ongoing downloads using actor for thread safety
    private let downloadRegistry = DownloadRegistry()
    
    // Track memory cache keys for cleanup
    private var memoryCacheKeys: Set<String> = []
    private let memoryCacheKeysLock = NSLock()
    
    // MARK: - Cache Entry Models
    
    private class CachedImage {
        let image: UIImage
        let date: Date
        let url: URL
        
        init(image: UIImage, url: URL) {
            self.image = image
            self.date = Date()
            self.url = url
        }
        
        var isExpired: Bool {
            Date().timeIntervalSince(date) > CacheConfig.cacheExpiration
        }
    }
    
    private struct DiskCacheMetadata: Codable {
        let url: String
        let timestamp: TimeInterval
        let filename: String
        
        var isExpired: Bool {
            Date().timeIntervalSince1970 - timestamp > CacheConfig.cacheExpiration
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Setup operation queue for downloads (reduced concurrency)
        operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = CacheConfig.maxConcurrentDownloads
        operationQueue.qualityOfService = .userInitiated
        
        // Setup memory cache with reduced limits
        memoryCache.countLimit = CacheConfig.maxMemoryImages
        memoryCache.totalCostLimit = CacheConfig.memoryCapacity
        
        // Create a custom cache directory for images
        if let appCacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDirectory = appCacheDirectory.appendingPathComponent("ImageCache")
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        } else {
            // Fallback, though this should rarely happen
            cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ImageCache")
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        setupMemoryWarningObserver()
        
        // Clean expired entries on startup (in background)
        Task.detached(priority: .background) { [weak self] in
            self?.cleanupExpiredEntries()
        }
    }
    
    // MARK: - Public Interface
    
    /// Load image with caching
    /// Returns cached image immediately if available, otherwise downloads and caches
    public func loadImage(from url: URL) async -> UIImage? {
        // Validate URL first
        guard isValidImageURL(url) else {
            return nil
        }

        let cacheKey = generateCacheKey(for: url)
        let key = cacheKey as NSString

        // 1. Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key) {
            return cachedImage.image
        }

        // 2. Check disk cache
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey + ".jpg")
        if let image = UIImage(contentsOfFile: fileURL.path) {
            let cachedImage = CachedImage(image: image, url: url)
            self.memoryCache.setObject(cachedImage, forKey: key)

            // Track memory cache key
            memoryCacheKeysLock.lock()
            memoryCacheKeys.insert(cacheKey)
            memoryCacheKeysLock.unlock()

            return image
        }

        // 3. Check if download is already in progress
        if let existingOperation = await downloadRegistry.operation(for: url) {
            return await withCheckedContinuation { continuation in
                existingOperation.addCompletion { image in
                    continuation.resume(returning: image)
                }
            }
        }

        // 4. Start new download
        let downloadOperation = DownloadOperation(url: url)
        await downloadRegistry.set(downloadOperation, for: url)

        return await withCheckedContinuation { continuation in
            downloadOperation.addCompletion { image in
                continuation.resume(returning: image)
            }

            downloadOperation.completionBlock = { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.downloadRegistry.remove(url: url)
                    if let image = downloadOperation.downloadedImage {
                        self.cache(image: image, forKey: key, fileURL: fileURL, originalURL: url)
                    }
                }
            }

            self.operationQueue.addOperation(downloadOperation)
        }
    }

    /// Load image with caching using completion handler for legacy callers
    public func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        Task {
            let image = await loadImage(from: url)
            await MainActor.run {
                completion(image)
            }
        }
    }
    
    /// Preload images for URLs (useful for prefetching)
    public func preloadImages(urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        
        let validUrls = urls.filter { isValidImageURL($0) }
        guard !validUrls.isEmpty else { return }
        
        DispatchQueue.global(qos: .utility).async {
            let group = DispatchGroup()
            
            for url in validUrls {
                // Don't re-download if it's already in the cache
                guard !self.isImageCached(url: url) else { continue }
                
                group.enter()
                self.loadImage(from: url) { _ in
                    group.leave()
                }
            }
            
            group.wait()
        }
    }
    
    /// Clear all caches
    func clearAllCaches() {
        memoryCache.removeAllObjects()
        
        memoryCacheKeysLock.lock()
        memoryCacheKeys.removeAll()
        memoryCacheKeysLock.unlock()
        
        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.cacheDirectory)
            self.createCacheDirectoryIfNeeded()
        }
    }
    
    /// Clear memory cache only (keep disk cache)
    public func clearMemoryCache() {
        let count = memoryCache.totalCostLimit
        memoryCache.removeAllObjects()
        
        memoryCacheKeysLock.lock()
        let keyCount = memoryCacheKeys.count
        memoryCacheKeys.removeAll()
        memoryCacheKeysLock.unlock()
        
        Self.logger.info("Cleared image memory cache (\(keyCount) images) to free memory")
    }
    
    /// Clear expired entries only
    func clearExpiredEntries() {
        cleanupExpiredEntries()
    }
    
    /// Get cache statistics
    func getCacheStats() -> (memoryCount: Int, diskSizeMB: Double) {
        memoryCacheKeysLock.lock()
        let memoryCount = memoryCacheKeys.count
        memoryCacheKeysLock.unlock()
        
        var diskSize: Double = 0
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for file in files {
                if let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    diskSize += Double(size)
                }
            }
        } catch {
            // Silent failure for cache stats
        }
        
        return (memoryCount, diskSize / (1024 * 1024))
    }
    
    /// Check if image is cached (in memory or disk)
    public func isImageCached(url: URL) -> Bool {
        guard isValidImageURL(url) else { return false }
        
        let cacheKey = generateCacheKey(for: url)
        let key = cacheKey as NSString
        
        if memoryCache.object(forKey: key) != nil {
            return true
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey + ".jpg")
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// Check if multiple images are cached
    func areImagesCached(urls: [URL]) -> Bool {
        return urls.allSatisfy { isImageCached(url: $0) }
    }
    
    // MARK: - Private Methods
    
    private func isValidImageURL(_ url: URL) -> Bool {
        // Check if URL is valid and points to an image
        let urlString = url.absoluteString.lowercased()
        
        // Must be HTTP/HTTPS
        guard url.scheme == "http" || url.scheme == "https" else { return false }
        
        // Must have a host
        guard url.host != nil else { return false }
        
        // Check for common image extensions or iTunes artwork patterns
        let imageExtensions = [".jpg", ".jpeg", ".png", ".webp", ".gif"]
        let hasImageExtension = imageExtensions.contains { urlString.contains($0) }
        let isITunesArtwork = urlString.contains("is1-ssl.mzstatic.com") || 
                             urlString.contains("is2-ssl.mzstatic.com") ||
                             urlString.contains("is3-ssl.mzstatic.com") ||
                             urlString.contains("is4-ssl.mzstatic.com") ||
                             urlString.contains("is5-ssl.mzstatic.com")
        
        return hasImageExtension || isITunesArtwork
    }
    
    private func generateCacheKey(for url: URL) -> String {
        // Create a unique cache key using SHA256 hash of the URL
        let urlString = url.absoluteString
        let data = Data(urlString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func cache(image: UIImage, forKey key: NSString, fileURL: URL, originalURL: URL) {
        // Cache in memory
        let cachedImage = CachedImage(image: image, url: originalURL)
        self.memoryCache.setObject(cachedImage, forKey: key)
        
        // Track memory cache key
        memoryCacheKeysLock.lock()
        memoryCacheKeys.insert(key as String)
        memoryCacheKeysLock.unlock()
        
        // Cache on disk in background
        diskCacheQueue.async {
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
                
                // Save metadata
                let metadata = DiskCacheMetadata(
                    url: originalURL.absoluteString,
                    timestamp: Date().timeIntervalSince1970,
                    filename: fileURL.lastPathComponent
                )
                
                if let metadataData = try? JSONEncoder().encode(metadata) {
                    let metadataURL = fileURL.appendingPathExtension("meta")
                    try? metadataData.write(to: metadataURL)
                }
            }
        }
    }
    
    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    @objc private func handleMemoryWarning() {
        memoryCacheKeysLock.lock()
        let allKeys = Array(memoryCacheKeys)
        let keysToRemove = Array(allKeys.prefix(Int(Double(allKeys.count) * CacheConfig.memoryWarningCleanupRatio)))
        memoryCacheKeysLock.unlock()
        
        for keyString in keysToRemove {
            let key = NSString(string: keyString)
            memoryCache.removeObject(forKey: key)
        }
        
        memoryCacheKeysLock.lock()
        for key in keysToRemove {
            memoryCacheKeys.remove(key)
        }
        memoryCacheKeysLock.unlock()
    }
    
    private func cleanupExpiredEntries() {
        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                let metadataFiles = files.filter { $0.pathExtension == "meta" }
                
                var removedCount = 0
                for metadataFile in metadataFiles {
                    do {
                        let metadataData = try Data(contentsOf: metadataFile)
                        let metadata = try JSONDecoder().decode(DiskCacheMetadata.self, from: metadataData)
                        
                        if metadata.isExpired {
                            // Remove both metadata and image files
                            try? FileManager.default.removeItem(at: metadataFile)
                            let imageFile = self.cacheDirectory.appendingPathComponent(metadata.filename)
                            try? FileManager.default.removeItem(at: imageFile)
                            removedCount += 1
                        }
                    } catch {
                        // Remove corrupted metadata files
                        try? FileManager.default.removeItem(at: metadataFile)
                    }
                }
                
            } catch {
                // Silent failure for cleanup
            }
        }
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Download Operation

private class DownloadOperation: Operation, @unchecked Sendable {
    let url: URL
    private var completions: [(UIImage?) -> Void] = []
    private let completionsLock = NSLock()
    var downloadedImage: UIImage?
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ImageCache")
    
    private var _executing = false
    private var _finished = false
    private var task: URLSessionDataTask?
    
    override var isAsynchronous: Bool {
        return true
    }
    
    override var isExecuting: Bool {
        get { return _executing }
        set {
            willChangeValue(forKey: "isExecuting")
            _executing = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    override var isFinished: Bool {
        get { return _finished }
        set {
            willChangeValue(forKey: "isFinished")
            _finished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    
    init(url: URL) {
        self.url = url
        super.init()
    }
    
    func addCompletion(_ completion: @escaping (UIImage?) -> Void) {
        completionsLock.lock()
        completions.append(completion)
        completionsLock.unlock()
    }
    
    override func start() {
        guard !isCancelled else {
            isFinished = true
            return
        }
        
        isExecuting = true
        
        Task {
            do {
                // SIMPLE FIX: Use URLSession.shared directly - this is what actually works
                // URLSession.shared has the most reliable networking configuration
                let (data, _) = try await URLSession.shared.data(from: url)
                
                guard !self.isCancelled,
                      let image = UIImage(data: data) else {
                    self.finishOperation()
                    return
                }
                
                let urlStr = self.url.absoluteString
                self.logger.debug("ImageCache: URLSession.shared succeeded for \(urlStr)")
                self.downloadedImage = image
                self.finishOperation()
            } catch {
                let urlStr = self.url.absoluteString
                self.logger.error("ImageCache: URLSession.shared failed for \(urlStr) - \(error.localizedDescription)")
                self.finishOperation()
            }
        }
    }
    
    private func finishOperation() {
        isExecuting = false
        isFinished = true
        
        // Call all completions
        completionsLock.lock()
        let allCompletions = completions
        completionsLock.unlock()
        
        DispatchQueue.main.async {
            for completion in allCompletions {
                completion(self.downloadedImage)
            }
        }
    }
    
    override func cancel() {
        super.cancel()
        task?.cancel()
    }
}

// Actor to manage ongoing downloads safely across threads
private actor DownloadRegistry {
    private var operations: [URL: DownloadOperation] = [:]

    func operation(for url: URL) -> DownloadOperation? {
        operations[url]
    }

    func set(_ operation: DownloadOperation, for url: URL) {
        operations[url] = operation
    }

    func remove(url: URL) {
        operations.removeValue(forKey: url)
    }
}
