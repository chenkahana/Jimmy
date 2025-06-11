import Foundation
import SwiftUI
import OSLog

/// Thread-safe repository for episode data with reader-writer lock pattern
/// Prevents concurrent read/write collisions and ensures data integrity
@MainActor
final class EpisodeRepository: ObservableObject {
    static let shared = EpisodeRepository()
    
    // MARK: - Published Properties
    
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastUpdateTime: Date?
    @Published private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    
    /// Concurrent queue for reader-writer lock pattern
    private let dataQueue = DispatchQueue(
        label: "episode.repository.data",
        qos: .userInitiated,
        attributes: .concurrent
    )
    
    /// Serial queue for persistence operations
    private let persistenceQueue = DispatchQueue(
        label: "episode-repository-persistence",
        qos: .utility
    )
    
    /// Played episode IDs for quick lookup
    private var playedEpisodeIDs: Set<UUID> = []
    
    /// Cache metadata
    private var cacheMetadata: CacheMetadata = CacheMetadata()
    
    /// Data integrity validation
    private var dataIntegrityHash: String = ""
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "EpisodeRepository")
    #endif
    
    // MARK: - Cache Metadata
    
    private struct CacheMetadata: Codable {
        var lastUpdated: Date = Date()
        var episodeCount: Int = 0
        var version: String = "1.0"
        var dataIntegrityHash: String = ""
        
        var needsRefresh: Bool {
            Date().timeIntervalSince(lastUpdated) > 3600 // 1 hour
        }
    }
    
    // MARK: - Error Types
    
    enum RepositoryError: Error, LocalizedError {
        case dataCorruption(String)
        case timeoutError(String)
        case validationError(String)
        case persistenceError(String)
        
        var errorDescription: String? {
            switch self {
            case .dataCorruption(let message):
                return "Data corruption detected: \(message)"
            case .timeoutError(let message):
                return "Operation timed out: \(message)"
            case .validationError(let message):
                return "Data validation failed: \(message)"
            case .persistenceError(let message):
                return "Persistence error: \(message)"
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadInitialData()
    }
    
    // MARK: - Public Interface with Timeout Protection
    
    /// Get all episodes (thread-safe with timeout)
    func getAllEpisodes() async -> [Episode] {
        return await withTimeout(seconds: 5.0) { [self] in
            return await withCheckedContinuation { continuation in
                self.dataQueue.async { [weak self] in
                    let episodes = self?.episodes ?? []
                    continuation.resume(returning: episodes)
                }
            }
        } ?? []
    }
    
    /// Get episodes for a specific podcast (thread-safe with timeout)
    func getEpisodes(for podcastID: UUID) async -> [Episode] {
        return await withTimeout(seconds: 3.0) { [self] in
            return await withCheckedContinuation { continuation in
                self.dataQueue.async { [weak self] in
                    let episodes = self?.episodes.filter { $0.podcastID == podcastID } ?? []
                    continuation.resume(returning: episodes)
                }
            }
        } ?? []
    }
    
    /// Get episode count (thread-safe with timeout)
    func getEpisodeCount() async -> Int {
        return await withTimeout(seconds: 2.0) { [self] in
            return await withCheckedContinuation { continuation in
                self.dataQueue.async { [weak self] in
                    let count = self?.episodes.count ?? 0
                    continuation.resume(returning: count)
                }
            }
        } ?? 0
    }
    
    /// Check if cache needs refresh (thread-safe with timeout)
    func needsRefresh() async -> Bool {
        return await withTimeout(seconds: 1.0) { [self] in
            return await withCheckedContinuation { continuation in
                self.dataQueue.async { [weak self] in
                    let needs = self?.cacheMetadata.needsRefresh ?? true
                    continuation.resume(returning: needs)
                }
            }
        } ?? true
    }
    
    /// Get cache statistics for debugging
    func getCacheStats() async -> (count: Int, needsRefresh: Bool, lastUpdated: Date) {
        return await withTimeout(seconds: 2.0) { [self] in
            return await withCheckedContinuation { continuation in
                self.dataQueue.async { [weak self] in
                    let count = self?.episodes.count ?? 0
                    let needs = self?.cacheMetadata.needsRefresh ?? true
                    let lastUpdated = self?.cacheMetadata.lastUpdated ?? Date.distantPast
                    
                    continuation.resume(returning: (
                        count: count,
                        needsRefresh: needs,
                        lastUpdated: lastUpdated
                    ))
                }
            }
        } ?? (count: 0, needsRefresh: true, lastUpdated: Date.distantPast)
    }
    
    /// Set loading state
    func setLoading(_ loading: Bool) async {
        isLoading = loading
    }
    
    /// Get cache metadata
    private func getCacheMetadata() async -> CacheMetadata {
        return await withCheckedContinuation { continuation in
            dataQueue.async { [weak self] in
                continuation.resume(returning: CacheMetadata(
                    lastUpdated: self?.cacheMetadata.lastUpdated ?? Date.distantPast,
                    episodeCount: self?.episodes.count ?? 0,
                    version: self?.cacheMetadata.version ?? "1.0",
                    dataIntegrityHash: self?.dataIntegrityHash ?? ""
                ))
            }
        }
    }
    
    // MARK: - Update Operations with Data Integrity
    
    enum UpdateSource {
        case userInitiated
        case backgroundRefresh
        case cache
    }
    
    /// Atomic batch update with data integrity validation
    func batchUpdateEpisodes(_ updates: [EpisodeUpdate]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                Task { @MainActor in
                    do {
                        guard let self = self else {
                            continuation.resume(throwing: RepositoryError.dataCorruption("Repository deallocated"))
                            return
                        }
                        
                        // Validate updates before applying
                        try self.validateEpisodeUpdates(updates)
                        
                        // Apply all updates atomically
                        for update in updates {
                            try self.applyEpisodeUpdate(update)
                        }
                        
                        // Update integrity hash
                        self.updateDataIntegrityHash()
                        
                        // Update cache metadata
                        self.updateCacheMetadata()
                        
                        #if canImport(OSLog)
                        self.logger.info("✅ Applied \(updates.count) episode updates atomically")
                        #endif
                        
                        // Save in background
                        Task.detached(priority: .utility) { [weak self] in
                            await self?.saveEpisodesToDisk()
                        }
                        
                        continuation.resume()
                        
                    } catch {
                        #if canImport(OSLog)
                        self?.logger.error("❌ Batch update failed: \(error.localizedDescription)")
                        #endif
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Update episodes with new data (thread-safe with validation)
    func updateEpisodes(_ newEpisodes: [Episode], source: UpdateSource) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                Task { @MainActor in
                    do {
                        guard let self = self else {
                            continuation.resume(throwing: RepositoryError.dataCorruption("Repository deallocated"))
                            return
                        }
                        
                        // Validate episodes before updating
                        try self.validateEpisodes(newEpisodes)
                        
                        self.performEpisodeUpdate(newEpisodes, source: source)
                        
                        // Update integrity hash
                        self.updateDataIntegrityHash()
                        
                        continuation.resume()
                        
                    } catch {
                        #if canImport(OSLog)
                        self?.logger.error("❌ Episode update failed: \(error.localizedDescription)")
                        #endif
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Add new episodes without replacing existing ones (with validation)
    func addNewEpisodes(_ newEpisodes: [Episode]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                Task { @MainActor in
                    do {
                        guard let self = self else {
                            continuation.resume(throwing: RepositoryError.dataCorruption("Repository deallocated"))
                            return
                        }
                        
                        // Validate episodes before adding
                        try self.validateEpisodes(newEpisodes)
                        
                        let existingIDs = Set(self.episodes.map { $0.id })
                        let episodesToAdd = newEpisodes.filter { !existingIDs.contains($0.id) }
                        
                        if !episodesToAdd.isEmpty {
                            self.episodes.append(contentsOf: episodesToAdd)
                            self.sortEpisodes()
                            self.updateCacheMetadata()
                            self.updateDataIntegrityHash()
                            
                            #if canImport(OSLog)
                            self.logger.info("📥 Added \(episodesToAdd.count) new episodes")
                            #endif
                            
                            // Save in background
                            Task.detached(priority: .utility) { [weak self] in
                                await self?.saveEpisodesToDisk()
                            }
                        }
                        
                        continuation.resume()
                        
                    } catch {
                        #if canImport(OSLog)
                        self?.logger.error("❌ Add episodes failed: \(error.localizedDescription)")
                        #endif
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Mark episode as played
    func markEpisodeAsPlayed(_ episodeID: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    if let index = self.episodes.firstIndex(where: { $0.id == episodeID }) {
                        self.episodes[index].played = true
                        self.playedEpisodeIDs.insert(episodeID)
                        self.updateDataIntegrityHash()
                        
                        #if canImport(OSLog)
                        self.logger.info("✅ Marked episode as played: \(episodeID)")
                        #endif
                        
                        // Save played episodes in background
                        Task.detached(priority: .utility) { [weak self] in
                            await self?.savePlayedEpisodeIDs()
                        }
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// Mark episode as unplayed
    func markEpisodeAsUnplayed(_ episodeID: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    if let index = self.episodes.firstIndex(where: { $0.id == episodeID }) {
                        self.episodes[index].played = false
                        self.playedEpisodeIDs.remove(episodeID)
                        self.updateDataIntegrityHash()
                        
                        #if canImport(OSLog)
                        self.logger.info("⭕ Marked episode as unplayed: \(episodeID)")
                        #endif
                        
                        // Save played episodes in background
                        Task.detached(priority: .utility) { [weak self] in
                            await self?.savePlayedEpisodeIDs()
                        }
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// Clear all episodes
    func clearAllEpisodes() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataQueue.async(flags: .barrier) { [weak self] in
                Task { @MainActor in
                    self?.episodes.removeAll()
                    self?.playedEpisodeIDs.removeAll()
                    self?.cacheMetadata = CacheMetadata()
                    self?.dataIntegrityHash = ""
                    
                    #if canImport(OSLog)
                    self?.logger.info("🗑️ Cleared all episodes")
                    #endif
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// Validate data integrity
    func validateDataIntegrity() async throws {
        let currentHash = await calculateDataIntegrityHash()
        
        if !dataIntegrityHash.isEmpty && currentHash != dataIntegrityHash {
            throw RepositoryError.dataCorruption("Data integrity hash mismatch")
        }
        
        // Additional validation checks
        let episodes = await getAllEpisodes()
        try validateEpisodes(episodes)
    }
    
    // MARK: - Private Methods
    
    /// Timeout wrapper for async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
    
    /// Validate episodes data
    private func validateEpisodes(_ episodes: [Episode]) throws {
        for episode in episodes {
            // Check required fields
            if episode.title.isEmpty {
                throw RepositoryError.validationError("Episode title cannot be empty")
            }
            
            if episode.podcastID == nil {
                throw RepositoryError.validationError("Episode must have a podcast ID")
            }
            
            // Check for duplicate IDs
            let episodeIDs = episodes.map { $0.id }
            let uniqueIDs = Set(episodeIDs)
            if episodeIDs.count != uniqueIDs.count {
                throw RepositoryError.validationError("Duplicate episode IDs detected")
            }
        }
    }
    
    /// Validate episode updates
    private func validateEpisodeUpdates(_ updates: [EpisodeUpdate]) throws {
        for update in updates {
            switch update {
            case .markAsPlayed(let episodeID), .markAsUnplayed(let episodeID):
                if !episodes.contains(where: { $0.id == episodeID }) {
                    throw RepositoryError.validationError("Episode not found for update: \(episodeID)")
                }
            case .updatePlaybackPosition(let episodeID, let position):
                if !episodes.contains(where: { $0.id == episodeID }) {
                    throw RepositoryError.validationError("Episode not found for update: \(episodeID)")
                }
                if position < 0 {
                    throw RepositoryError.validationError("Invalid playback position: \(position)")
                }
            }
        }
    }
    
    /// Apply individual episode update
    private func applyEpisodeUpdate(_ update: EpisodeUpdate) throws {
        switch update {
        case .markAsPlayed(let episodeID):
            if let index = episodes.firstIndex(where: { $0.id == episodeID }) {
                episodes[index].played = true
                playedEpisodeIDs.insert(episodeID)
            }
        case .markAsUnplayed(let episodeID):
            if let index = episodes.firstIndex(where: { $0.id == episodeID }) {
                episodes[index].played = false
                playedEpisodeIDs.remove(episodeID)
            }
        case .updatePlaybackPosition(let episodeID, let position):
            if let index = episodes.firstIndex(where: { $0.id == episodeID }) {
                episodes[index].playbackPosition = position
            }
        }
    }
    
    /// Calculate data integrity hash
    private func calculateDataIntegrityHash() async -> String {
        let episodes = await getAllEpisodes()
        let episodeData = episodes.map { "\($0.id):\($0.title):\($0.played)" }.joined(separator: "|")
        return String(episodeData.hashValue)
    }
    
    /// Update data integrity hash
    private func updateDataIntegrityHash() {
        Task {
            dataIntegrityHash = await calculateDataIntegrityHash()
            cacheMetadata.dataIntegrityHash = dataIntegrityHash
        }
    }
    
    private func loadInitialData() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loadEpisodesFromDisk()
            await self?.loadPlayedEpisodeIDsFromDisk()
            await self?.loadCacheMetadataFromDisk()
            
            // Validate data integrity after loading
            do {
                try await self?.validateDataIntegrity()
            } catch {
                #if canImport(OSLog)
                self?.logger.error("❌ Data integrity validation failed: \(error.localizedDescription)")
                #endif
                
                // Clear corrupted data
                await self?.clearAllEpisodes()
            }
        }
    }
    
    private func loadEpisodesFromDisk() async {
        let loadedEpisodes: [Episode] = FileStorage.shared.load([Episode].self, from: "episodes.json") ?? []
        
        await MainActor.run { [weak self] in
            self?.episodes = loadedEpisodes
        }
        
        #if canImport(OSLog)
        logger.info("📱 Loaded \(loadedEpisodes.count) episodes from disk")
        #endif
    }
    
    private func loadPlayedEpisodeIDsFromDisk() async {
        let loadedIDs: [UUID] = FileStorage.shared.load([UUID].self, from: "playedEpisodeIDs.json") ?? []
        playedEpisodeIDs = Set(loadedIDs)
        
        #if canImport(OSLog)
        logger.info("📱 Loaded \(loadedIDs.count) played episode IDs from disk")
        #endif
    }
    
    private func loadCacheMetadataFromDisk() async {
        let metadata: CacheMetadata = FileStorage.shared.load(CacheMetadata.self, from: "episodeCacheMetadata.json") ?? CacheMetadata()
        
        await MainActor.run { [weak self] in
            self?.cacheMetadata = metadata
            self?.dataIntegrityHash = metadata.dataIntegrityHash
        }
        
        #if canImport(OSLog)
        logger.info("📱 Loaded cache metadata from disk")
        #endif
    }
    
    private func performEpisodeUpdate(_ newEpisodes: [Episode], source: UpdateSource) {
        // Sort episodes by published date (newest first)
        let sortedEpisodes = newEpisodes.sorted { episode1, episode2 in
            let date1 = episode1.publishedDate ?? Date.distantPast
            let date2 = episode2.publishedDate ?? Date.distantPast
            return date1 > date2
        }
        
        episodes = sortedEpisodes
        
        // Update cache metadata
        cacheMetadata.episodeCount = episodes.count
        cacheMetadata.lastUpdated = Date()
        
        #if canImport(OSLog)
        logger.info("📥 Updated \(newEpisodes.count) episodes from source")
        #endif
        
        // Save to disk in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.saveEpisodesToDisk()
            await self?.saveCacheMetadata()
        }
    }
    
    private func sortEpisodes() {
        episodes.sort { episode1, episode2 in
            let date1 = episode1.publishedDate ?? Date.distantPast
            let date2 = episode2.publishedDate ?? Date.distantPast
            return date1 > date2
        }
    }
    
    private func updateCacheMetadata() {
        cacheMetadata.episodeCount = episodes.count
        cacheMetadata.lastUpdated = Date()
    }
    
    private func saveEpisodesToDisk() async {
        let episodesToSave = await MainActor.run { [weak self] in
            return self?.episodes ?? []
        }
        
        Task.detached(priority: .utility) { [weak self] in
            _ = FileStorage.shared.save(episodesToSave, to: "episodes.json")
            
            #if canImport(OSLog)
            self?.logger.info("💾 Saved \(episodesToSave.count) episodes to disk")
            #endif
        }
    }
    
    private func savePlayedEpisodeIDs() async {
        let idsToSave = await MainActor.run { [weak self] in
            return Array(self?.playedEpisodeIDs ?? [])
        }
        
        Task.detached(priority: .utility) { [weak self] in
            _ = FileStorage.shared.save(idsToSave, to: "playedEpisodeIDs.json")
            
            #if canImport(OSLog)
            self?.logger.info("💾 Saved \(idsToSave.count) played episode IDs")
            #endif
        }
    }
    
    private func saveCacheMetadata() async {
        let metadataToSave = await MainActor.run { [weak self] in
            return self?.cacheMetadata ?? CacheMetadata()
        }
        
        Task.detached(priority: .utility) { [weak self] in
            _ = FileStorage.shared.save(metadataToSave, to: "episodeCacheMetadata.json")
            
            #if canImport(OSLog)
            self?.logger.info("💾 Saved cache metadata")
            #endif
        }
    }
}

// MARK: - Episode Update Types

enum EpisodeUpdate {
    case markAsPlayed(UUID)
    case markAsUnplayed(UUID)
    case updatePlaybackPosition(UUID, TimeInterval)
}

// MARK: - Notification Names

extension Notification.Name {
    static let episodeRepositoryUpdated = Notification.Name("episodeRepositoryUpdated")
    static let episodeRepositoryError = Notification.Name("episodeRepositoryError")
} 