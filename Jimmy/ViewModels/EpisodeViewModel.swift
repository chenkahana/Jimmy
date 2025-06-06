import Foundation
import SwiftUI

class EpisodeViewModel: ObservableObject {
    static let shared = EpisodeViewModel()
    
    @Published var episodes: [Episode] = []
    private let episodesKey = "episodesKey"
    
    // Persisted list of played episode IDs
    private var playedEpisodeIDs: Set<UUID> = []
    private let playedIDsFilename = "playedEpisodes.json"
    
    private init() {
        loadPlayedIDs()
        loadEpisodes()
    }
    
    // MARK: - Episode Management
    
    /// Check if an episode ID is marked as played
    func isEpisodePlayed(_ episodeID: UUID) -> Bool {
        return playedEpisodeIDs.contains(episodeID)
    }
    
    func updateEpisode(_ episode: Episode) {
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            episodes[index] = episode
            saveEpisodes()
            
            // Update episode in queue if it exists
            QueueViewModel.shared.updateEpisodeInQueue(episode)
        }
    }
    
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) {
        // Update played IDs file
        if played {
            playedEpisodeIDs.insert(episode.id)
        } else {
            playedEpisodeIDs.remove(episode.id)
        }
        savePlayedIDs()
        
        // Update episode in memory and persistence
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
        _ = FileStorage.shared.save(episodes, to: "episodes.json")
        AppDataDocument.saveToICloudIfEnabled()
    }
    
    private func loadEpisodes() {
        // Try to migrate from UserDefaults first, then load from file
        if let migratedEpisodes = FileStorage.shared.migrateFromUserDefaults([Episode].self, userDefaultsKey: episodesKey, filename: "episodes.json") {
            episodes = migratedEpisodes
            applyPlayedIDs()
        } else {
            FileStorage.shared.loadAsync([Episode].self, from: "episodes.json") { [weak self] saved in
                if let self = self, let saved = saved {
                    self.episodes = saved
                    self.applyPlayedIDs()
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
        episodes = episodes.map { ep in
            var e = ep
            e.played = playedEpisodeIDs.contains(ep.id)
            return e
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
        
        // Apply played status to new episodes and add them
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
                            // Replace the existing episode with the newer one, but preserve played status and playback position
                            if let index = episodes.firstIndex(where: { $0.id == existingEpisode.id }) {
                                var updatedEpisode = episode
                                updatedEpisode.played = existingEpisode.played
                                updatedEpisode.playbackPosition = existingEpisode.playbackPosition
                                episodes[index] = updatedEpisode
                                existingEpisodesByTitle[key] = updatedEpisode
                            }
                        }
                        // Otherwise keep existing
                    case (_, nil):
                        // New episode has date, existing doesn't - prefer new, but preserve played status and playback position
                        if let index = episodes.firstIndex(where: { $0.id == existingEpisode.id }) {
                            var updatedEpisode = episode
                            updatedEpisode.played = existingEpisode.played
                            updatedEpisode.playbackPosition = existingEpisode.playbackPosition
                            episodes[index] = updatedEpisode
                            existingEpisodesByTitle[key] = updatedEpisode
                        }
                    default:
                        // Keep existing episode
                        break
                    }
                    continue
                }
            }
            
            // New episode - add it to the list to be added
            var newEpisode = episode
            newEpisode.played = playedEpisodeIDs.contains(episode.id)
            episodesToAdd.append(newEpisode)
            
            // Also add to our tracking dictionary
            if let podcastID = episode.podcastID {
                let key = "\(podcastID.uuidString)_\(episode.title)"
                existingEpisodesByTitle[key] = newEpisode
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