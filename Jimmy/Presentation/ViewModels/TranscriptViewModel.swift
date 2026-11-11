import Foundation
import JimmyKit
import Combine
import Observation
import os

/// Syncs current transcript segment to playback position, supports search
@MainActor
class TranscriptViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "TranscriptViewModel")
    @Published var segments: [TranscriptSegment] = []
    @Published var currentSegment: TranscriptSegment?
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var hasTranscript = false

    private let episodeID: UUID

    var filteredSegments: [TranscriptSegment] {
        if searchText.isEmpty { return segments }
        return segments.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    init(episodeID: UUID) {
        self.episodeID = episodeID
        observePlaybackPosition()
        Task { await loadTranscript() }
    }

    func loadTranscript() async {
        isLoading = true
        if let record = await TranscriptService.shared.loadTranscript(for: episodeID) {
            segments = record.segments
            hasTranscript = !segments.isEmpty
            updateCurrentSegment(for: AppModel.current?.playback?.position ?? 0)
        }
        isLoading = false
    }

    func fetchTranscript(from url: URL) async {
        isLoading = true
        do {
            let fetched = try await TranscriptService.shared.fetchTranscript(from: url)
            let format = url.pathExtension.isEmpty ? "json" : url.pathExtension
            try await TranscriptService.shared.saveTranscript(for: episodeID, segments: fetched, url: url.absoluteString, format: format)
            segments = fetched
            hasTranscript = !fetched.isEmpty
            updateCurrentSegment(for: AppModel.current?.playback?.position ?? 0)
        } catch {
            Self.logger.error("Failed to fetch transcript: \(error)")
        }
        isLoading = false
    }

    /// `Playback` is `@Observable`, not an `ObservableObject` this Combine-based view model can
    /// subscribe to — track `position` and re-register on every change instead.
    private func observePlaybackPosition() {
        withObservationTracking {
            updateCurrentSegment(for: AppModel.current?.playback?.position ?? 0)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePlaybackPosition()
            }
        }
    }

    private func updateCurrentSegment(for position: TimeInterval) {
        let segment = segments.last { $0.startTime <= position && position < $0.endTime }
        if segment?.startTime != currentSegment?.startTime {
            currentSegment = segment
        }
    }
}
