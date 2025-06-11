import Foundation
import SwiftUI
import UIKit
import CryptoKit
import Combine

/// A comprehensive image caching solution for podcast artwork
/// Handles both memory and disk caching with proper cache expiration
public class ImageCache: ObservableObject {
    public static let shared = ImageCache()
    
    // MARK: - Cache Configuration
    
    struct CacheConfig {
        static let memoryCapacity = 50 * 1024 * 1024 // 50MB memory cache
        static let diskCapacity = 200 * 1024 * 1024 // 200MB disk cache
        static let maxConcurrentDownloads = 5
        static let downloadTimeout: TimeInterval = 15.0
        static let cacheExpiration: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        static let memoryWarningCleanupRatio: Double = 0.5 // Remove 50% on memory warning
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
    
    // Track ongoing downloads to prevent duplicate requests
    private var ongoingDownloads: [URL: DownloadOperation] = [:]
    private let downloadsLock = NSLock()
    
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
        // Setup operation queue for downloads
        operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = CacheConfig.maxConcurrentDownloads
        operationQueue.qualityOfService = .userInitiated
        
        // Setup memory cache
        memoryCache.countLimit = 100 // Max 100 images in memory
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
        
        // Clean expired entries on startup
        cleanupExpiredEntries()
    }
    
    // MARK: - Public Interface
    
    /// Load image with caching
    /// Returns cached image immediately if available, otherwise downloads and caches
    public func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString as NSString
        
        // 1. Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key) {
            completion(cachedImage.image)
            return
        }
        
        // 2. Check disk cache
        let fileURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)
        if let image = UIImage(contentsOfFile: fileURL.path) {
            self.memoryCache.setObject(CachedImage(image: image, url: url), forKey: key)
            completion(image)
            return
        }
        
        // 3. Fetch from network
        URLSession.shared.dataTaskPublisher(for: url)
            .map { UIImage(data: $0.data) }
            .replaceError(with: nil)
            .handleEvents(receiveOutput: { [weak self] image in
                guard let image = image else { return }
                self?.cache(image: image, forKey: key, fileURL: fileURL)
            })
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: completion)
            .store(in: &cancellables)
    }
    
    /// Preload images for URLs (useful for prefetching)
    public func preloadImages(urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        
        print("🖼️ [ImageCache] Preloading \(urls.count) images...")
        let qos: DispatchQoS.QoSClass = .utility
        
        DispatchQueue.global(qos: qos).async {
            let group = DispatchGroup()
            
            for url in urls {
                // Don't re-download if it's already in the cache
                guard !self.isImageCached(url: url) else { continue }
                
                group.enter()
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let self = self,
                          let data = data,
                          let image = UIImage(data: data) else {
                        group.leave()
                        return
                    }
                    
                    let key = url.absoluteString as NSString
                    let fileURL = self.cacheDirectory.appendingPathComponent(url.lastPathComponent)
                    self.cache(image: image, forKey: key, fileURL: fileURL)
                    
                    group.leave()
                }.resume()
            }
            
            group.wait()
            print("✅ [ImageCache] Preloading complete.")
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
            print("❌ Failed to calculate disk cache size: \(error)")
        }
        
        return (memoryCount, diskSize / (1024 * 1024))
    }
    
    /// Check if image is cached (in memory or disk)
    public func isImageCached(url: URL) -> Bool {
        let key = url.absoluteString as NSString
        if memoryCache.object(forKey: key) != nil {
            return true
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// Check if multiple images are cached
    func areImagesCached(urls: [URL]) -> Bool {
        return urls.allSatisfy { isImageCached(url: $0) }
    }
    
    // MARK: - Private Methods
    
    private func cache(image: UIImage, forKey key: NSString, fileURL: URL) {
        // Cache in memory
        self.memoryCache.setObject(CachedImage(image: image, url: fileURL), forKey: key)
        
        // Cache on disk in background
        DispatchQueue.global(qos: .background).async {
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
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
        
        print("🧹 Cleared \(keysToRemove.count) images from memory cache due to memory warning")
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
                
                if removedCount > 0 {
                    print("🧹 Cleaned up \(removedCount) expired image cache entries")
                }
                
            } catch {
                print("❌ Failed to cleanup expired cache entries: \(error)")
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
    
    func notifyCompletions(with image: UIImage?) {
        completionsLock.lock()
        let allCompletions = completions
        completions.removeAll()
        completionsLock.unlock()
        
        for completion in allCompletions {
            completion(image)
        }
    }
    
    override func start() {
        if isCancelled {
            isFinished = true
            return
        }
        
        isExecuting = true
        
        var request = URLRequest(url: url)
        request.timeoutInterval = ImageCache.CacheConfig.downloadTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            defer {
                self.isExecuting = false
                self.isFinished = true
            }
            
            if self.isCancelled {
                return
            }
            
            if let error = error {
                print("❌ Image download failed for \(self.url): \(error.localizedDescription)")
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                print("❌ Invalid image data from \(self.url)")
                return
            }
            
            self.downloadedImage = self.optimizeImageForCache(image)
        }
        
        task?.resume()
    }
    
    override func cancel() {
        super.cancel()
        task?.cancel()
    }
    
    private func optimizeImageForCache(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 600 // Max size for podcast artwork
        let currentMaxDimension = max(image.size.width, image.size.height)
        
        guard currentMaxDimension > maxDimension else { return image }
        
        let scaleFactor = maxDimension / currentMaxDimension
        let newSize = CGSize(
            width: image.size.width * scaleFactor,
            height: image.size.height * scaleFactor
        )
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let optimizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return optimizedImage
    }
}
