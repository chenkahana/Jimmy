import Foundation

/// Errors from a subscribe/unsubscribe attempt, surfaced by `AppModel.subscribe(feedURL:)` and
/// mapped here for the screens (Discover, Search, podcast detail) that show them. Factored out of
/// the old `SubscriptionStateManager`, which is gone, but
/// these types are still what every subscribe UI shows on failure.
enum SubscriptionError: Error, LocalizedError, Equatable {
    case networkError(String)
    case databaseError(String)
    case alreadySubscribed
    case notSubscribed
    case notFound
    case timeout
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error. Please check your connection and try again."
        case .databaseError:
            return "Unable to save subscription. Please try again."
        case .alreadySubscribed:
            return "You're already subscribed to this podcast."
        case .notSubscribed:
            return "You're not subscribed to this podcast."
        case .notFound:
            return "Podcast not found. Please try again."
        case .timeout:
            return "Operation timed out. Please try again."
        case .unknownError(let message):
            return "An error occurred: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again."
        case .databaseError:
            return "Try restarting the app or contact support if the problem persists."
        case .alreadySubscribed:
            return "You can find this podcast in your library."
        case .notSubscribed:
            return "Subscribe to this podcast first."
        case .notFound:
            return "Make sure the podcast URL is correct."
        case .timeout:
            return "Try again with a better internet connection."
        case .unknownError:
            return "Try again or contact support if the problem persists."
        }
    }

    /// Maps whatever `AppModel.subscribe(feedURL:)` threw (or any other error) to one of these
    /// cases, the way `SubscriptionStateManager.mapError` used to.
    static func mapping(_ error: Error) -> SubscriptionError {
        if let subscriptionError = error as? SubscriptionError {
            return subscriptionError
        }
        if error.localizedDescription.contains("network") || error.localizedDescription.contains("internet") {
            return .networkError(error.localizedDescription)
        }
        if error.localizedDescription.contains("database") || error.localizedDescription.contains("save") {
            return .databaseError(error.localizedDescription)
        }
        if error.localizedDescription.contains("timeout") {
            return .timeout
        }
        if error.localizedDescription.contains("not found") {
            return .notFound
        }
        return .unknownError(error.localizedDescription)
    }
}

struct SubscriptionErrorHandler {
    static func handle(_ error: SubscriptionError, for podcastTitle: String) -> String {
        switch error {
        case .networkError:
            return "Network error while subscribing to \(podcastTitle). Please check your connection and try again."
        case .databaseError:
            return "Unable to save subscription to \(podcastTitle). Please try again."
        case .alreadySubscribed:
            return "You're already subscribed to \(podcastTitle)."
        case .notSubscribed:
            return "You're not subscribed to \(podcastTitle)."
        case .notFound:
            return "\(podcastTitle) not found. Please try again."
        case .timeout:
            return "Subscription to \(podcastTitle) timed out. Please try again."
        case .unknownError(let message):
            return "Failed to subscribe to \(podcastTitle): \(message)"
        }
    }

    static func handleUnsubscribe(_ error: SubscriptionError, for podcastTitle: String) -> String {
        switch error {
        case .networkError:
            return "Network error while unsubscribing from \(podcastTitle). Please check your connection and try again."
        case .databaseError:
            return "Unable to remove subscription to \(podcastTitle). Please try again."
        case .alreadySubscribed:
            return "You're still subscribed to \(podcastTitle)."
        case .notSubscribed:
            return "You're not subscribed to \(podcastTitle)."
        case .notFound:
            return "\(podcastTitle) not found in your subscriptions."
        case .timeout:
            return "Unsubscribe from \(podcastTitle) timed out. Please try again."
        case .unknownError(let message):
            return "Failed to unsubscribe from \(podcastTitle): \(message)"
        }
    }
}
