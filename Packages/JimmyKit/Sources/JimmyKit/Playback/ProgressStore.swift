import Foundation

/// Loads and saves playback `Progress`. Backed by the (parallel-authored) Store module in the
/// real app; `Playback` only depends on this protocol so it doesn't need to wait on that work.
public protocol ProgressStore {
    func loadProgress(for episodeID: UUID) async -> Progress?
    func saveProgress(_ progress: Progress) async
}
