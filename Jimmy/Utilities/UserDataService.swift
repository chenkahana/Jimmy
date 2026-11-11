import Foundation

/// Minimal representation of a subscribed podcast used for persistence. This is
/// kept small so the utilities package does not depend on the main app model.
public struct PodcastInfo: Codable, Equatable {
    public var title: String
    public var feedURL: URL

    public init(title: String, feedURL: URL) {
        self.title = title
        self.feedURL = feedURL
    }
}

public struct UserData: Codable, Equatable {
    public var subscriptions: [PodcastInfo]
    public var listenedEpisodeIDs: [UUID]

    public init(subscriptions: [PodcastInfo] = [], listenedEpisodeIDs: [UUID] = []) {
        self.subscriptions = subscriptions
        self.listenedEpisodeIDs = listenedEpisodeIDs
    }
}

/// Stores and retrieves user specific podcast data using `FileStorage`.
public class UserDataService {
    public static let shared = UserDataService()
    private let storage = FileStorage.shared

    private init() {}

    /// Build a sanitized filename for the given user identifier. Returns `nil`
    /// if the identifier is empty or contains path separators.
    private func filename(for userID: String) -> String? {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: "[/\\]", options: .regularExpression) == nil else {
            return nil
        }
        return "user_\(trimmed)_data.json"
    }

    @discardableResult
    public func save(_ data: UserData, for userID: String) -> Bool {
        guard let filename = filename(for: userID) else { return false }
        return storage.save(data, to: filename)
    }

    public func load(for userID: String) -> UserData? {
        guard let filename = filename(for: userID) else { return nil }
        return storage.load(UserData.self, from: filename)
    }
}
