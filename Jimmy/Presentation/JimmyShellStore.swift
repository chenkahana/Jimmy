import Foundation
import Observation

enum ShellDestination: Equatable {
    case queue
    case library
    case discover(query: String? = nil)
    case settings
    case podcast(UUID)
    case episode(UUID)
}

enum ShellPresentation: Equatable {
    case nowPlaying
}

enum ShellContentRoute: Equatable {
    case podcast(UUID)
    case episode(UUID)

    var id: String {
        switch self {
        case .podcast(let id):
            return "podcast-\(id.uuidString)"
        case .episode(let id):
            return "episode-\(id.uuidString)"
        }
    }
}

enum ShellTab: Hashable {
    case queue
    case library
    case search
}

/// A sheet the shell presents over the tabs; the Library menu and `jimmy://settings` open these.
enum ShellSheet: String, Identifiable {
    case settings
    case addByURL
    case stats
    case feedback

    var id: Self { self }
}

@MainActor
@Observable
final class ShellStore {
    static let shared = ShellStore()

    private(set) var selectedTab: ShellTab = .queue
    private(set) var tabSelectionEventID = UUID()
    private(set) var discoverSearchQuery = ""
    private(set) var isDiscoverSearchFocused = false
    private(set) var presentation: ShellPresentation?
    private(set) var pendingContentRoute: ShellContentRoute?
    var sheet: ShellSheet?

    private init() {}

    func navigate(to destination: ShellDestination) {
        switch destination {
        case .queue:
            pendingContentRoute = nil
            selectTab(.queue)
        case .library:
            pendingContentRoute = nil
            selectTab(.library)
        case .discover(let query):
            pendingContentRoute = nil
            selectedTab = .search
            tabSelectionEventID = UUID()
            if let query, !query.isEmpty {
                discoverSearchQuery = query
                isDiscoverSearchFocused = true
            } else {
                discoverSearchQuery = ""
                isDiscoverSearchFocused = false
            }
        case .settings:
            sheet = .settings
        case .podcast(let id):
            pendingContentRoute = .podcast(id)
            selectTab(.library)
        case .episode(let id):
            pendingContentRoute = .episode(id)
            selectTab(.library)
        }

    }

    func handleUserSelectedTab(_ tab: ShellTab) {
        if pendingContentRoute == nil || tab != .library {
            pendingContentRoute = nil
        }

        selectTab(tab)
    }

    func updateDiscoverSearch(query: String) {
        discoverSearchQuery = query
    }

    func setDiscoverSearchFocused(_ isFocused: Bool) {
        isDiscoverSearchFocused = isFocused
        if isFocused {
            selectedTab = .search
        }
    }

    func present(_ presentation: ShellPresentation) {
        self.presentation = presentation
    }

    func clearPresentation() {
        presentation = nil
    }

    func clearPendingContentRoute(_ route: ShellContentRoute? = nil) {
        guard route == nil || pendingContentRoute == route else {
            return
        }

        pendingContentRoute = nil
    }

    private func selectTab(_ tab: ShellTab) {
        selectedTab = tab
        tabSelectionEventID = UUID()
        if tab != .search {
            discoverSearchQuery = ""
            isDiscoverSearchFocused = false
        }
    }
}
