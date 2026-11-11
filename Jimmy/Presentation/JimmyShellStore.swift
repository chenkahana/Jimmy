import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

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

enum ShellTab: Int, CaseIterable {
    case queue = 0
    case library = 1
    case discover = 2
    case settings = 3

    var identifier: String {
        switch self {
        case .queue:
            return "tab.queue"
        case .library:
            return "tab.library"
        case .discover:
            return "tab.discover"
        case .settings:
            return "tab.settings"
        }
    }

    init?(identifier: String) {
        switch identifier {
        case "tab.queue":
            self = .queue
        case "tab.library":
            self = .library
        case "tab.discover":
            self = .discover
        case "tab.settings":
            self = .settings
        default:
            return nil
        }
    }

    var destination: ShellDestination {
        switch self {
        case .queue:
            return .queue
        case .library:
            return .library
        case .discover:
            return .discover(query: nil)
        case .settings:
            return .settings
        }
    }
}

@MainActor
@Observable
final class ShellChromeModel {
    static let shared = ShellChromeModel()

    var prefersTabBarMinimization = true
    var isDiscoverSearchActive = false
    var showsMiniPlayer = false
    var isMiniPlayerInline = false
    var isPresentingModal = false

    private init() {}

    func setSearchActive(_ isActive: Bool) {
        isDiscoverSearchActive = isActive
    }

    @available(iOS 26.0, *)
    func updateAccessoryEnvironment(_ environment: UITabAccessory.Environment) {
        isMiniPlayerInline = environment == .inline
    }
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
    let chrome = ShellChromeModel.shared

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
            selectedTab = .discover
            tabSelectionEventID = UUID()
            if let query, !query.isEmpty {
                discoverSearchQuery = query
                isDiscoverSearchFocused = true
                chrome.setSearchActive(true)
            } else {
                discoverSearchQuery = ""
                isDiscoverSearchFocused = false
                chrome.setSearchActive(false)
            }
        case .settings:
            pendingContentRoute = nil
            selectTab(.settings)
        case .podcast(let id):
            pendingContentRoute = .podcast(id)
            selectTab(.library)
        case .episode(let id):
            pendingContentRoute = .episode(id)
            selectTab(.library)
        }

    }

    func handleUserSelectedTab(identifier: String) {
        guard let tab = ShellTab(identifier: identifier) else {
            return
        }

        if pendingContentRoute == nil || tab != .library {
            pendingContentRoute = nil
        }

        selectTab(tab)
    }

    func updateDiscoverSearch(query: String) {
        discoverSearchQuery = query
        chrome.setSearchActive(!query.isEmpty || isDiscoverSearchFocused)
    }

    func setDiscoverSearchFocused(_ isFocused: Bool) {
        isDiscoverSearchFocused = isFocused
        chrome.setSearchActive(isFocused || !discoverSearchQuery.isEmpty)
        if isFocused {
            selectedTab = .discover
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
        if tab != .discover {
            discoverSearchQuery = ""
            isDiscoverSearchFocused = false
            chrome.setSearchActive(false)
        }
    }
}
