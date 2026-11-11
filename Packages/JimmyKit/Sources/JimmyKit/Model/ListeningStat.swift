import Foundation

/// One day's listening time, optionally attributed to a podcast. Aggregates (streaks, totals,
/// top podcasts) are derived by querying these rows rather than stored as separate fields.
public nonisolated struct ListeningStat: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    /// "yyyy-MM-dd", in the user's local calendar.
    public var date: String
    public var podcastID: UUID?
    public var seconds: TimeInterval

    public init(id: UUID = UUID(), date: String, podcastID: UUID? = nil, seconds: TimeInterval) {
        self.id = id
        self.date = date
        self.podcastID = podcastID
        self.seconds = seconds
    }
}
