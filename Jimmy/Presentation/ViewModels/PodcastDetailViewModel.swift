import Foundation

/// Filter and sort options for a podcast's episode list, shared by `PodcastDetailView` and the
/// episode rows it embeds.
///
/// This is all that's left of the old `PodcastDetailViewModel` class: PR 18 moved
/// `PodcastDetailView` onto `AppModel`/`Store` directly, so there's no view model left — just the
/// two enums it used to define.
public enum PodcastDetailViewModel {
    public enum EpisodeSortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case titleAZ = "Title A-Z"
        case titleZA = "Title Z-A"
        public var id: String { rawValue }
    }

    public enum EpisodeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case unplayed = "Unplayed"
        case played = "Played"
        case downloaded = "Downloaded"
        public var id: String { rawValue }
    }
}
