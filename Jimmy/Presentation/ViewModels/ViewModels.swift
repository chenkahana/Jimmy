// MARK: - Jimmy App ViewModels
// This file provides a single import point for all ViewModels in the app

import Foundation

/// ViewModels Registry for dependency injection and testing
@MainActor
class ViewModelsRegistry {
    // MARK: - Singleton ViewModels
    static let shared = ViewModelsRegistry()
    
    // Core ViewModels (Singletons)
    let libraryViewModel = LibraryViewModel.shared
    let discoveryViewModel = DiscoveryViewModel.shared
    let queueViewModel = QueueViewModel.shared
    let audioPlayerViewModel = AudioPlayerViewModel.shared
    let settingsViewModel = SettingsViewModel.shared
    
    private init() {}
    
    // MARK: - Factory Methods for Detail ViewModels
    func makePodcastDetailViewModel(for podcast: Podcast) -> PodcastDetailViewModel {
        return PodcastDetailViewModel(podcast: podcast)
    }
    
    func makeEpisodeDetailViewModel(for episode: Episode) -> EpisodeDetailViewModel {
        return EpisodeDetailViewModel(episode: episode)
    }
    
    func makePodcastSearchViewModel() -> PodcastSearchViewModel {
        return PodcastSearchViewModel()
    }
    
    func makeEpisodeListViewModel() -> EpisodeListViewModel {
        return EpisodeListViewModel()
    }
    
    // MARK: - Testing Support
    #if DEBUG
    func resetAllViewModels() {
        // Reset singleton state for testing
        // This would need to be implemented in each ViewModel
    }
    #endif
}