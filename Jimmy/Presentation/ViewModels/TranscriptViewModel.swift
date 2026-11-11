import Foundation
import Combine
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
    private var cancellables = Set<AnyCancellable>()

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
        } catch {
            Self.logger.error("Failed to fetch transcript: \(error)")
        }
        isLoading = false
    }

    private func observePlaybackPosition() {
        AudioPlayerService.shared.$playbackPosition
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] position in
                self?.updateCurrentSegment(for: position)
            }
            .store(in: &cancellables)
    }

    private func updateCurrentSegment(for position: TimeInterval) {
        currentSegment = segments.last { $0.startTime <= position && position < $0.endTime }
    }
}
