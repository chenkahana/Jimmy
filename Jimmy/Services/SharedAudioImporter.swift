import Foundation
import UniformTypeIdentifiers

/// Handles importing audio files shared to the app
class SharedAudioImporter {
    static let shared = SharedAudioImporter()

    private let fileManager = FileManager.default
    private let baseDirectory: URL

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDirectory = documents.appendingPathComponent("SharedAudio")
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    /// Imports a shared audio file and returns the created Episode
    @discardableResult
    func importFile(from url: URL) -> Episode? {
        let filename = url.lastPathComponent
        let folderURL = baseDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let destURL = folderURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: url, to: destURL)

            let episode = Episode(
                id: UUID(),
                title: url.deletingPathExtension().lastPathComponent,
                artworkURL: nil,
                audioURL: destURL,
                description: nil,
                played: false,
                podcastID: nil,
                publishedDate: Date(),
                localFileURL: destURL,
                playbackPosition: 0
            )

            EpisodeViewModel.shared.addEpisodes([episode])
            QueueViewModel.shared.addToQueue(episode)
            return episode
        } catch {
            print("❌ Failed to import shared audio: \(error)")
            return nil
        }
    }
}

