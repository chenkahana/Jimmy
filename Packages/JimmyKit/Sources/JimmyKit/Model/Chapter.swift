import Foundation

/// A chapter marker within a podcast episode (Podcasting 2.0 JSON Chapters spec). `CodingKeys`
/// matches the spec's on-the-wire field names (`startTime`, `img`) exactly, so this type decodes
/// directly both from a Podcasting 2.0 chapters endpoint and from what `Store` has stored in
/// `episode_details.chaptersJSON` since before JimmyKit existed.
public nonisolated struct Chapter: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(start)" }
    public var start: TimeInterval
    public var title: String
    public var url: URL?
    public var imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case start = "startTime"
        case title
        case url
        case imageURL = "img"
    }

    public init(start: TimeInterval, title: String, url: URL? = nil, imageURL: URL? = nil) {
        self.start = start
        self.title = title
        self.url = url
        self.imageURL = imageURL
    }
}
