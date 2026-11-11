import Foundation
import UniformTypeIdentifiers
import os

/// Errors that can occur during audio file import
enum SharedAudioImporterError: Error {
    case podcastCreationFailed
    case episodeCreationFailed
    case fileOperationFailed
}

/// Handles importing audio files shared to the app
class SharedAudioImporter: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SharedAudioImporter")
    static let shared = SharedAudioImporter()

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let episodeRepository: EpisodeRepositoryProtocol
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    
    // Published property for Combine-based UI updates
    @Published var pendingURL: URL?
    
    // Callback for when a file needs naming
    var onFileRequiresNaming: ((URL) -> Void)?
    
    // Callback for file import with clean architecture
    private var importCallback: ((URL, String, String, UUID?) async -> Void)?

    private init(
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        playbackStateRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository,
        podcastRepository: PodcastRepositoryProtocol = DIContainer.shared.podcastRepository
    ) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseDirectory = documents.appendingPathComponent("SharedAudio")
        self.episodeRepository = episodeRepository
        self.playbackStateRepository = playbackStateRepository
        self.podcastRepository = podcastRepository
        
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    /// Set callback for clean architecture file import
    func setImportCallback(_ callback: @escaping (URL, String, String, UUID?) async -> Void) {
        importCallback = callback
    }

    /// Triggers the naming popup for a shared audio file
    func handleSharedFile(from url: URL) {
        Task { @MainActor in
            self.pendingURL = url
        }
        onFileRequiresNaming?(url)
    }

    /// Imports a shared audio file with custom name and show and returns the created Episode
    @discardableResult
    func importFile(from url: URL, fileName: String, showName: String, existingShowID: UUID?) async -> Episode? {
        do {
            // Step 1: Get or create podcast and ensure it's committed to database
            let podcast = try await getOrCreatePodcast(showName: showName, existingShowID: existingShowID)
            
            // Step 2: Copy the file to app storage
            let fileExtension = url.pathExtension
            let customFileName = fileName + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
            
            let showFolderURL = baseDirectory.appendingPathComponent(podcast.title)
            try fileManager.createDirectory(at: showFolderURL, withIntermediateDirectories: true)
            
            let destURL = showFolderURL.appendingPathComponent(customFileName)
            
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            
            try fileManager.copyItem(at: url, to: destURL)

            // Step 3: Create episode with deterministic UUID based on file path
            let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
                feedURL: podcast.feedURL,
                audioURL: destURL,
                title: fileName,
                publishedDate: Date()
            )
            
            let episode = Episode(
                id: deterministicID,
                title: fileName,
                podcastID: podcast.id,
                publishedDate: Date(),
                duration: 0,
                artworkURL: nil,
                description: "Imported from shared file on \(Date().formatted(date: .abbreviated, time: .shortened))",
                audioURL: destURL
            )
            
            let playbackState = PlaybackState(
                episodeID: episode.id,
                position: 0,
                finished: false,
                updatedAt: Date()
            )
            
            // Step 4: Create EpisodeWithPlaybackState for repository
            let episodeWithPlayback = EpisodeWithPlaybackState(
                episode: episode,
                playbackState: playbackState
            )

            // Step 5: Save episode and playback state (podcast should already exist in DB)
            Self.logger.debug("Attempting to save episode for podcast ID: \(podcast.id)")
            let podcastIDStr = episode.podcastID?.uuidString ?? "nil"
            Self.logger.debug("Episode podcastID: \(podcastIDStr)")
            
            do {
                try await episodeRepository.saveEpisodes([episodeWithPlayback], for: podcast.id)
                try await playbackStateRepository.savePlaybackState(playbackState)
                Self.logger.info("Successfully saved episode and playback state")
            } catch {
                Self.logger.error("Failed to save episode: \(error)")
                throw SharedAudioImporterError.episodeCreationFailed
            }
            
            // Step 6: Clear the pending URL to dismiss the dialog
            await MainActor.run {
                self.pendingURL = nil
            }
            
            return episode
        } catch {
            Self.logger.error("Failed to import shared audio: \(error)")
            // Clear pending URL even on failure to dismiss dialog
            await MainActor.run {
                self.pendingURL = nil
            }
            return nil
        }
    }
    
    private func getOrCreatePodcast(showName: String, existingShowID: UUID?) async throws -> Podcast {
        // Try to use existing podcast if provided
        if let existingShowID = existingShowID,
           let podcast = try? await podcastRepository.fetchPodcast(id: existingShowID, ignoreCache: false) {
            return podcast
        }
        
        // Create new podcast
        let newShow = Podcast(
            id: UUID(),
            title: showName,
            author: "Local Files",
            description: "Custom show for imported audio files",
            feedURL: URL(string: "local://\(UUID().uuidString)")!,
            artworkURL: nil
        )
        
        // Add podcast to database and ensure it's committed
        try await podcastRepository.addPodcast(newShow)
        
        // Verify the podcast was saved by fetching it back
        guard let savedPodcast = try? await podcastRepository.fetchPodcast(id: newShow.id, ignoreCache: true) else {
            throw SharedAudioImporterError.podcastCreationFailed
        }
        
        return savedPodcast
    }

    /// Legacy method - now triggers the naming popup
    @discardableResult
    func importFile(from url: URL) -> Episode? {
        handleSharedFile(from: url)
        return nil
    }
}
