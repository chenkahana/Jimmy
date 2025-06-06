import Foundation
import UserNotifications

class QueueViewModel: ObservableObject {
    static let shared = QueueViewModel()
    @Published var queue: [Episode] = []
    @Published var loadingEpisodeID: UUID?
    private let queueKey = "queueKey"
    
    private init() {
        loadQueue()
        // Preload first few episodes for faster playback
        preloadUpcomingEpisodes()
    }
    
    // MARK: - Basic Queue Operations
    
    func addToQueue(_ episode: Episode) {
        // Prevent duplicate episodes in the queue
        guard !queue.contains(where: { $0.id == episode.id }) else { return }
        queue.append(episode)
        saveQueue()
        
        // Record this operation for undo
        ShakeUndoManager.shared.recordOperation(
            .episodeAddedToQueue(episode: episode),
            description: "Added \"\(episode.title)\" to queue"
        )
    }
    
    func addToTopOfQueue(_ episode: Episode) {
        // Remove existing instance to avoid duplicates
        if let existingIndex = queue.firstIndex(where: { $0.id == episode.id }) {
            queue.remove(at: existingIndex)
        }

        // If there's a currently playing episode (at position 0), insert at position 1
        // Otherwise, insert at position 0
        let insertIndex = (queue.isEmpty || AudioPlayerService.shared.currentEpisode == nil) ? 0 : 1
        queue.insert(episode, at: insertIndex)
        saveQueue()
        
        // Record this operation for undo
        ShakeUndoManager.shared.recordOperation(
            .episodeAddedToQueue(episode: episode),
            description: "Added \"\(episode.title)\" to top of queue"
        )
    }
    
    func removeFromQueue(at offsets: IndexSet) {
        // Record episodes being removed for undo (only record the first one for simplicity)
        if let firstIndex = offsets.first, firstIndex < queue.count {
            let episode = queue[firstIndex]
            ShakeUndoManager.shared.recordOperation(
                .episodeRemovedFromQueue(episode: episode, atIndex: firstIndex),
                description: "Removed \"\(episode.title)\" from queue"
            )
        }
        
        queue.remove(atOffsets: offsets)
        saveQueue()
    }
    
    func removeFromQueue(_ episode: Episode) {
        if let index = queue.firstIndex(where: { $0.id == episode.id }) {
            // Record this operation for undo
            ShakeUndoManager.shared.recordOperation(
                .episodeRemovedFromQueue(episode: episode, atIndex: index),
                description: "Removed \"\(episode.title)\" from queue"
            )
            
            queue.remove(at: index)
        }
        saveQueue()
    }
    
    func moveToEndOfQueue(_ episode: Episode) {
        guard let index = queue.firstIndex(where: { $0.id == episode.id }) else { return }
        let removedEpisode = queue.remove(at: index)
        queue.append(removedEpisode)
        saveQueue()
    }
    
    func moveToEndOfQueue(at index: Int) {
        guard index < queue.count else { return }
        let removedEpisode = queue.remove(at: index)
        queue.append(removedEpisode)
        saveQueue()
    }
    
    func moveQueue(from source: IndexSet, to destination: Int) {
        // Record the current queue state for undo
        let previousQueue = queue
        
        queue.move(fromOffsets: source, toOffset: destination)
        saveQueue()
        
        // Record this operation for undo
        ShakeUndoManager.shared.recordOperation(
            .queueReordered(previousQueue: previousQueue),
            description: "Reordered queue"
        )
    }
    
    // MARK: - Advanced Queue Logic
    
    /// Play the next episode in the queue (called when current episode ends)
    func playNextEpisode() {
        guard !queue.isEmpty else { return }
        
        // Remove the first episode (current episode that just finished)
        queue.removeFirst()
        saveQueue()
        
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

        // If there's currently a playing episode, move it to second position
        if let currentEpisode = audioPlayer.currentEpisode {
            // Only remove the current episode if it's at position 0
            if !queue.isEmpty && queue[0].id == currentEpisode.id {
                queue.removeFirst()
            }

            // Insert new episode at position 0
            queue.insert(episode, at: 0)

            // Insert previous episode at position 1
            queue.insert(currentEpisode, at: 1)
        } else {
            // No current episode, just add to front
            queue.insert(episode, at: 0)
        }

        // Start playing the new episode
        audioPlayer.loadEpisode(episode)
        audioPlayer.play()

        saveQueue()
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
        queue.removeFirst(episodeIndex)

        // Remove any remaining duplicates of this episode
        queue.removeAll { $0.id == episode.id }

        // Insert the selected episode at the top
        queue.insert(episode, at: 0)

        // Start playing it
        AudioPlayerService.shared.loadEpisode(episode)
        AudioPlayerService.shared.play()

        saveQueue()
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
        queue.removeFirst(index)

        // Remove any remaining duplicates of this episode
        queue.removeAll { $0.id == episode.id }

        // Insert the selected episode at the top
        queue.insert(episode, at: 0)

        // Start playing it
        AudioPlayerService.shared.loadEpisode(episode)
        AudioPlayerService.shared.play()

        saveQueue()
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

        // Ensure the current episode is at the front of the queue
        queue.insert(currentEpisode, at: 0)
        saveQueue()
    }
    
    // MARK: - Existing Functions (kept for compatibility)
    
    func removeEpisodes(withIDs ids: Set<UUID>) {
        queue.removeAll { ids.contains($0.id) }
        saveQueue()
    }
    
    func markEpisodesAsPlayed(withIDs ids: Set<UUID>, played: Bool = true) {
        for i in queue.indices {
            if ids.contains(queue[i].id) {
                queue[i].played = played
            }
        }
        saveQueue()
    }
    
    func autoAddNewEpisodesFromSubscribedPodcasts() {
        let podcasts = PodcastService.shared.loadPodcasts().filter { $0.autoAddToQueue }
        for podcast in podcasts {
            PodcastService.shared.fetchEpisodes(for: podcast) { [weak self] episodes in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let existingIDs = Set(self.queue.map { $0.id })
                    let newEpisodes = episodes.filter { !existingIDs.contains($0.id) }
                    for episode in newEpisodes {
                        self.addToQueue(episode)
                        if podcast.notificationsEnabled {
                            self.scheduleNotification(for: episode, podcast: podcast)
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
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(self.queue) {
                UserDefaults.standard.set(data, forKey: self.queueKey)
                AppDataDocument.saveToICloudIfEnabled()
            }
        }
        DispatchQueue.main.async {
            CarPlayManager.shared.reloadData()
        }
    }

    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let savedQueue = try? JSONDecoder().decode([Episode].self, from: data) {
            queue = savedQueue
        }
        CarPlayManager.shared.reloadData()
    }
    
    // MARK: - Loading State Management
    
    private func clearLoadingState() {
        loadingEpisodeID = nil
    }
    
    private func preloadUpcomingEpisodes() {
        // Preload the first 3 episodes in the queue for faster loading
        AudioPlayerService.shared.preloadEpisodes(Array(queue.prefix(3)))
    }
}
