import Foundation
import JimmyKit
import Combine
import Observation
import os

/// ViewModel that tracks chapters and determines the current chapter based on playback position.
/// Read and written through `AppModel`/`Store` directly; fetching the Podcasting 2.0 JSON
/// Chapters file from its URL is this view model's own job — the store only persists the
/// already-parsed result.
@MainActor
class ChapterViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ChapterViewModel")
    @Published var chapters: [Chapter] = []
    @Published var currentChapter: Chapter?
    @Published var isLoading = false

    private let episodeID: UUID

    init(episodeID: UUID) {
        self.episodeID = episodeID
        observePlaybackPosition()
        Task { await loadChapters() }
    }

    func loadChapters() async {
        isLoading = true
        chapters = await AppModel.current?.chapters(for: episodeID) ?? []
        updateCurrentChapter(for: AppModel.current?.playback?.position ?? 0)
        isLoading = false
    }

    /// Fetch chapters from a remote Podcasting 2.0 JSON Chapters URL and save to the store.
    func fetchAndSaveChapters(from url: URL) async {
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ChaptersResponse.self, from: data)
            await AppModel.current?.saveChapters(response.chapters, for: episodeID)
            chapters = response.chapters
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
        let chapter = chapters.last { chapter in
            position >= chapter.start
        }
        if chapter?.start != currentChapter?.start {
            currentChapter = chapter
        }
    }
}

/// Container for the Podcasting 2.0 JSON Chapters format.
private struct ChaptersResponse: Codable {
    let version: String?
    let chapters: [Chapter]
}
