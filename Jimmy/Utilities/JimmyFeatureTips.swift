import SwiftUI
import TipKit

struct QueueReorderTip: Tip {
    static let reorderedQueue = Event(id: "queue-reordered")

    var title: Text {
        Text("Reorder your queue")
    }

    var message: Text? {
        Text("Drag any episode to promote the next must-hear pick.")
    }

    var image: Image? {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
    }

    var rules: [Rule] {
        [
            #Rule(Self.reorderedQueue) { event in
                event.donations.count == 0
            }
        ]
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

struct DiscoverSearchTip: Tip {
    static let searchedCatalog = Event(id: "discover-searched-catalog")

    var title: Text {
        Text("Search the full catalog")
    }

    var message: Text? {
        Text("Search works across featured picks, charts, and direct show lookup from one field.")
    }

    var image: Image? {
        Image(systemName: "magnifyingglass.circle")
    }

    var rules: [Rule] {
        [
            #Rule(Self.searchedCatalog) { event in
                event.donations.count == 0
            }
        ]
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

struct MiniPlayerTip: Tip {
    static let openedNowPlaying = Event(id: "mini-player-opened")

    var title: Text {
        Text("Jump back into now playing")
    }

    var message: Text? {
        Text("Tap the mini player to expand controls without losing your place in the app.")
    }

    var image: Image? {
        Image(systemName: "play.rectangle.on.rectangle")
    }

    var rules: [Rule] {
        [
            #Rule(Self.openedNowPlaying) { event in
                event.donations.count == 0
            }
        ]
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}
