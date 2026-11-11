import Foundation
import Combine

/// Tracks listening time in real-time and persists stats to disk
final class ListeningStatsService {
    static let shared = ListeningStatsService()

    private(set) var stats: ListeningStats
    private var timer: Timer?
    private var lastTickDate: Date?
    private let saveInterval: TimeInterval = 30  // Save every 30s
    private var unsavedSeconds: TimeInterval = 0
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("listening_stats.json")
        stats = Self.load(from: fileURL) ?? ListeningStats()
    }

    // MARK: - Tracking

    /// Start tracking listening time. Call when playback begins.
    func startTracking(podcastID: String?) {
        stopTracking()
        lastTickDate = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let lastTick = self.lastTickDate else { return }
            let elapsed = Date().timeIntervalSince(lastTick)
            self.lastTickDate = Date()

            self.stats.addListeningTime(elapsed, podcastID: podcastID)
            self.unsavedSeconds += elapsed

            if self.unsavedSeconds >= self.saveInterval {
                self.save()
                self.unsavedSeconds = 0
            }
        }
    }

    /// Stop tracking. Call when playback pauses/stops.
    func stopTracking() {
        if let lastTick = lastTickDate {
            let elapsed = Date().timeIntervalSince(lastTick)
            if elapsed > 0 && elapsed < 60 {  // Sanity check
                stats.addListeningTime(elapsed, podcastID: nil)
            }
        }
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
        save()
    }

    /// Mark an episode as completed
    func markEpisodeCompleted() {
        stats.markEpisodeCompleted()
        save()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(stats) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> ListeningStats? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ListeningStats.self, from: data)
    }

    /// Reload stats from disk (useful after iCloud sync)
    func reload() {
        if let loaded = Self.load(from: fileURL) {
            stats = loaded
        }
    }
}
