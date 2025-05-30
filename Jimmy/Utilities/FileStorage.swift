import Foundation

/// Utility for storing large data in files instead of UserDefaults
/// UserDefaults has a 4MB limit, so we use file storage for larger datasets
class FileStorage {
    static let shared = FileStorage()
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    
    private init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create storage directory if it doesn't exist
        let storageDirectory = documentsDirectory.appendingPathComponent("AppData")
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Public Interface
    
    /// Save Codable object to file
    func save<T: Codable>(_ object: T, to filename: String) -> Bool {
        let url = getFileURL(for: filename)
        
        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: url)
            print("💾 Saved \(filename) (\(data.count) bytes)")
            return true
        } catch {
            print("❌ Failed to save \(filename): \(error.localizedDescription)")
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
            print("📱 Loaded \(filename) (\(data.count) bytes)")
            return object
        } catch {
            print("❌ Failed to load \(filename): \(error.localizedDescription)")
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
            print("🗑️ Deleted \(filename)")
            return true
        } catch {
            print("❌ Failed to delete \(filename): \(error.localizedDescription)")
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
            print("📦 Migrated \(userDefaultsKey) from UserDefaults to file storage")
            return object
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    private func getFileURL(for filename: String) -> URL {
        return documentsDirectory
            .appendingPathComponent("AppData")
            .appendingPathComponent(filename)
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