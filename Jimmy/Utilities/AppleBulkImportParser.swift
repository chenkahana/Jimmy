import Foundation

struct AppleBulkImportParser {
    struct ExportedPodcast: Codable {
        let title: String
        let feedURL: String
        let author: String?

        enum CodingKeys: String, CodingKey {
            case title
            case feedURL = "feedUrl"
            case author
        }
    }

    static func parse(data: Data) throws -> [Podcast] {
        let decoder = JSONDecoder()
        let exports = try decoder.decode([ExportedPodcast].self, from: data)
        return exports.compactMap { item in
            guard let url = URL(string: item.feedURL) else { return nil }
            return Podcast(title: item.title,
                           author: item.author ?? "",
                           description: "",
                           feedURL: url,
                           artworkURL: nil)
        }
    }
}
