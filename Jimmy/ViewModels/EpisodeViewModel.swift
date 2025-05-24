import Foundation
import SwiftUI

class EpisodeViewModel: ObservableObject {
    static let shared = EpisodeViewModel()
    
    @Published var episodes: [Episode] = []
    private let episodesKey = "episodesKey"
    
    private init() {
        loadEpisodes()
    }
    
    // MARK: - Episode Management
    
    func updateEpisode(_ episode: Episode) {
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            episodes[index] = episode
            saveEpisodes()
            
            // Update episode in queue if it exists
            QueueViewModel.shared.updateEpisodeInQueue(episode)
        }
    }
    
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) {
        var updatedEpisode = episode
        updatedEpisode.played = played
        updateEpisode(updatedEpisode)
        
        // Show haptic feedback
        FeedbackManager.shared.markAsPlayed()
    }
    
    func updatePlaybackPosition(for episode: Episode, position: TimeInterval) {
        var updatedEpisode = episode
        updatedEpisode.playbackPosition = position
        updateEpisode(updatedEpisode)
    }
    
    func getEpisode(by id: UUID) -> Episode? {
        return episodes.first { $0.id == id }
    }
    
    func getEpisodes(for podcastID: UUID) -> [Episode] {
        return episodes.filter { $0.podcastID == podcastID }
    }
    
    // MARK: - Batch Operations
    
    func markAllEpisodesAsPlayed(for podcastID: UUID) {
        for i in episodes.indices {
            if episodes[i].podcastID == podcastID {
                episodes[i].played = true
            }
        }
        saveEpisodes()
    }
    
    func markAllEpisodesAsUnplayed(for podcastID: UUID) {
        for i in episodes.indices {
            if episodes[i].podcastID == podcastID {
                episodes[i].played = false
            }
        }
        saveEpisodes()
    }
    
    // MARK: - Persistence
    
    private func saveEpisodes() {
        if let data = try? JSONEncoder().encode(episodes) {
            UserDefaults.standard.set(data, forKey: episodesKey)
            AppDataDocument.saveToICloudIfEnabled()
        }
    }
    
    private func loadEpisodes() {
        if let data = UserDefaults.standard.data(forKey: episodesKey),
           let savedEpisodes = try? JSONDecoder().decode([Episode].self, from: data) {
            episodes = savedEpisodes
        }
    }
    
    // MARK: - Episode Addition/Removal
    
    func addEpisodes(_ newEpisodes: [Episode]) {
        let existingIDs = Set(episodes.map { $0.id })
        let episodesToAdd = newEpisodes.filter { !existingIDs.contains($0.id) }
        
        episodes.append(contentsOf: episodesToAdd)
        saveEpisodes()
    }
    
    func removeEpisodes(for podcastID: UUID) {
        episodes.removeAll { $0.podcastID == podcastID }
        saveEpisodes()
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
}

// MARK: - QueueViewModel Extension
extension QueueViewModel {
    func updateEpisodeInQueue(_ episode: Episode) {
        if let index = queue.firstIndex(where: { $0.id == episode.id }) {
            queue[index] = episode
            saveQueue()
        }
    }
} 