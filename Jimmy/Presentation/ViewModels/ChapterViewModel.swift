import Foundation
import JimmyKit
import Combine
import Observation
import os

/// ViewModel that tracks chapters and determines the current chapter based on playback position
@MainActor
class ChapterViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ChapterViewModel")
    @Published var chapters: [Chapter] = []
    @Published var currentChapter: Chapter?
    @Published var isLoading = false

    private let chapterService = ChapterService.shared
    private let episodeID: UUID

    init(episodeID: UUID) {
        self.episodeID = episodeID
        observePlaybackPosition()
        Task { await loadChapters() }
    }

    func loadChapters() async {
        isLoading = true
        chapters = await chapterService.loadChapters(for: episodeID)
        updateCurrentChapter(for: AppModel.current?.playback?.position ?? 0)
        isLoading = false
    }

    /// Fetch chapters from a remote URL and save to DB
    func fetchAndSaveChapters(from url: URL) async {
        isLoading = true
        do {
            let fetched = try await chapterService.fetchChapters(from: url)
            try await chapterService.saveChapters(fetched, for: episodeID)
            chapters = fetched
            updateCurrentChapter(for: AppModel.current?.playback?.position ?? 0)
        } catch {
            Self.logger.error("Failed to fetch chapters: \(error)")
        }
        isLoading = false
    }

    /// `Playback` is `@Observable`, not an `ObservableObject` this Combine-based view model can
    /// subscribe to — track `position` and re-register on every change instead.
    private func observePlaybackPosition() {
        withObservationTracking {
            updateCurrentChapter(for: AppModel.current?.playback?.position ?? 0)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePlaybackPosition()
            }
        }
    }

    private func updateCurrentChapter(for position: TimeInterval) {
        // Find the chapter that contains the current position
        let chapter = chapters.last { chapter in
            position >= chapter.startTime
        }
        if chapter?.startTime != currentChapter?.startTime {
            currentChapter = chapter
        }
    }
}
