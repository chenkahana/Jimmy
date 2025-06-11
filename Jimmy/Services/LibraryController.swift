import Foundation
import SwiftUI

extension Notification.Name {
    static let uiUpdateCompleted = Notification.Name("uiUpdateCompleted")
    static let uiBatchUpdateCompleted = Notification.Name("uiBatchUpdateCompleted")
}

/// Temporary LibraryController stub for build compatibility
@MainActor
class LibraryController: ObservableObject {
    static let shared = LibraryController()
    
    // Published properties needed by LibraryView
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var filteredPodcasts: [Podcast] = []
    @Published var filteredEpisodes: [Episode] = []
    @Published var isEditMode: Bool = false
    
    private init() {}
    
    func reloadData() {
        // Stub implementation
        print("📚 LibraryController: Reloading data")
    }
    
    func refreshEpisodeData() {
        // Stub implementation
        print("📚 LibraryController: Refreshing episode data")
    }
    
    func toggleEditMode() {
        // Stub implementation
        print("✏️ LibraryController: Toggling edit mode")
        isEditMode.toggle()
    }
    
    func loadData() {
        // Stub implementation
        print("📚 LibraryController: Loading data")
    }
    
    // Additional methods needed by LibraryView
    func refreshPodcastData() {
        print("📚 LibraryController: Refreshing podcast data")
    }
    
    func refreshPodcastDataAsync() async {
        print("📚 LibraryController: Refreshing podcast data async")
    }
    
    func refreshEpisodeDataAsync() async {
        print("📚 LibraryController: Refreshing episode data async")
    }
    
    func refreshAllData() async {
        print("📚 LibraryController: Refreshing all data")
    }
    
    func clearSearch() {
        print("🔍 LibraryController: Clearing search")
        searchText = ""
    }
    
    func getLatestEpisodeDate(for podcast: Podcast) -> Date? {
        return nil // Stub implementation
    }
    
    func getEpisodesCount(for podcast: Podcast) -> Int {
        return 0 // Stub implementation
    }
    
    func getUnplayedEpisodesCount(for podcast: Podcast) -> Int {
        return 0 // Stub implementation
    }
    
    func deletePodcast(_ podcast: Podcast) {
        print("🗑️ LibraryController: Deleting podcast: \(podcast.title)")
    }
    
    func getPodcast(for episode: Episode) -> Podcast? {
        return nil // Stub implementation
    }
} 