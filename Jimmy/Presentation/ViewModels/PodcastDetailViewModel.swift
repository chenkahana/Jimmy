import Foundation

/// Filter and sort options for a podcast's episode list, shared by `PodcastDetailView`, the
/// episode-row list it embeds, and `StickyCompactHeader`'s filter/sort menu.
///
/// This is all that's left of the old `PodcastDetailViewModel` class: PR 18 moved
/// `PodcastDetailView` onto `AppModel`/`Store` directly, so there's no view model left — just the
/// two enums it used to define. Kept under this name so none of those three files needed to change
/// their `PodcastDetailViewModel.EpisodeFilter`/`.EpisodeSortOrder` references.
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
