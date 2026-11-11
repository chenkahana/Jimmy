import Foundation

/// Use case for importing audio files into the app
struct ImportAudioFileUseCase {
    private let episodeRepository: EpisodeRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    
    init(
        episodeRepository: EpisodeRepositoryProtocol,
        podcastRepository: PodcastRepositoryProtocol,
        playbackStateRepository: PlaybackStateRepositoryProtocol
    ) {
        self.episodeRepository = episodeRepository
        self.podcastRepository = podcastRepository
        self.playbackStateRepository = playbackStateRepository
    }
    
    func execute(
        fileURL: URL,
        fileName: String,
        showName: String,
        existingShowID: UUID?
    ) async throws -> Episode {
        let podcast = try await getOrCreatePodcast(showName: showName, existingShowID: existingShowID)

        let destinationURL = try copyFileToAppDocuments(fileURL: fileURL, fileName: fileName)
        
        // Generate deterministic UUID based on podcast feed URL and episode data
        let episodeTitle = fileName.replacingOccurrences(of: ".\(fileURL.pathExtension)", with: "")
        let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: podcast.feedURL,
            audioURL: destinationURL,
            title: episodeTitle,
            publishedDate: Date()
        )
        
        let episode = Episode(
            id: deterministicID,
            title: episodeTitle,
            podcastID: podcast.id,
            publishedDate: Date(),
            duration: 0, // Should be determined later
            artworkURL: nil,
            description: "Imported audio file",
            audioURL: destinationURL
        )
        
        let episodeWithState = EpisodeWithPlaybackState(
            episode: episode,
            playbackState: PlaybackState(episodeID: episode.id, position: 0, finished: false)
        )
        
        try await episodeRepository.saveEpisodes([episodeWithState], for: podcast.id)
        
        return episode
    }
    
    private func getOrCreatePodcast(showName: String, existingShowID: UUID?) async throws -> Podcast {
        if let existingShowID = existingShowID,
                       let existingPodcast = try await podcastRepository.fetchPodcast(id: existingShowID, ignoreCache: false) {
            return existingPodcast
        }
        
        let newPodcast = Podcast(
            id: UUID(),
            title: showName,
            author: "Imported",
            description: "Imported audio files",
            feedURL: URL(string: "file://imported")!,
            artworkURL: nil
        )
        try await podcastRepository.addPodcast(newPodcast)
        return newPodcast
    }
    
    private func copyFileToAppDocuments(fileURL: URL, fileName: String) throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsURL.appendingPathComponent("ImportedAudio").appendingPathComponent(fileName)
        
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        
        return destinationURL
    }
} 