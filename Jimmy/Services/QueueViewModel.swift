import Foundation
import SwiftUI

/// Temporary QueueViewModel stub for build compatibility
/// This will be replaced by CleanQueueViewModel in the clean architecture
@MainActor
class QueueViewModel: ObservableObject {
    static let shared = QueueViewModel()
    
    @Published var queue: [Episode] = []
    @Published var loadingEpisodeID: UUID?
    
    private init() {}
    
    func addToQueue(_ episode: Episode) {
        queue.append(episode)
    }
    
    func addToTopOfQueue(_ episode: Episode) {
        queue.insert(episode, at: 0)
    }
    
    func playEpisodeFromLibrary(_ episode: Episode) {
        // Delegate to audio player service
        AudioPlayerService.shared.loadEpisode(episode)
        AudioPlayerService.shared.play()
    }
    
    func playEpisodeFromQueue(_ episode: Episode) {
        // Delegate to audio player service
        AudioPlayerService.shared.loadEpisode(episode)
        AudioPlayerService.shared.play()
    }
    
    func playEpisodeFromQueue(at index: Int) {
        guard index < queue.count else { return }
        let episode = queue[index]
        AudioPlayerService.shared.loadEpisode(episode)
        AudioPlayerService.shared.play()
    }
    
    func playNextEpisode() {
        guard !queue.isEmpty else { return }
        let nextEpisode = queue.removeFirst()
        AudioPlayerService.shared.loadEpisode(nextEpisode)
        AudioPlayerService.shared.play()
    }
    
    func removeFromQueue(_ episode: Episode) {
        queue.removeAll { $0.id == episode.id }
    }
    
    func removeFromQueue(at offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
        saveQueue()
    }
    
    func moveToEndOfQueue(at index: Int) {
        guard index < queue.count else { return }
        let episode = queue.remove(at: index)
        queue.append(episode)
        saveQueue()
    }
    
    func syncCurrentEpisodeWithQueue() {
        // Stub implementation
        print("🔄 Syncing current episode with queue")
    }
    
    func saveQueue() {
        // Stub implementation - save queue to UserDefaults or file
        print("📝 Queue saved with \(queue.count) episodes")
    }
    
    func updateEpisodeIDs() {
        // Stub implementation - update internal episode ID tracking
        print("📝 Episode IDs updated for \(queue.count) episodes")
    }
    
    func moveQueue(from source: IndexSet, to destination: Int) {
        // Stub implementation - move episodes in queue
        queue.move(fromOffsets: source, toOffset: destination)
        saveQueue()
    }
} 