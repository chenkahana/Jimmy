import Foundation

struct GoogleTakeoutParser {
    struct GoogleFeed: Codable {
        let title: String
        let feedUrl: String
    }
    struct GoogleSubscriptions: Codable {
        let subscriptions: [GoogleFeed]
    }
    static func parse(data: Data) throws -> [Podcast] {
        let decoder = JSONDecoder()
        let subs = try decoder.decode(GoogleSubscriptions.self, from: data)
        return subs.subscriptions.compactMap { feed in
            guard let url = URL(string: feed.feedUrl) else { return nil }
            return Podcast(title: feed.title, author: "", feedURL: url, artworkURL: nil)
        }
    }
} 