import Foundation
import UserNotifications

class QueueViewModel: ObservableObject {
    static let shared = QueueViewModel()
    @Published var queue: [Episode] = []
    @Published var loadingEpisodeID: UUID?
    private let queueKey = "queueKey"
    
    // Fast duplicate checking with a Set
    private var queueEpisodeIDs: Set<UUID> = []
    
    private init() {
        // Load queue asynchronously and don't preload episodes during init
        // This prevents blocking the UI during app startup
        loadQueue { [weak self] in
            // Initialization complete - could trigger other operations here if needed
            self?.scheduleCarPlayReload()
        }
    }
    
    // MARK: - Basic Queue Operations
    
    func addToQueue(_ episode: Episode) {
        // Fast duplicate check using Set - O(1) instead of O(n)
        guard !queueEpisodeIDs.contains(episode.id) else { return }
        
        // Add to both queue and ID set
        queue.append(episode)
        queueEpisodeIDs.insert(episode.id)
        
        // Debounce save operations to avoid excessive saves when adding multiple episodes
        debouncedSaveQueue()
        
        // Record undo operation asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .utility).async {
            ShakeUndoManager.shared.recordOperation(
                .episodeAddedToQueue(episode: episode),
                description: "Added \"\(episode.title)\" to queue"
            )
        }
    }
    
    /// Add multiple episodes to queue efficiently in batch
    func addEpisodesToQueue(_ episodes: [Episode]) {
        var addedEpisodes: [Episode] = []
        
        for episode in episodes {
            // Fast duplicate check using Set - O(1) instead of O(n)
            guard !queueEpisodeIDs.contains(episode.id) else { continue }
            queue.append(episode)
            queueEpisodeIDs.insert(episode.id)
            addedEpisodes.append(episode)
        }
        
        guard !addedEpisodes.isEmpty else { return }
        
        // Save once after all episodes are added
        saveQueue()
        
        // Record batch operations asynchronously
        DispatchQueue.global(qos: .utility).async {
            for episode in addedEpisodes {
                ShakeUndoManager.shared.recordOperation(
                    .episodeAddedToQueue(episode: episode),
                    description: "Added \"\(episode.title)\" to queue"
                )
            }
        }
    }
    
    func addToTopOfQueue(_ episode: Episode) {
        // Remove existing instance to avoid duplicates
        if queueEpisodeIDs.contains(episode.id) {
            if let existingIndex = queue.firstIndex(where: { $0.id == episode.id }) {
                queue.remove(at: existingIndex)
            }
            queueEpisodeIDs.remove(episode.id)
        }

        // If there's a currently playing episode (at position 0), insert at position 1
        // Otherwise, insert at position 0
        let insertIndex = (queue.isEmpty || AudioPlayerService.shared.currentEpisode == nil) ? 0 : 1
        queue.insert(episode, at: insertIndex)
        queueEpisodeIDs.insert(episode.id)
        
        // Debounce save operations
        debouncedSaveQueue()
        
        // Record undo operation asynchronously
        DispatchQueue.global(qos: .utility).async {
            ShakeUndoManager.shared.recordOperation(
                .episodeAddedToQueue(episode: episode),
                description: "Added \"\(episode.title)\" to top of queue"
            )
        }
    }
    
    func removeFromQueue(at offsets: IndexSet) {
        // Get episodes being removed
        let episodesToRemove = offsets.compactMap { index in
            index < queue.count ? queue[index] : nil
        }
        
        // Remove from queue and ID set
        queue.remove(atOffsets: offsets)
        for episode in episodesToRemove {
            queueEpisodeIDs.remove(episode.id)
        }
        
        saveQueue()
        
        // Record undo operations asynchronously
        if let firstEpisode = episodesToRemove.first, let firstIndex = offsets.first {
            DispatchQueue.global(qos: .utility).async {
                ShakeUndoManager.shared.recordOperation(
                    .episodeRemovedFromQueue(episode: firstEpisode, atIndex: firstIndex),
                    description: "Removed \"\(firstEpisode.title)\" from queue"
                )
            }
        }
    }
    
    func removeFromQueue(_ episode: Episode) {
        if let index = queue.firstIndex(where: { $0.id == episode.id }) {
            queue.remove(at: index)
            queueEpisodeIDs.remove(episode.id)
            saveQueue()
            
            // Record undo operation asynchronously
            DispatchQueue.global(qos: .utility).async {
                ShakeUndoManager.shared.recordOperation(
                    .episodeRemovedFromQueue(episode: episode, atIndex: index),
                    description: "Removed \"\(episode.title)\" from queue"
                )
            }
        }
    }
    
    func moveToEndOfQueue(_ episode: Episode) {
        guard let index = queue.firstIndex(where: { $0.id == episode.id }) else { return }
        let removedEpisode = queue.remove(at: index)
        queue.append(removedEpisode)
        // No need to update queueEpisodeIDs since episode is just moved, not added/removed
        saveQueue()
    }
    
    func moveToEndOfQueue(at index: Int) {
        guard index < queue.count else { return }
        let removedEpisode = queue.remove(at: index)
        queue.append(removedEpisode)
        // No need to update queueEpisodeIDs since episode is just moved, not added/removed
        saveQueue()
    }
    
    func moveQueue(from source: IndexSet, to destination: Int) {
        // Record the current queue state for undo asynchronously
        let previousQueue = queue
        
        queue.move(fromOffsets: source, toOffset: destination)
        // No need to update queueEpisodeIDs since episodes are just reordered, not added/removed
        saveQueue()
        
        // Record undo operation asynchronously
        DispatchQueue.global(qos: .utility).async {
            ShakeUndoManager.shared.recordOperation(
                .queueReordered(previousQueue: previousQueue),
                description: "Reordered queue"
            )
        }
    }
    
    // MARK: - Advanced Queue Logic
    
    /// Play the next episode in the queue (called when current episode ends)
    func playNextEpisode() {
        guard !queue.isEmpty else { return }
        
        // Remove the first episode (current episode that just finished)
        let removedEpisode = queue.removeFirst()
        queueEpisodeIDs.remove(removedEpisode.id)
        debouncedSaveQueue()
        
        // Play the next episode if available
        if !queue.isEmpty {
            let nextEpisode = queue[0]
            AudioPlayerService.shared.loadEpisode(nextEpisode)
            AudioPlayerService.shared.play()
        } else {
            // No more episodes in queue, stop playback
            AudioPlayerService.shared.stop()
        }
    }
    
    /// Play an episode from the library - moves current playing episode to second place
    func playEpisodeFromLibrary(_ episode: Episode) {
        let audioPlayer = AudioPlayerService.shared

        // Set loading state immediately for UI feedback
        loadingEpisodeID = episode.id

        // Remove any existing instance of this episode to keep the queue unique
        queue.removeAll { $0.id == episode.id }
        queueEpisodeIDs.remove(episode.id)

        // If there's currently a playing episode, move it to second position
        if let currentEpisode = audioPlayer.currentEpisode {
            // Only remove the current episode if it's at position 0
            if !queue.isEmpty && queue[0].id == currentEpisode.id {
                let removedEpisode = queue.removeFirst()
                queueEpisodeIDs.remove(removedEpisode.id)
            }

            // Insert new episode at position 0
            queue.insert(episode, at: 0)
            queueEpisodeIDs.insert(episode.id)

            // Insert previous episode at position 1
            queue.insert(currentEpisode, at: 1)
            queueEpisodeIDs.insert(currentEpisode.id)
        } else {
            // No current episode, just add to front
            queue.insert(episode, at: 0)
            queueEpisodeIDs.insert(episode.id)
        }

        // Start playing the new episode
        audioPlayer.loadEpisode(episode)
        audioPlayer.play()

        debouncedSaveQueue()
        preloadUpcomingEpisodes()
        
        // Clear loading state after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.clearLoadingState()
        }
    }
    
    /// Play an episode from the queue - removes all episodes above it
    func playEpisodeFromQueue(_ episode: Episode) {
        guard let episodeIndex = queue.firstIndex(where: { $0.id == episode.id }) else { return }

        // Set loading state immediately for UI feedback
        loadingEpisodeID = episode.id

        // If it's already at position 0, just play it
        if episodeIndex == 0 {
            AudioPlayerService.shared.loadEpisode(episode)
            AudioPlayerService.shared.play()
            clearLoadingState()
            return
        }

        // Remove all episodes above the selected episode (0 to episodeIndex-1)
        let removedEpisodes = Array(queue[0..<episodeIndex])
        queue.removeFirst(episodeIndex)
        for removedEpisode in removedEpisodes {
            queueEpisodeIDs.remove(removedEpisode.id)
        }

        // Remove any remaining duplicates of this episode
        queue.removeAll { $0.id == episode.id }
        queueEpisodeIDs.remove(episode.id)

        // Insert the selected episode at the top
        queue.insert(episode, at: 0)
        queueEpisodeIDs.insert(episode.id)

        // Start playing it
        AudioPlayerService.shared.loadEpisode(episode)
        AudioPlayerService.shared.play()

        debouncedSaveQueue()
        preloadUpcomingEpisodes()
        
        // Clear loading state after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.clearLoadingState()
        }
    }
    
    /// Play an episode from the queue using index - removes all episodes above it
    func playEpisodeFromQueue(at index: Int) {
        guard index < queue.count else { return }
        let episode = queue[index]

        // Set loading state immediately for UI feedback
        loadingEpisodeID = episode.id

        // If it's already at position 0, just play it
        if index == 0 {
            AudioPlayerService.shared.loadEpisode(episode)
            AudioPlayerService.shared.play()
            clearLoadingState()
            return
        }

        // Remove all episodes above the selected episode (0 to index-1)
        let removedEpisodes = Array(queue[0..<index])
        queue.removeFirst(index)
        for removedEpisode in removedEpisodes {
            queueEpisodeIDs.remove(removedEpisode.id)
        }

        // Remove any remaining duplicates of this episode
        queue.removeAll { $0.id == episode.id }
        queueEpisodeIDs.remove(episode.id)

        // Insert the selected episode at the top
        queue.insert(episode, at: 0)
        queueEpisodeIDs.insert(episode.id)

        // Start playing it
        AudioPlayerService.shared.loadEpisode(episode)
        AudioPlayerService.shared.play()

        debouncedSaveQueue()
        preloadUpcomingEpisodes()
        
        // Clear loading state after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.clearLoadingState()
        }
    }
    
    /// Ensure the currently playing episode is at the top of the queue
    func syncCurrentEpisodeWithQueue() {
        guard let currentEpisode = AudioPlayerService.shared.currentEpisode else { return }

        // Remove any existing copies of the current episode
        queue.removeAll { $0.id == currentEpisode.id }
        queueEpisodeIDs.remove(currentEpisode.id)

        // Ensure the current episode is at the front of the queue
        queue.insert(currentEpisode, at: 0)
        queueEpisodeIDs.insert(currentEpisode.id)
        debouncedSaveQueue()
    }
    
    // MARK: - Existing Functions (kept for compatibility)
    
    func removeEpisodes(withIDs ids: Set<UUID>) {
        queue.removeAll { ids.contains($0.id) }
        // Remove from ID set as well
        queueEpisodeIDs.subtract(ids)
        debouncedSaveQueue()
    }
    
    func markEpisodesAsPlayed(withIDs ids: Set<UUID>, played: Bool = true) {
        for i in queue.indices {
            if ids.contains(queue[i].id) {
                queue[i].played = played
            }
        }
        debouncedSaveQueue()
    }
    
    /// Helper method to verify queue consistency (for debugging)
    private func verifyQueueConsistency() {
        #if DEBUG
        let actualIDs = Set(queue.map { $0.id })
        if actualIDs != queueEpisodeIDs {
            print("⚠️ Queue consistency error: ID set mismatch")
            queueEpisodeIDs = actualIDs // Fix it
        }
        #endif
    }
    
    func autoAddNewEpisodesFromSubscribedPodcasts() {
        let podcasts = PodcastService.shared.loadPodcasts().filter { $0.autoAddToQueue }
        for podcast in podcasts {
            PodcastService.shared.fetchEpisodes(for: podcast) { [weak self] episodes in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let existingIDs = Set(self.queue.map { $0.id })
                    let newEpisodes = episodes.filter { !existingIDs.contains($0.id) }
                    
                    // Use batch add to avoid multiple save operations
                    if !newEpisodes.isEmpty {
                        self.addEpisodesToQueue(newEpisodes)
                        
                        // Schedule notifications asynchronously
                        if podcast.notificationsEnabled {
                            DispatchQueue.global(qos: .utility).async { [weak self] in
                                for episode in newEpisodes {
                                    self?.scheduleNotification(for: episode, podcast: podcast)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func scheduleNotification(for episode: Episode, podcast: Podcast) {
        let content = UNMutableNotificationContent()
        content.title = "New Episode: \(podcast.title)"
        content.body = episode.title
        content.sound = .default
        let request = UNNotificationRequest(identifier: episode.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    func saveQueue() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if let data = try? JSONEncoder().encode(self.queue) {
                UserDefaults.standard.set(data, forKey: self.queueKey)
                AppDataDocument.saveToICloudIfEnabled()
            }
            
            // Move CarPlay reloading to main thread but debounce it
            DispatchQueue.main.async {
                self.scheduleCarPlayReload()
            }
        }
    }
    
    private var carPlayReloadWorkItem: DispatchWorkItem?
    
    private func scheduleCarPlayReload() {
        // Cancel any pending reload
        carPlayReloadWorkItem?.cancel()
        
        // Schedule a new reload with debouncing
        carPlayReloadWorkItem = DispatchWorkItem { [weak self] in
            CarPlayManager.shared.reloadData()
        }
        
        if let workItem = carPlayReloadWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        }
    }

    private func loadQueue(completion: (() -> Void)? = nil) {
        // Load queue asynchronously to never block the UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { 
                completion?()
                return 
            }
            
            var loadedQueue: [Episode] = []
            
            if let data = UserDefaults.standard.data(forKey: self.queueKey),
               let savedQueue = try? JSONDecoder().decode([Episode].self, from: data) {
                loadedQueue = savedQueue
            }
            
            // Update the queue on main thread
            DispatchQueue.main.async {
                self.queue = loadedQueue
                // Sync the episode IDs set for fast duplicate checking
                self.queueEpisodeIDs = Set(loadedQueue.map { $0.id })
                completion?()
            }
        }
    }
    
    // MARK: - Loading State Management
    
    private func clearLoadingState() {
        loadingEpisodeID = nil
    }
    
    private func preloadUpcomingEpisodes() {
        // Preload episodes asynchronously to avoid blocking the UI
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // Preload the first 3 episodes in the queue for faster loading
            AudioPlayerService.shared.preloadEpisodes(Array(self.queue.prefix(3)))
        }
    }
    
    private var saveQueueWorkItem: DispatchWorkItem?
    
    internal func debouncedSaveQueue() {
        // Cancel any pending save
        saveQueueWorkItem?.cancel()
        
        // Schedule a new save with debouncing
        saveQueueWorkItem = DispatchWorkItem { [weak self] in
            self?.saveQueue()
        }
        
        if let workItem = saveQueueWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        }
    }
}
