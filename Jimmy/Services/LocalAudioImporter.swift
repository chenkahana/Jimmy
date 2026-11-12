import Foundation
import JimmyKit
import os

enum LocalAudioImportError: Error, LocalizedError {
    case unsupportedFormat
    case fileAccessDenied
    case storeNotReady

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This file format isn't supported for audio import."
        case .fileAccessDenied:
            return "Couldn't access the audio file."
        case .storeNotReady:
            return "The library isn't ready yet."
        }
    }
}

/// Imports an audio file shared to or opened by the app as an episode of a single, fixed
/// "Imported audio" local show in `AppModel`'s store — copied into the app container with a path
/// stored relative to it, so it never breaks if the container moves between launches.
///
/// Replaces `BulletproofAudioImporter` and `SharedAudioImporter`, which separately juggled
/// per-file show creation/selection, retries, and two overlapping progress models for what the
/// app only ever used as one plain file copy. Also fixes #86 (imported local-file episodes not
/// appearing in the episode list): this show's episodes are ordinary store-backed rows, so
/// `PodcastEpisodeListView` already shows them like any other podcast's.
@MainActor
final class LocalAudioImporter: ObservableObject {
    static let shared = LocalAudioImporter()
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LocalAudioImporter")

    /// Deterministic (same local feed URL every launch), so repeated imports land on one show.
    static let importedAudioFeedURL = URL(string: "jimmy-local://imported-audio")!
    static let importedAudioPodcastID = FeedIDs.generatePodcastID(from: importedAudioFeedURL)

    private static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg"]

    /// Set when a shared/opened file is waiting on the user to name it (presented by
    /// `AppShell`'s `LocalAudioImportView` sheet).
    @Published var pendingURL: URL?
    @Published var isImporting = false

    private let fileManager = FileManager.default

    private init() {}

    /// Shows the naming sheet for a file shared to or opened by the app. A no-op for a format
    /// `importFile` wouldn't accept anyway.
    func handleSharedFile(from url: URL) {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            Self.logger.error("Ignoring unsupported shared file: \(url.lastPathComponent, privacy: .public)")
            return
        }
        pendingURL = url
    }

    /// Copies `url` into the app container under the "Imported audio" show and inserts it into
    /// the store as a new episode with that title. Returns the created episode, or `nil` if the
    /// store isn't ready or the copy failed.
    @discardableResult
    func importFile(from url: URL, title: String) async -> JimmyKit.Episode? {
        guard let store = AppModel.current?.readyStore else {
            Self.logger.error("Import failed: \(LocalAudioImportError.storeNotReady.localizedDescription, privacy: .public)")
            return nil
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let audioURL = try copyIntoContainer(url, title: title)
            let podcast = JimmyKit.Podcast(
                id: Self.importedAudioPodcastID,
                title: "Imported audio",
                cleanTitle: "Imported audio",
                author: "Local Files",
                feedURL: Self.importedAudioFeedURL
            )
            let episode = JimmyKit.Episode(
                id: FeedIDs.generateEpisodeID(
                    feedURL: podcast.feedURL, audioURL: audioURL, title: title, publishedDate: Date()
                ),
                podcastID: podcast.id,
                title: title,
                audioURL: audioURL,
                publishedDate: Date(),
                description: "Imported audio file"
            )

            try await store.addLocalEpisode(episode, to: podcast)
            pendingURL = nil
            return episode
        } catch {
            Self.logger.error("Failed to import local audio file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Copies `url` into `Documents/ImportedAudio/`, disambiguating `title` from any file already
    /// there, and returns a URL with no scheme or host — just the path relative to the app
    /// container — for `AppModel`'s `resolveAudioURL` to resolve back at playback time.
    private func copyIntoContainer(_ url: URL, title: String) throws -> URL {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LocalAudioImportError.fileAccessDenied
        }
        let showDirectory = documentsDirectory.appendingPathComponent("ImportedAudio", isDirectory: true)
        try fileManager.createDirectory(at: showDirectory, withIntermediateDirectories: true)

        let fileExtension = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let baseName = sanitize(title)
        var fileName = "\(baseName).\(fileExtension)"
        var suffix = 1
        while fileManager.fileExists(atPath: showDirectory.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) (\(suffix)).\(fileExtension)"
            suffix += 1
        }
        let destinationURL = showDirectory.appendingPathComponent(fileName)

        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        try fileManager.copyItem(at: url, to: destinationURL)

        let relativePath = "ImportedAudio/\(fileName)"
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        guard let relativeURL = URL(string: encodedPath) else {
            throw LocalAudioImportError.fileAccessDenied
        }
        return relativeURL
    }

    private func sanitize(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:*?\"<>|")
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
        return cleaned.isEmpty ? "Imported Audio" : cleaned
    }
}
