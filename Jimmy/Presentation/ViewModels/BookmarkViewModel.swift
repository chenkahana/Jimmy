import Foundation
import Combine
import os

/// ViewModel for managing bookmarks for a specific episode or globally
@MainActor
class BookmarkViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "BookmarkViewModel")
    @Published var bookmarks: [Bookmark] = []
    @Published var isLoading = false

    private let bookmarkService = BookmarkService.shared
    private let episodeID: UUID?

    /// Init for a specific episode's bookmarks
    init(episodeID: UUID) {
        self.episodeID = episodeID
        Task { await loadBookmarks() }
    }

    /// Init for global bookmarks view
    init() {
        self.episodeID = nil
        Task { await loadBookmarks() }
    }

    func loadBookmarks() async {
        isLoading = true
        do {
            if let episodeID = episodeID {
                bookmarks = try await bookmarkService.bookmarks(for: episodeID)
            } else {
                bookmarks = try await bookmarkService.allBookmarks()
            }
        } catch {
            Self.logger.error("Failed to load bookmarks: \(error)")
        }
        isLoading = false
    }

    func addBookmark(timestamp: TimeInterval, note: String = "") async {
        guard let episodeID = episodeID else { return }
        do {
            let bookmark = try await bookmarkService.addBookmark(
                episodeID: episodeID,
                timestamp: timestamp,
                note: note
            )
            bookmarks.append(bookmark)
            bookmarks.sort { $0.timestamp < $1.timestamp }
        } catch {
            Self.logger.error("Failed to add bookmark: \(error)")
        }
    }

    func deleteBookmark(_ bookmark: Bookmark) async {
        do {
            try await bookmarkService.deleteBookmark(bookmark.id)
            bookmarks.removeAll { $0.id == bookmark.id }
        } catch {
            Self.logger.error("Failed to delete bookmark: \(error)")
        }
    }

    func updateNote(for bookmark: Bookmark, note: String) async {
        do {
            try await bookmarkService.updateBookmarkNote(bookmark.id, note: note)
            if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                bookmarks[index].note = note
            }
        } catch {
            Self.logger.error("Failed to update bookmark note: \(error)")
        }
    }
}
