import Foundation

/// Use case for importing audio files into the app
struct ImportAudioFileUseCase {
    private let episodeRepository: EpisodeRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    private let storageRepository: StorageRepositoryProtocol
    
    init(
        episodeRepository: EpisodeRepositoryProtocol,
        podcastRepository: PodcastRepositoryProtocol,
        storageRepository: StorageRepositoryProtocol
    ) {
        self.episodeRepository = episodeRepository
        self.podcastRepository = podcastRepository
        self.storageRepository = storageRepository
    }
    
    func execute(
        fileURL: URL,
        fileName: String,
        showName: String,
        existingShowID: UUID?
    ) async throws -> Episode {
        
        // Get or create podcast
        let podcast: Podcast
        if let existingShowID = existingShowID {
            let allPodcasts = try await podcastRepository.fetchPodcasts()
            if let existingPodcast = allPodcasts.first(where: { $0.id == existingShowID }) {
                podcast = existingPodcast
            } else {
                // Create new podcast if existing one not found
                podcast = createPodcast(showName: showName)
                try await podcastRepository.savePodcasts([podcast])
            }
        } else {
            // Create new podcast
            podcast = createPodcast(showName: showName)
            var allPodcasts = try await podcastRepository.fetchPodcasts()
            allPodcasts.append(podcast)
            try await podcastRepository.savePodcasts(allPodcasts)
        }
        
        // Copy file to app's documents directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsURL.appendingPathComponent("ImportedAudio").appendingPathComponent(fileName)
        
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Copy file
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        
        // Create episode
        let episode = Episode(
            id: UUID(),
            title: fileName.replacingOccurrences(of: ".\(fileURL.pathExtension)", with: ""),
            artworkURL: nil,
            audioURL: destinationURL,
            description: "Imported audio file",
            played: false,
            podcastID: podcast.id,
            publishedDate: Date(),
            localFileURL: destinationURL,
            playbackPosition: 0
        )
        
        // Save episode
        var allEpisodes = try await episodeRepository.fetchAllEpisodes()
        allEpisodes.append(episode)
        try await episodeRepository.saveEpisodes(allEpisodes)
        
        return episode
    }
    
    private func createPodcast(showName: String) -> Podcast {
        return Podcast(
            id: UUID(),
            title: showName,
            author: "Imported",
            description: "Imported audio files",
            feedURL: URL(string: "file://imported")!,
            artworkURL: nil
        )
    }
} 