import Foundation
import JimmyKit
import Combine
import os

/// ViewModel for managing bookmarks for a specific episode, read and written through `AppModel`/
/// `Store` directly.
@MainActor
class BookmarkViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "BookmarkViewModel")
    @Published var bookmarks: [Bookmark] = []
    @Published var isLoading = false

    private let episodeID: UUID

    init(episodeID: UUID) {
        self.episodeID = episodeID
        Task { await loadBookmarks() }
    }

    func loadBookmarks() async {
        isLoading = true
        bookmarks = await AppModel.current?.bookmarks(for: episodeID) ?? []
        isLoading = false
    }

    func addBookmark(timestamp: TimeInterval, note: String = "") async {
        guard let bookmark = await AppModel.current?.addBookmark(episodeID: episodeID, timestamp: timestamp, note: note) else {
            Self.logger.error("Failed to add bookmark: store not ready")
            return
        }
        bookmarks.append(bookmark)
        bookmarks.sort { $0.timestamp < $1.timestamp }
    }

    func deleteBookmark(_ bookmark: Bookmark) async {
        await AppModel.current?.deleteBookmark(bookmark.id)
        bookmarks.removeAll { $0.id == bookmark.id }
    }
}
