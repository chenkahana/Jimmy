import Foundation
import SwiftUI

class EpisodeViewModel: ObservableObject {
    static let shared = EpisodeViewModel()
    
    @Published var episodes: [Episode] = []
    @Published var hasAttemptedLoad: Bool = false
    private let episodesKey = "episodesKey"
    
    // Persisted list of played episode IDs
    private var playedEpisodeIDs: Set<UUID> = []
    private let playedIDsFilename = "playedEpisodes.json"
    
    // PERFORMANCE FIX: Add background queue for heavy operations
    private let dataProcessingQueue = DispatchQueue(label: "episode-data-processing", qos: .userInitiated, attributes: .concurrent)
    private let persistenceQueue = DispatchQueue(label: "episode-persistence", qos: .utility)
    
    // Debouncing for episode saves
    private var saveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 2.0
    
    // PERFORMANCE FIX: Add operation tracking to prevent concurrent modifications
    private var isLoading = false
    private var pendingUpdates: [Episode] = []
    private let updateQueue = DispatchQueue(label: "episode-updates", qos: .userInitiated)
    
    private init() {
        // Load data synchronously during initialization to avoid background thread publishing warnings
        // These FileStorage.load calls are fast enough for synchronous execution
        if let ids: [UUID] = FileStorage.shared.load([UUID].self, from: self.playedIDsFilename) {
            self.playedEpisodeIDs = Set(ids)
        }

        if var loadedEpisodes: [Episode] = FileStorage.shared.load([Episode].self, from: "episodes.json") {
            // Apply played status to the loaded episodes
            for i in loadedEpisodes.indices {
                if self.playedEpisodeIDs.contains(loadedEpisodes[i].id) {
                    loadedEpisodes[i].played = true
                }
            }
            self.episodes = loadedEpisodes
            print("⚡ EpisodeViewModel: Loaded \(loadedEpisodes.count) cached episodes instantly")
        } else {
            // No cached episodes - start with empty array for immediate UI display
            self.episodes = []
            print("📱 Starting with empty episodes - will load fresh data")
        }

        self.hasAttemptedLoad = true
        print("📊 EpisodeViewModel: Episodes array now has \(self.episodes.count) episodes")

        // Schedule recovery check for later (not during init)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkAndRecoverIfNeeded()
        }
    }
    
    // MARK: - Synchronous Helper for Startup
    
    private func applyPlayedIDsSync() {
        // Apply played IDs immediately for startup performance
        episodes = episodes.map { ep in
            var e = ep
            e.played = playedEpisodeIDs.contains(ep.id)
            return e
        }
    }
    
    // MARK: - Episode Management
    
    /// Check if an episode ID is marked as played
    func isEpisodePlayed(_ episodeID: UUID) -> Bool {
        return playedEpisodeIDs.contains(episodeID)
    }
    
    func updateEpisode(_ episode: Episode) {
        // PERFORMANCE FIX: Use update queue to prevent blocking main thread
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Update UI state on main actor
            Task { @MainActor in
                if let index = self.episodes.firstIndex(where: { $0.id == episode.id }) {
                    self.episodes[index] = episode
                }
                
                // Save episodes on background thread to avoid blocking UI
                Task.detached(priority: .utility) { [weak self] in
                    self?.saveEpisodes()
                }
            }
        }
    }
    
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) {
        // PERFORMANCE FIX: Handle played state updates asynchronously
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Update played IDs file
            if played {
                self.playedEpisodeIDs.insert(episode.id)
            } else {
                self.playedEpisodeIDs.remove(episode.id)
            }
            
            // Save played IDs on background thread
            Task.detached(priority: .utility) { [weak self] in
                self?.savePlayedIDs()
            }
            
            // Update episode in memory and persistence
            var updatedEpisode = episode
            updatedEpisode.played = played
            self.updateEpisode(updatedEpisode)
            
            // Show haptic feedback on main thread
            Task { @MainActor in
                FeedbackManager.shared.markAsPlayed()
            }
        }
    }
    
    func updatePlaybackPosition(for episode: Episode, position: TimeInterval) {
        // PERFORMANCE FIX: Batch position updates to prevent excessive saves
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            var updatedEpisode = episode
            updatedEpisode.playbackPosition = position
            
            Task { @MainActor in
                if let index = self.episodes.firstIndex(where: { $0.id == episode.id }) {
                    self.episodes[index] = updatedEpisode
                }
                
                // Debounce saves for position updates
                self.debouncedSave()
            }
        }
    }
    
    func updateEpisodeDuration(_ episode: Episode, duration: TimeInterval) {
        updateQueue.async { [weak self] in
            var updatedEpisode = episode
            updatedEpisode.duration = duration
            self?.updateEpisode(updatedEpisode)
        }
    }
    
    func getEpisode(by id: UUID) -> Episode? {
        return episodes.first { $0.id == id }
    }
    
    func getEpisodes(for podcastID: UUID) -> [Episode] {
        return episodes.filter { $0.podcastID == podcastID }
    }
    
    // MARK: - Batch Operations
    
    func markAllEpisodesAsPlayed(for podcastID: UUID) {
        // PERFORMANCE FIX: Handle batch operations on background queue
        dataProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            var affectedIDs = Set<UUID>()
            var updatedEpisodes: [Episode] = []
            
            for episode in self.episodes {
                if episode.podcastID == podcastID {
                    var updatedEpisode = episode
                    updatedEpisode.played = true
                    updatedEpisodes.append(updatedEpisode)
                    affectedIDs.insert(episode.id)
                    self.playedEpisodeIDs.insert(episode.id)
                }
            }
            
            // Update UI on main thread
            Task { @MainActor in
                for updatedEpisode in updatedEpisodes {
                    if let index = self.episodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
                        self.episodes[index] = updatedEpisode
                    }
                }
            }
            
            // Save on background thread
            self.persistenceQueue.async {
                self.saveEpisodes()
                self.savePlayedIDs()
            }
            
            if !affectedIDs.isEmpty {
                QueueViewModel.shared.markEpisodesAsPlayed(withIDs: affectedIDs, played: true)
            }
        }
    }

    func markAllEpisodesAsUnplayed(for podcastID: UUID) {
        // PERFORMANCE FIX: Handle batch operations on background queue
        dataProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            var affectedIDs = Set<UUID>()
            var updatedEpisodes: [Episode] = []
            
            for episode in self.episodes {
                if episode.podcastID == podcastID {
                    var updatedEpisode = episode
                    updatedEpisode.played = false
                    updatedEpisodes.append(updatedEpisode)
                    affectedIDs.insert(episode.id)
                    self.playedEpisodeIDs.remove(episode.id)
                }
            }
            
            // Update UI on main thread
            Task { @MainActor in
                for updatedEpisode in updatedEpisodes {
                    if let index = self.episodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
                        self.episodes[index] = updatedEpisode
                    }
                }
            }
            
            // Save on background thread
            self.persistenceQueue.async {
                self.saveEpisodes()
                self.savePlayedIDs()
            }
            
            if !affectedIDs.isEmpty {
                QueueViewModel.shared.markEpisodesAsPlayed(withIDs: affectedIDs, played: false)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveEpisodes() {
        _ = FileStorage.shared.save(episodes, to: "episodes.json")
        AppDataDocument.saveToICloudIfEnabled()
    }
    
    private func debouncedSave() {
        // Cancel any pending save work item
        saveWorkItem?.cancel()
        
        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistenceQueue.async {
                self?.saveEpisodes()
            }
        }
        
        // Schedule it after the debounce interval
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(saveDebounceInterval * 1_000_000_000))
            workItem.perform()
        }
        
        // Store the new work item
        saveWorkItem = workItem
    }
    
    /// Immediately saves any pending changes. Call this when the app is about to be suspended.
    func saveImmediately() {
        saveWorkItem?.cancel()
        persistenceQueue.async { [weak self] in
            self?.saveEpisodes()
        }
    }
    
    private func loadEpisodes() async {
        // PERFORMANCE FIX: Prevent concurrent loading
        await MainActor.run {
            guard !isLoading else { return }
            isLoading = true
        }
        
        // Try to migrate from UserDefaults first, then load from file
        if let migratedEpisodes = FileStorage.shared.migrateFromUserDefaults([Episode].self, userDefaultsKey: episodesKey, filename: "episodes.json") {
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.episodes = migratedEpisodes
                self.applyPlayedIDs()
                self.isLoading = false
            }
        } else {
            await withCheckedContinuation { continuation in
                FileStorage.shared.loadAsync([Episode].self, from: "episodes.json") { [weak self] saved in
                    Task { @MainActor in
                        guard let self = self else { 
                            continuation.resume()
                            return 
                        }
                        if let saved = saved {
                            self.episodes = saved
                            self.applyPlayedIDs()
                        } else {
                            self.attemptAutomaticRecovery()
                        }
                        self.isLoading = false
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    private func attemptAutomaticRecovery() {
        // Ensure this runs on main thread since it might update @Published properties
        Task { @MainActor in
            // Check if we have any podcasts but no episodes - this suggests corrupted episode data
            let podcasts = PodcastService.shared.loadPodcasts()
            
            if !podcasts.isEmpty {
                // CRITICAL FIX: Don't trigger forceUpdate during recovery as it can interfere with navigation
                // Instead, just clear the corrupted file and let the natural update cycle handle it
                DispatchQueue.global(qos: .utility).async {
                    _ = FileStorage.shared.delete("episodes.json")
                    print("🔧 EpisodeViewModel: Cleared corrupted episodes.json file, letting natural update cycle handle recovery")
                }
            }
        }
    }
    
    // MARK: - Played Episodes Persistence
    private func loadPlayedIDs() {
        if let ids: [UUID] = FileStorage.shared.load([UUID].self, from: playedIDsFilename) {
            playedEpisodeIDs = Set(ids)
        }
    }
    
    private func savePlayedIDs() {
        let idsArray = Array(playedEpisodeIDs)
        _ = FileStorage.shared.save(idsArray, to: playedIDsFilename)
    }
    
    private func applyPlayedIDs() {
        // PERFORMANCE FIX: Apply played IDs on background thread for large datasets
        dataProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let updatedEpisodes = self.episodes.map { ep in
                var e = ep
                e.played = self.playedEpisodeIDs.contains(ep.id)
                return e
            }
            
            Task { @MainActor in
                self.episodes = updatedEpisodes
            }
        }
    }
    
    // MARK: - Episode Addition/Removal
    
    func addEpisodes(_ newEpisodes: [Episode]) {
        // PERFORMANCE FIX: Handle large episode additions on background thread
        guard !newEpisodes.isEmpty else { return }
        
        dataProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let existingIDs = Set(self.episodes.map { $0.id })
            
            // Create a dictionary of existing episodes by podcast+title combination
            var existingEpisodesByTitle: [String: Episode] = [:]
            for episode in self.episodes {
                if let podcastID = episode.podcastID {
                    // Use podcastID instead of podcast title for more reliable identification
                    let key = "\(podcastID.uuidString)_\(episode.title)"
                    existingEpisodesByTitle[key] = episode
                }
            }
            
            var episodesToAdd: [Episode] = []
            var episodesToUpdate: [Episode] = []
            
            for newEpisode in newEpisodes {
                // Skip if episode ID already exists
                if existingIDs.contains(newEpisode.id) {
                    continue
                }
                
                // Check for duplicate by podcast + title combination
                if let podcastID = newEpisode.podcastID {
                    let key = "\(podcastID.uuidString)_\(newEpisode.title)"
                    
                    if let existingEpisode = existingEpisodesByTitle[key] {
                        // Episode with same title and podcast exists - update if new one has more data
                        if newEpisode.audioURL != nil && existingEpisode.audioURL == nil {
                            // New episode has audio URL but existing doesn't - update
                            var updatedEpisode = existingEpisode
                            updatedEpisode.audioURL = newEpisode.audioURL
                            updatedEpisode.duration = newEpisode.duration
                            updatedEpisode.description = newEpisode.description ?? updatedEpisode.description
                            episodesToUpdate.append(updatedEpisode)
                        }
                        continue
                    }
                }
                
                // Apply played status if it exists
                var episodeToAdd = newEpisode
                if self.playedEpisodeIDs.contains(newEpisode.id) {
                    episodeToAdd.played = true
                }
                
                episodesToAdd.append(episodeToAdd)
            }
            
            // Update UI on main thread
            Task { @MainActor in
                // Add new episodes
                self.episodes.append(contentsOf: episodesToAdd)
                
                // Update existing episodes
                for updatedEpisode in episodesToUpdate {
                    if let index = self.episodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
                        self.episodes[index] = updatedEpisode
                    }
                }
                
                // Sort episodes by published date (most recent first) efficiently
                self.episodes.sort { episode1, episode2 in
                    switch (episode1.publishedDate, episode2.publishedDate) {
                    case (let date1?, let date2?):
                        return date1 > date2
                    case (nil, _?):
                        return false
                    case (_?, nil):
                        return true
                    case (nil, nil):
                        return episode1.title.localizedCaseInsensitiveCompare(episode2.title) == .orderedAscending
                    }
                }
            }
            
            // Save on background thread
            if !episodesToAdd.isEmpty || !episodesToUpdate.isEmpty {
                self.persistenceQueue.async {
                    self.saveEpisodes()
                }
                
                print("📥 EpisodeViewModel: Added \(episodesToAdd.count) new episodes, updated \(episodesToUpdate.count) existing episodes")
                print("📊 EpisodeViewModel: Episodes array now has \(self.episodes.count) episodes")
            }
        }
    }

    func removeEpisodes(for podcastID: UUID) {
        Task { @MainActor in
            self.episodes.removeAll { $0.podcastID == podcastID }
            
            // Save episodes on background thread to avoid blocking UI
            Task.detached(priority: .utility) { [weak self] in
                await self?.saveEpisodes()
            }
        }
    }

    func clearAllEpisodes() {
        Task { @MainActor in
            self.episodes.removeAll()
            
            // Save episodes on background thread to avoid blocking UI
            Task.detached(priority: .utility) { [weak self] in
                await self?.saveEpisodes()
            }
        }
    }
    
    func clearPlayedIDs() {
        playedEpisodeIDs.removeAll()
        savePlayedIDs()
    }
    
    /// Force reload episodes from storage - useful for recovery
    func forceReloadEpisodes() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loadEpisodes()
        }
    }
    
    /// Manually trigger episode recovery - clears corrupted data and fetches fresh episodes
    func triggerRecovery() {
        Task { @MainActor in
            self.episodes.removeAll()
            self.attemptAutomaticRecovery()
        }
    }
    
    /// Check if recovery is needed and trigger it automatically
    private func checkAndRecoverIfNeeded() {
        Task { @MainActor in
            // CRITICAL FIX: Never trigger automatic recovery to prevent episodes from disappearing
            // The episodes array can be temporarily empty during navigation, tab switching, or playback
            // Recovery should only be triggered manually by the user or in extreme circumstances
            
            // DISABLED: Automatic recovery is too aggressive and causes episodes to disappear
            // Only log the situation for debugging
            if self.episodes.isEmpty {
                let podcasts = PodcastService.shared.loadPodcasts()
                if !podcasts.isEmpty {
                    print("⚠️ EpisodeViewModel: Episodes empty but podcasts exist. NOT triggering automatic recovery to prevent data loss.")
                }
            }
        }
    }
    
    // MARK: - Sorting
    
    private func sortEpisodesByDate() {
        episodes.sort { episode1, episode2 in
            switch (episode1.publishedDate, episode2.publishedDate) {
            case (let date1?, let date2?):
                return date1 > date2 // Most recent first
            case (nil, _?):
                return false // Episodes without dates go to the end
            case (_?, nil):
                return true // Episodes with dates come before those without
            case (nil, nil):
                return episode1.title.localizedCaseInsensitiveCompare(episode2.title) == .orderedAscending // Alphabetical fallback
            }
        }
    }
    
    // MARK: - Public sorting method for manual refresh
    func sortAllEpisodes() {
        sortEpisodesByDate()
    }
    
    // MARK: - Statistics
    
    func getPlayedEpisodesCount(for podcastID: UUID) -> Int {
        return episodes.filter { $0.podcastID == podcastID && $0.played }.count
    }
    
    func getTotalEpisodesCount(for podcastID: UUID) -> Int {
        return episodes.filter { $0.podcastID == podcastID }.count
    }
    
    func getInProgressEpisodes(for podcastID: UUID) -> [Episode] {
        return episodes.filter { 
            $0.podcastID == podcastID && 
            $0.playbackPosition > 0 && 
            !$0.played 
        }
    }
    
    // MARK: - Episode Lookup
    
    func findEpisode(by id: String) -> Episode? {
        return episodes.first { $0.id.uuidString == id }
    }
} 