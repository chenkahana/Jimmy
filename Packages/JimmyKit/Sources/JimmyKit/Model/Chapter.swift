import Foundation

/// A chapter marker within a podcast episode (Podcasting 2.0 JSON Chapters spec).
public nonisolated struct Chapter: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(start)" }
    public var start: TimeInterval
    public var title: String
    public var url: URL?
    public var imageURL: URL?

    public init(start: TimeInterval, title: String, url: URL? = nil, imageURL: URL? = nil) {
        self.start = start
        self.title = title
        self.url = url
        self.imageURL = imageURL
    }
}
