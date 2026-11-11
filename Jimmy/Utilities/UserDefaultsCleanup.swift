import Foundation
import os

/// Utility to clean up large UserDefaults data that exceeds the 4MB limit
class UserDefaultsCleanup {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "UserDefaultsCleanup")
    static let shared = UserDefaultsCleanup()
    
    private init() {}
    
    /// Clean up large data from UserDefaults that should now be in file storage
    func performCleanup() {
        let defaults = UserDefaults.standard
        
        // Keys that have been migrated to file storage
        let keysToRemove = [
            "episodesKey",           // Migrated to episodes.json
            "episodeCacheData"       // Migrated to episodeCache.json
        ]
        
        var totalBytesFreed = 0
        
        for key in keysToRemove {
            if let data = defaults.object(forKey: key) {
                let size = estimateDataSize(data)
                defaults.removeObject(forKey: key)
                totalBytesFreed += size
            }
        }
        
        if totalBytesFreed > 0 {
            Self.logger.info("Total UserDefaults cleanup: \(self.formatBytes(totalBytesFreed))")
            
            // Synchronize to ensure changes are written
            defaults.synchronize()
        }
    }
    
    /// Get current UserDefaults usage statistics
    func getUsageStats() -> (totalKeys: Int, estimatedSize: Int, largeKeys: [(String, Int)]) {
        let defaults = UserDefaults.standard
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        
        var totalSize = 0
        var largeKeys: [(String, Int)] = []
        
        for key in allKeys {
            if let value = defaults.object(forKey: key) {
                let size = estimateDataSize(value)
                totalSize += size
                
                // Consider keys over 1MB as "large"
                if size > 1024 * 1024 {
                    largeKeys.append((key, size))
                }
            }
        }
        
        // Sort large keys by size (largest first)
        largeKeys.sort { $0.1 > $1.1 }
        
        return (allKeys.count, totalSize, largeKeys)
    }
    
    /// Print current UserDefaults usage
    func printUsageStats() {
        let (totalKeys, estimatedSize, largeKeys) = getUsageStats()
        
        Self.logger.debug("UserDefaults Usage:")
        Self.logger.debug("Total keys: \(totalKeys)")
        Self.logger.debug("Estimated size: \(self.formatBytes(estimatedSize))")
        
        if !largeKeys.isEmpty {
            Self.logger.debug("Large keys (>1MB):")
            for (key, size) in largeKeys {
                Self.logger.debug("Large key: \(key): \(self.formatBytes(size))")
            }
        }
        
        // Check if approaching limit
        let limit = 4 * 1024 * 1024 // 4MB
        if estimatedSize > limit * 3 / 4 { // 75% of limit
            Self.logger.warning("Approaching 4MB UserDefaults limit")
        }
    }
    
    // MARK: - Private Methods
    
    private func estimateDataSize(_ object: Any) -> Int {
        switch object {
        case let data as Data:
            return data.count
        case let string as String:
            return string.utf8.count
        case let array as NSArray:
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: array, requiringSecureCoding: false)
                return data.count
            } catch {
                return 0
            }
        case let dict as NSDictionary:
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false)
                return data.count
            } catch {
                return 0
            }
        default:
            // For primitive types, estimate small size
            return 64 // bytes
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
} 