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
        var affectedIDs = Set<UUID>()
        for i in episodes.indices {
            if episodes[i].podcastID == podcastID {
                episodes[i].played = true
                affectedIDs.insert(episodes[i].id)
            }
        }
        saveEpisodes()
        if !affectedIDs.isEmpty {
            QueueViewModel.shared.markEpisodesAsPlayed(withIDs: affectedIDs, played: true)
        }
    }

    func markAllEpisodesAsUnplayed(for podcastID: UUID) {
        var affectedIDs = Set<UUID>()
        for i in episodes.indices {
            if episodes[i].podcastID == podcastID {
                episodes[i].played = false
                affectedIDs.insert(episodes[i].id)
            }
        }
        saveEpisodes()
        if !affectedIDs.isEmpty {
            QueueViewModel.shared.markEpisodesAsPlayed(withIDs: affectedIDs, played: false)
        }
    }
    
    // MARK: - Persistence
    
    private func saveEpisodes() {
        FileStorage.shared.saveAsync(episodes, to: "episodes.json") { _ in
            AppDataDocument.saveToICloudIfEnabled()
        }
    }
    
    private func loadEpisodes() {
        // Try to migrate from UserDefaults first, then load from file
        if let migratedEpisodes = FileStorage.shared.migrateFromUserDefaults([Episode].self, userDefaultsKey: episodesKey, filename: "episodes.json") {
            episodes = migratedEpisodes
        } else {
            FileStorage.shared.loadAsync([Episode].self, from: "episodes.json") { [weak self] saved in
                if let saved = saved {
                    self?.episodes = saved
                }
            }
        }
    }
    
    // MARK: - Episode Addition/Removal
    
    func addEpisodes(_ newEpisodes: [Episode]) {
        let existingIDs = Set(episodes.map { $0.id })
        
        // Create a dictionary of existing episodes by podcast+title combination
        var existingEpisodesByTitle: [String: Episode] = [:]
        for episode in episodes {
            if let podcastID = episode.podcastID {
                // Use podcastID instead of podcast title for more reliable identification
                let key = "\(podcastID.uuidString)_\(episode.title)"
                existingEpisodesByTitle[key] = episode
            }
        }
        
        var episodesToAdd: [Episode] = []
        
        for episode in newEpisodes {
            // Skip if we already have this episode by ID
            if existingIDs.contains(episode.id) {
                continue
            }
            
            // Skip if we already have an episode with the same title for this podcast
            if let podcastID = episode.podcastID {
                let key = "\(podcastID.uuidString)_\(episode.title)"
                if let existingEpisode = existingEpisodesByTitle[key] {
                    // Keep the one with the more recent published date, or first one if dates are equal
                    switch (episode.publishedDate, existingEpisode.publishedDate) {
                    case (let newDate?, let existingDate?):
                        if newDate > existingDate {
                            // Replace the existing episode with the newer one
                            if let index = episodes.firstIndex(where: { $0.id == existingEpisode.id }) {
                                episodes[index] = episode
                                existingEpisodesByTitle[key] = episode
                            }
                        }
                        // Otherwise keep existing
                    case (_, nil):
                        // New episode has date, existing doesn't - prefer new
                        if let index = episodes.firstIndex(where: { $0.id == existingEpisode.id }) {
                            episodes[index] = episode
                            existingEpisodesByTitle[key] = episode
                        }
                    default:
                        // Keep existing episode
                        break
                    }
                    continue
                }
            }
            
            // New episode - add it to the list to be added
            episodesToAdd.append(episode)
            
            // Also add to our tracking dictionary
            if let podcastID = episode.podcastID {
                let key = "\(podcastID.uuidString)_\(episode.title)"
                existingEpisodesByTitle[key] = episode
            }
        }
        
        episodes.append(contentsOf: episodesToAdd)
        
        // Sort episodes by publication date immediately
        sortEpisodesByDate()
        
        saveEpisodes()
    }
    
    func removeEpisodes(for podcastID: UUID) {
        episodes.removeAll { $0.podcastID == podcastID }
        saveEpisodes()
    }
    
    func clearAllEpisodes() {
        episodes.removeAll()
        saveEpisodes()
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