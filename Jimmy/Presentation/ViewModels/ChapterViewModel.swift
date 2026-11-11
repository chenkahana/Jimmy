import Foundation
import Combine
import os

/// ViewModel that tracks chapters and determines the current chapter based on playback position
@MainActor
class ChapterViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ChapterViewModel")
    @Published var chapters: [Chapter] = []
    @Published var currentChapter: Chapter?
    @Published var isLoading = false

    private let chapterService = ChapterService.shared
    private var cancellables = Set<AnyCancellable>()
    private let episodeID: UUID

    init(episodeID: UUID) {
        self.episodeID = episodeID
        observePlaybackPosition()
        Task { await loadChapters() }
    }

    func loadChapters() async {
        isLoading = true
        chapters = await chapterService.loadChapters(for: episodeID)
        isLoading = false
    }

    /// Fetch chapters from a remote URL and save to DB
    func fetchAndSaveChapters(from url: URL) async {
        isLoading = true
        do {
            let fetched = try await chapterService.fetchChapters(from: url)
            try await chapterService.saveChapters(fetched, for: episodeID)
            chapters = fetched
        } catch {
            Self.logger.error("Failed to fetch chapters: \(error)")
        }
        isLoading = false
    }

    private func observePlaybackPosition() {
        AudioPlayerService.shared.$playbackPosition
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] position in
                self?.updateCurrentChapter(for: position)
            }
            .store(in: &cancellables)
    }

    private func updateCurrentChapter(for position: TimeInterval) {
        // Find the chapter that contains the current position
        currentChapter = chapters.last { chapter in
            position >= chapter.startTime
        }
    }
}
