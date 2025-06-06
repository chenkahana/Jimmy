import Foundation
import SwiftUI
import UIKit

/// A comprehensive image caching solution for podcast artwork
/// Handles both memory and disk caching with proper cache expiration
class ImageCache: ObservableObject {
    static let shared = ImageCache()
    
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

    // Notification token for memory warning observer
    private var memoryWarningObserver: NSObjectProtocol?
    
    // Track ongoing downloads to prevent duplicate requests
    private var ongoingDownloads: [URL: DownloadOperation] = [:]
    private let downloadsLock = NSLock()
    
    // Track memory cache keys for cleanup
    private var memoryCacheKeys: Set<String> = []
    private let memoryCacheKeysLock = NSLock()
    
    // Cache directory
    private let cacheDirectory: URL
    
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
        
        // Setup disk cache directory
        let documentsPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("ImageCache")
        
        createCacheDirectoryIfNeeded()
        setupMemoryWarningObserver()
        
        // Clean expired entries on startup
        cleanupExpiredEntries()
    }
    
    // MARK: - Public Interface
    
    /// Load image with caching
    /// Returns cached image immediately if available, otherwise downloads and caches
    func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        // First check memory cache
        if let cachedImage = getFromMemoryCache(url: url) {
            completion(cachedImage.image)
            return
        }
        
        // Check disk cache
        loadFromDiskCache(url: url) { [weak self] diskImage in
            if let diskImage = diskImage {
                // Add to memory cache and return
                self?.addToMemoryCache(image: diskImage, url: url)
                DispatchQueue.main.async {
                    completion(diskImage)
                }
                return
            }
            
            // Download from network
            self?.downloadAndCache(url: url, completion: completion)
        }
    }
    
    /// Preload images for URLs (useful for prefetching)
    func preloadImages(urls: [URL]) {
        for url in urls {
            loadImage(from: url) { _ in
                // Silent preload - no completion handling needed
            }
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
    
    // MARK: - Private Methods
    
    private func getFromMemoryCache(url: URL) -> CachedImage? {
        let key = NSString(string: url.absoluteString)
        guard let cachedImage = memoryCache.object(forKey: key) else { return nil }
        
        if cachedImage.isExpired {
            memoryCache.removeObject(forKey: key)
            memoryCacheKeysLock.lock()
            memoryCacheKeys.remove(url.absoluteString)
            memoryCacheKeysLock.unlock()
            return nil
        }
        
        return cachedImage
    }
    
    private func addToMemoryCache(image: UIImage, url: URL) {
        let cachedImage = CachedImage(image: image, url: url)
        let key = NSString(string: url.absoluteString)
        
        // Estimate image memory cost
        let cost = Int(image.size.width * image.size.height * 4) // 4 bytes per pixel (RGBA)
        memoryCache.setObject(cachedImage, forKey: key, cost: cost)
        
        memoryCacheKeysLock.lock()
        memoryCacheKeys.insert(url.absoluteString)
        memoryCacheKeysLock.unlock()
    }
    
    private func loadFromDiskCache(url: URL, completion: @escaping (UIImage?) -> Void) {
        diskCacheQueue.async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            let filename = self.cacheFilename(for: url)
            let imagePath = self.cacheDirectory.appendingPathComponent(filename)
            let metadataPath = self.cacheDirectory.appendingPathComponent(filename + ".meta")
            
            // Check if files exist
            guard FileManager.default.fileExists(atPath: imagePath.path),
                  FileManager.default.fileExists(atPath: metadataPath.path) else {
                completion(nil)
                return
            }
            
            // Check metadata for expiration
            do {
                let metadataData = try Data(contentsOf: metadataPath)
                let metadata = try JSONDecoder().decode(DiskCacheMetadata.self, from: metadataData)
                
                if metadata.isExpired {
                    // Remove expired files
                    try? FileManager.default.removeItem(at: imagePath)
                    try? FileManager.default.removeItem(at: metadataPath)
                    completion(nil)
                    return
                }
                
                // Load image
                if let imageData = try? Data(contentsOf: imagePath),
                   let image = UIImage(data: imageData) {
                    completion(image)
                } else {
                    completion(nil)
                }
                
            } catch {
                print("❌ Failed to load image metadata: \(error)")
                completion(nil)
            }
        }
    }
    
    private func downloadAndCache(url: URL, completion: @escaping (UIImage?) -> Void) {
        downloadsLock.lock()
        
        // Check if download is already in progress
        if let existingOperation = ongoingDownloads[url] {
            existingOperation.addCompletion(completion)
            downloadsLock.unlock()
            return
        }
        
        // Create new download operation
        let operation = DownloadOperation(url: url)
        operation.addCompletion(completion)
        ongoingDownloads[url] = operation
        downloadsLock.unlock()
        
        // Configure download operation
        operation.completionBlock = { [weak self, weak operation] in
            guard let self = self, let operation = operation else { return }
            
            self.downloadsLock.lock()
            self.ongoingDownloads.removeValue(forKey: url)
            self.downloadsLock.unlock()
            
            if let image = operation.downloadedImage {
                // Cache the image
                self.addToMemoryCache(image: image, url: url)
                self.saveToDiskCache(image: image, url: url)
            }
            
            // Notify all waiting completions
            DispatchQueue.main.async {
                operation.notifyCompletions(with: operation.downloadedImage)
            }
        }
        
        operationQueue.addOperation(operation)
    }
    
    private func saveToDiskCache(image: UIImage, url: URL) {
        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let filename = self.cacheFilename(for: url)
            let imagePath = self.cacheDirectory.appendingPathComponent(filename)
            let metadataPath = self.cacheDirectory.appendingPathComponent(filename + ".meta")
            
            // Save image data
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                do {
                    try imageData.write(to: imagePath)
                    
                    // Save metadata
                    let metadata = DiskCacheMetadata(
                        url: url.absoluteString,
                        timestamp: Date().timeIntervalSince1970,
                        filename: filename
                    )
                    
                    let metadataData = try JSONEncoder().encode(metadata)
                    try metadataData.write(to: metadataPath)
                    
                } catch {
                    print("❌ Failed to save image to disk cache: \(error)")
                }
            }
        }
    }
    
    private func cacheFilename(for url: URL) -> String {
        return url.absoluteString.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-") ?? UUID().uuidString
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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
}

// MARK: - Download Operation

private class DownloadOperation: Operation, @unchecked Sendable {
    let url: URL
    private var completions: [(UIImage?) -> Void] = []
    private let completionsLock = NSLock()
    var downloadedImage: UIImage?
    
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
    
    override func main() {
        guard !isCancelled else { return }
        
        let semaphore = DispatchSemaphore(value: 0)
        
        var request = URLRequest(url: url)
        request.timeoutInterval = ImageCache.CacheConfig.downloadTimeout
        request.cachePolicy = .useProtocolCachePolicy
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            
            guard let self = self, !self.isCancelled else { return }
            
            if let error = error {
                print("❌ Image download failed for \(self.url): \(error.localizedDescription)")
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                print("❌ Invalid image data from \(self.url)")
                return
            }
            
            // Optimize image size for memory efficiency
            self.downloadedImage = self.optimizeImageForCache(image)
        }
        
        task.resume()
        semaphore.wait()
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

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
