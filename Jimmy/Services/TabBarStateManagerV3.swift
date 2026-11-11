import SwiftUI
import Combine

@MainActor
class TabBarStateManagerV3: ObservableObject {
    @Published var currentState: TabBarState = .full
    @Published var isSearchActive: Bool = false
    @Published var selectedTab: Int = 0
    @Published var accessoryView: AnyView?
    
    private var debounceTask: Task<Void, Never>?
    
    var tabBarHeight: CGFloat {
        switch currentState {
        case .full:
            return TabBarDimensionsV3.heightFull
        case .minimized:
            return TabBarDimensionsV3.heightMinimized
        case .withAccessory(let height):
            return TabBarDimensionsV3.heightFull + height
        }
    }
    
    var shouldShowLabels: Bool {
        switch currentState {
        case .full, .withAccessory:
            return true
        case .minimized:
            return false
        }
    }
    
    var shouldShowSelectionIndicator: Bool {
        currentState != .minimized
    }
    
    func updateState(_ newState: TabBarState, animated: Bool = true) {
        guard currentState != newState else { return }
        
        if animated {
            withAnimation(TabBarAnimationsV3.restoration) {
                currentState = newState
            }
        } else {
            currentState = newState
        }
    }
    
    func handleSearchActivation() {
        // Debounce rapid changes
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard !Task.isCancelled else { return }
            
            isSearchActive = true
            updateState(.minimized)
            announceStateChange("Search active, tab bar minimized")
        }
    }
    
    func handleSearchDismissal() {
        // Debounce rapid changes
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard !Task.isCancelled else { return }
            
            isSearchActive = false
            updateState(.full)
            announceStateChange("Search dismissed, tab bar restored")
        }
    }
    
    private func announceStateChange(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
