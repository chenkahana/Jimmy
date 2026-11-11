import Foundation

/// A chapter marker within a podcast episode (Podcasting 2.0 JSON Chapters spec)
struct Chapter: Codable, Equatable, Identifiable {
    var id: String { "\(startTime)" }
    var title: String
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var imageURL: URL?
    var url: URL?

    enum CodingKeys: String, CodingKey {
        case title, startTime, endTime
        case imageURL = "img"
        case url
    }
}

/// Container for Podcasting 2.0 JSON Chapters format
struct ChaptersResponse: Codable {
    let version: String?
    let chapters: [Chapter]
}
