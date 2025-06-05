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

    private func filename(for userID: String) -> String {
        return "user_\(userID)_data.json"
    }

    @discardableResult
    public func save(_ data: UserData, for userID: String) -> Bool {
        storage.save(data, to: filename(for: userID))
    }

    public func load(for userID: String) -> UserData? {
        storage.load(UserData.self, from: filename(for: userID))
    }
}
