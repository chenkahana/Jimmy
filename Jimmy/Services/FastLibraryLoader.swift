import Foundation
import Combine
import GRDB

/// FastLibraryLoader provides optimized parallel loading for the library view
/// Uses multiple concurrent database queries to load podcast data quickly
class FastLibraryLoader {
    static let shared = FastLibraryLoader()
    
    private let maxConcurrentLoads = 4 // Limit concurrent database operations
    
    private init() {}
    
    /// Load all podcasts with parallel database queries
    /// This method loads podcast metadata in parallel for maximum speed
    func loadLibraryFast() async -> [Podcast] {
        
        do {
            // Wait for database to be ready
            await DatabaseManager.shared.waitForReady()
            
            // Get all podcast IDs first (fast query)
            let podcastIDs = try await DatabaseManager.shared.readAsync { db in
                // Fetch rows instead of direct strings to handle UUID properly
                let rows = try Row.fetchAll(db, sql: "SELECT id FROM podcasts ORDER BY title")
                return rows.compactMap { row -> String? in
                    // Handle UUID that might be stored as Data or String
                    if let uuidData = row["id"] as? Data {
                        // UUID stored as binary data (16 bytes)
                        let uuid = UUID(uuid: uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) })
                        return uuid.uuidString
                    } else if let uuidString = row["id"] as? String {
                        // UUID stored as string
                        return uuidString
                    } else {
                        // Skip this row if we can't parse the ID
                        return nil
                    }
                }
            }
            
            guard !podcastIDs.isEmpty else {
                return []
            }
            // Load podcasts in parallel batches
            let batchSize = maxConcurrentLoads
            let batches = podcastIDs.chunked(into: batchSize)
            var allPodcasts: [Podcast] = []
            
            for (batchIndex, batch) in batches.enumerated() {
                
                // Load batch concurrently
                let batchPodcasts = await withTaskGroup(of: Podcast?.self, returning: [Podcast].self) { group in
                    for podcastID in batch {
                        group.addTask { [weak self] in
                            await self?.loadSinglePodcast(id: podcastID)
                        }
                    }
                    
                    var results: [Podcast] = []
                    for await podcast in group {
                        if let podcast = podcast {
                            results.append(podcast)
                        }
                    }
                    return results
                }
                
                allPodcasts.append(contentsOf: batchPodcasts)
                
                // Small delay between batches to prevent overwhelming the database
                if batchIndex < batches.count - 1 {
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
            }
            
            // Sort by title for consistent display
            allPodcasts.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            
            return allPodcasts
            
        } catch {
            return []
        }
    }
    
    /// Load a single podcast from database
    private func loadSinglePodcast(id: String) async -> Podcast? {
        do {
            return try await DatabaseManager.shared.readAsync { db in
                try Podcast.fetchOne(db, sql: "SELECT * FROM podcasts WHERE id = ?", arguments: [id])
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Array Extension for Batching
extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
} 