import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Utility for storing large data in files instead of UserDefaults
/// UserDefaults has a 4MB limit, so we use file storage for larger datasets
class FileStorage {
    static let shared = FileStorage()

    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let ioQueue = DispatchQueue(label: "file-storage-io", qos: .utility)
#if canImport(OSLog)
    private let logger = Logger(subsystem: "com.jimmy.app", category: "filestorage")
#endif
    
    private init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create storage directory if it doesn't exist
        let storageDirectory = documentsDirectory.appendingPathComponent("AppData")
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Public Interface
    
    /// Save Codable object to file. If disk space is critically low the save
    /// is skipped and `false` is returned.
    func save<T: Codable>(_ object: T, to filename: String) -> Bool {
        let url = getFileURL(for: filename)

        do {
            let data = try JSONEncoder().encode(object)

            // Ensure we have at least 5MB free before attempting to write.
            if !hasEnoughDiskSpace(for: data.count) {
#if canImport(OSLog)
                logger.warning("Not enough disk space to save \(filename, privacy: .public). Skipping write")
#else
                print("⚠️ Not enough disk space to save \(filename). Skipping write")
#endif
                return false
            }

            try data.write(to: url)
#if canImport(OSLog)
            logger.info("Saved \(filename, privacy: .public) (\(data.count) bytes)")
#else
            print("💾 Saved \(filename) (\(data.count) bytes)")
#endif
            return true
        } catch {
            #if canImport(OSLog)
            logger.error("Failed to save \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #else
            print("❌ Failed to save \(filename): \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Load Codable object from file
    func load<T: Codable>(_ type: T.Type, from filename: String) -> T? {
        let url = getFileURL(for: filename)

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let object = try JSONDecoder().decode(type, from: data)
#if canImport(OSLog)
            logger.info("Loaded \(filename, privacy: .public) (\(data.count) bytes)")
#else
            print("📱 Loaded \(filename) (\(data.count) bytes)")
#endif
            return object
        } catch {
            // Move the corrupted file aside so future loads don't keep failing
            let corruptURL = url.appendingPathExtension("corrupt")
            try? fileManager.moveItem(at: url, to: corruptURL)
            #if canImport(OSLog)
            logger.error("Failed to load \(filename, privacy: .public): \(error.localizedDescription, privacy: .public). Moved to \(corruptURL.lastPathComponent, privacy: .public)")
            #else
            print("❌ Failed to load \(filename): \(error.localizedDescription). Moved to \(corruptURL.lastPathComponent)")
            #endif
            return nil
        }
    }
    
    /// Delete file
    func delete(_ filename: String) -> Bool {
        let url = getFileURL(for: filename)
        
        guard fileManager.fileExists(atPath: url.path) else {
            return true // Already doesn't exist
        }
        
        do {
            try fileManager.removeItem(at: url)
#if canImport(OSLog)
            logger.info("Deleted \(filename, privacy: .public)")
#else
            print("🗑️ Deleted \(filename)")
#endif
            return true
        } catch {
            #if canImport(OSLog)
            logger.error("Failed to delete \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #else
            print("❌ Failed to delete \(filename): \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    /// Check if file exists
    func exists(_ filename: String) -> Bool {
        let url = getFileURL(for: filename)
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// Get file size in bytes
    func getFileSize(_ filename: String) -> Int64? {
        let url = getFileURL(for: filename)
        
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    /// Migrate data from UserDefaults to file storage
    func migrateFromUserDefaults<T: Codable>(_ type: T.Type, userDefaultsKey: String, filename: String) -> T? {
        // Check if file already exists
        if exists(filename) {
            return load(type, from: filename)
        }
        
        // Try to load from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let object = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        
        // Save to file
        if save(object, to: filename) {
            // Clear from UserDefaults to free up space
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
#if canImport(OSLog)
            logger.info("Migrated \(userDefaultsKey, privacy: .public) from UserDefaults to file storage")
#else
            print("📦 Migrated \(userDefaultsKey) from UserDefaults to file storage")
#endif
            return object
        }
        
        return nil
    }

    // MARK: - Async Interface

    /// Save Codable object to file asynchronously
    func saveAsync<T: Codable>(_ object: T, to filename: String, completion: ((Bool) -> Void)? = nil) {
        ioQueue.async {
            let result = self.save(object, to: filename)
            if let completion = completion {
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Load Codable object from file asynchronously
    func loadAsync<T: Codable>(_ type: T.Type, from filename: String, completion: @escaping (T?) -> Void) {
        ioQueue.async {
            let result = self.load(type, from: filename)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    // MARK: - Private Methods
    
    private func getFileURL(for filename: String) -> URL {
        return documentsDirectory
            .appendingPathComponent("AppData")
            .appendingPathComponent(filename)
    }

    /// Returns available disk space in bytes for the documents volume.
    private func getAvailableDiskSpace() -> Int64 {
        do {
            let values = try documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            return 0
        }
    }

    /// Check whether there is enough free disk space to write data of the given size
    /// and keep at least 5MB free.
    private func hasEnoughDiskSpace(for dataLength: Int) -> Bool {
        let available = getAvailableDiskSpace()
        let minimumFree: Int64 = 5 * 1024 * 1024
        return available - Int64(dataLength) > minimumFree
    }
    
    // MARK: - Storage Statistics
    
    /// Get total storage used by file storage in bytes
    func getTotalStorageUsed() -> Int64 {
        let storageDirectory = documentsDirectory.appendingPathComponent("AppData")
        
        guard let enumerator = fileManager.enumerator(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    /// Get formatted storage size string
    func getFormattedStorageSize() -> String {
        let bytes = getTotalStorageUsed()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
} 