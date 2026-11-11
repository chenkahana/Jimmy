import Foundation

/// Parses jimmy:// URLs and dispatches navigation to the correct tab/view
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    private init() {}

    // MARK: - URL Parsing

    /// Parse a URL into a DeepLink destination.
    /// Supports:
    ///   jimmy://queue
    ///   jimmy://library
    ///   jimmy://discover
    ///   jimmy://settings
    ///   jimmy://nowplaying
    ///   jimmy://episode/<uuid>
    ///   jimmy://podcast/<uuid>
    ///   jimmy://subscribe?url=<feed_url>
    func parse(url: URL) -> DeepLink? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "jimmy" else { return nil }

        let host = url.host?.lowercased() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "queue":
            return .queue
        case "library":
            return .library
        case "discover", "search":
            return .discover
        case "settings":
            return .settings
        case "nowplaying", "now-playing":
            return .nowPlaying
        case "episode":
            if let idString = pathComponents.first, let id = UUID(uuidString: idString) {
                return .episode(id)
            }
        case "podcast":
            if let idString = pathComponents.first, let id = UUID(uuidString: idString) {
                return .podcast(id)
            }
        case "subscribe":
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let feedURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let feedURL = URL(string: feedURLString) {
                return .subscribe(feedURL)
            }
        default:
            break
        }

        return nil
    }

    // MARK: - Navigation Dispatch

    /// Navigate to a deep link destination
    @MainActor
    func navigate(to deepLink: DeepLink) {
        switch deepLink {
        case .queue:
            ShellStore.shared.navigate(to: .queue)
        case .library:
            ShellStore.shared.navigate(to: .library)
        case .discover:
            ShellStore.shared.navigate(to: .discover(query: nil))
        case .settings:
            ShellStore.shared.navigate(to: .settings)
        case .nowPlaying:
            ShellStore.shared.present(.nowPlaying)
        case .episode(let id):
            ShellStore.shared.navigate(to: .episode(id))
        case .podcast(let id):
            ShellStore.shared.navigate(to: .podcast(id))
        case .subscribe(let feedURL):
            Task {
                _ = try? await AppModel.current?.subscribe(feedURL: feedURL)
            }
            ShellStore.shared.navigate(to: .library)
        }
    }
}
