import Foundation
import UniformTypeIdentifiers

/// Handles importing audio files shared to the app
class SharedAudioImporter: ObservableObject {
    static let shared = SharedAudioImporter()

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    
    // Callback for when a file needs naming
    var onFileRequiresNaming: ((URL) -> Void)?

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDirectory = documents.appendingPathComponent("SharedAudio")
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    /// Triggers the naming popup for a shared audio file
    func handleSharedFile(from url: URL) {
        onFileRequiresNaming?(url)
    }

    /// Imports a shared audio file with custom name and show and returns the created Episode
    @discardableResult
    func importFile(from url: URL, fileName: String, showName: String, existingShowID: UUID?) -> Episode? {
        let fileExtension = url.pathExtension
        let customFileName = fileName + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        
        // Create or get the show
        let showID: UUID
        if let existingID = existingShowID {
            showID = existingID
        } else {
            // Create a new local show
            showID = createLocalShow(named: showName)
        }
        
        // Create folder structure: SharedAudio/ShowName/
        let showFolderURL = baseDirectory.appendingPathComponent(showName)
        do {
            try fileManager.createDirectory(at: showFolderURL, withIntermediateDirectories: true)
            let destURL = showFolderURL.appendingPathComponent(customFileName)
            
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            
            // Copy the file
            try fileManager.copyItem(at: url, to: destURL)

            let episode = Episode(
                id: UUID(),
                title: fileName,
                artworkURL: nil,
                audioURL: destURL,
                description: "Imported from shared file on \(Date().formatted(date: .abbreviated, time: .shortened))",
                played: false,
                podcastID: showID,
                publishedDate: Date(),
                localFileURL: destURL,
                playbackPosition: 0
            )

            EpisodeViewModel.shared.addEpisodes([episode])
            // Don't automatically add to queue - let user decide
            return episode
        } catch {
            print("❌ Failed to import shared audio: \(error)")
            return nil
        }
    }
    
    /// Creates a new local show and returns its ID
    private func createLocalShow(named showName: String) -> UUID {
        let localURL = URL(string: "local://\(UUID().uuidString)")!
        
        let newShow = Podcast(
            id: UUID(),
            title: showName,
            author: "Local Files",
            description: "Custom show for imported audio files",
            feedURL: localURL,
            artworkURL: nil,
            autoAddToQueue: false,
            notificationsEnabled: false,
            lastEpisodeDate: Date()
        )
        
        // Save the show
        var podcasts = PodcastService.shared.loadPodcasts()
        podcasts.append(newShow)
        PodcastService.shared.savePodcasts(podcasts)
        
        return newShow.id
    }

    /// Legacy method - now triggers the naming popup
    @discardableResult
    func importFile(from url: URL) -> Episode? {
        handleSharedFile(from: url)
        return nil
    }
}

