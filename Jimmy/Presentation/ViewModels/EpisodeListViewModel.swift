import Foundation
import Combine

/// ViewModel for Episode List functionality following MVVM patterns
@MainActor
class EpisodeListViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var episodes: [Episode] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let episodeService: EpisodeCacheService
    private let podcastService: PodcastService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(episodeService: EpisodeCacheService = .shared, podcastService: PodcastService = .shared) {
        self.episodeService = episodeService
        self.podcastService = podcastService
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    func loadEpisodes(for podcastID: UUID) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let loadedEpisodes = await episodeService.getEpisodes(for: podcastID)
            // Safely unwrap the optional array and sort
            episodes = (loadedEpisodes ?? []).sorted { episode1, episode2 in
                // Sort by published date, newest first
                let date1 = episode1.publishedDate ?? Date.distantPast
                let date2 = episode2.publishedDate ?? Date.distantPast
                return date1 > date2
            }
        } catch {
            errorMessage = "Failed to load episodes: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func refreshEpisodes(for podcastID: UUID) async {
        await loadEpisodes(for: podcastID)
    }
    
    func deleteEpisode(_ episode: Episode) async {
        // Remove from local array
        episodes.removeAll { $0.id == episode.id }
        
        // Update cache if we have a valid podcast ID
        guard let podcastID = episode.podcastID else {
            errorMessage = "Cannot delete episode: missing podcast ID"
            return
        }
        
        do {
            // Get all episodes for this podcast
            let allEpisodes = await episodeService.getEpisodes(for: podcastID)
            // Remove the deleted episode and save back
            if let allEpisodes = allEpisodes {
                let updatedEpisodes = allEpisodes.filter { $0.id != episode.id }
                await episodeService.saveEpisodes(updatedEpisodes, for: podcastID)
            }
        } catch {
            errorMessage = "Failed to delete episode: \(error.localizedDescription)"
        }
    }
    
    func markAsPlayed(_ episode: Episode, played: Bool) async {
        // Update local array
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            var updatedEpisode = episodes[index]
            updatedEpisode.played = played
            episodes[index] = updatedEpisode
        }
        
        // Update cache if we have a valid podcast ID
        guard let podcastID = episode.podcastID else {
            errorMessage = "Cannot update episode: missing podcast ID"
            return
        }
        
        do {
            // Get all episodes for this podcast
            let allEpisodes = await episodeService.getEpisodes(for: podcastID)
            // Update the specific episode and save back
            if let allEpisodes = allEpisodes {
                let updatedEpisodes = allEpisodes.map { ep in
                    if ep.id == episode.id {
                        var updated = ep
                        updated.played = played
                        return updated
                    }
                    return ep
                }
                await episodeService.saveEpisodes(updatedEpisodes, for: podcastID)
            }
        } catch {
            errorMessage = "Failed to update episode: \(error.localizedDescription)"
        }
    }
    
    func markAllEpisodesAsPlayed(for podcastID: UUID) {
        // Update local state immediately
        for index in episodes.indices {
            if episodes[index].podcastID == podcastID {
                var updatedEpisode = episodes[index]
                updatedEpisode.played = true
                episodes[index] = updatedEpisode
            }
        }
        
        // Update in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.updateAllEpisodesPlayedStatus(for: podcastID, played: true)
        }
    }
    
    func markAllEpisodesAsUnplayed(for podcastID: UUID) {
        // Update local state immediately
        for index in episodes.indices {
            if episodes[index].podcastID == podcastID {
                var updatedEpisode = episodes[index]
                updatedEpisode.played = false
                episodes[index] = updatedEpisode
            }
        }
        
        // Update in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.updateAllEpisodesPlayedStatus(for: podcastID, played: false)
        }
    }
    
    func markEpisodeAsPlayed(_ episode: Episode, played: Bool) {
        // Update local state immediately
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            var updatedEpisode = episodes[index]
            updatedEpisode.played = played
            episodes[index] = updatedEpisode
        }
        
        // Update in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.updateEpisodePlayedStatus(episode, played: played)
        }
    }
    
    // MARK: - Private Methods
    private func updateAllEpisodesPlayedStatus(for podcastID: UUID, played: Bool) async {
        do {
            let allEpisodes = await episodeService.getEpisodes(for: podcastID)
            if let allEpisodes = allEpisodes {
                let updatedEpisodes = allEpisodes.map { episode in
                    var updatedEpisode = episode
                    updatedEpisode.played = played
                    return updatedEpisode
                }
                await episodeService.saveEpisodes(updatedEpisodes, for: podcastID)
            }
        } catch {
            // Handle error silently for background operation
        }
    }
    
    private func updateEpisodePlayedStatus(_ episode: Episode, played: Bool) async {
        guard let podcastID = episode.podcastID else { return }
        
        do {
            let allEpisodes = await episodeService.getEpisodes(for: podcastID)
            if let allEpisodes = allEpisodes {
                let updatedEpisodes = allEpisodes.map { ep in
                    if ep.id == episode.id {
                        var updated = ep
                        updated.played = played
                        return updated
                    }
                    return ep
                }
                await episodeService.saveEpisodes(updatedEpisodes, for: podcastID)
            }
        } catch {
            // Handle error silently for background operation
        }
    }
} 