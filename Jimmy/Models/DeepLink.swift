import Foundation

/// Represents all deep link destinations in Jimmy
enum DeepLink: Equatable {
    case episode(UUID)
    case podcast(UUID)
    case queue
    case discover
    case nowPlaying
    case subscribe(URL)
    case library
    case settings
}
