import SwiftUI
import Combine

/// Manages swipe action state across all episode components to ensure only one can be open at a time
@MainActor
class SwipeStateManager: ObservableObject {
    static let shared = SwipeStateManager()
    
    @Published private var currentlyOpenEpisodeID: UUID?
    
    private init() {}
    
    /// Check if the given episode ID is currently showing swipe actions
    func isShowingActions(for episodeID: UUID) -> Bool {
        return currentlyOpenEpisodeID == episodeID
    }
    
    /// Set which episode is currently showing swipe actions
    func setShowingActions(for episodeID: UUID) {
        currentlyOpenEpisodeID = episodeID
    }
    
    /// Close all swipe actions
    func closeAllSwipeActions() {
        currentlyOpenEpisodeID = nil
    }
    
    /// Close swipe actions for a specific episode
    func closeSwipeActions(for episodeID: UUID) {
        if currentlyOpenEpisodeID == episodeID {
            currentlyOpenEpisodeID = nil
        }
    }
} 