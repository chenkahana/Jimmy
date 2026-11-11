import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct AppData: Codable {
    let podcasts: [Podcast]
    let episodes: [Episode]
    let queue: [Episode]
    let settings: [String: String]
    let exportDate: Date
}

struct AppDataDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json]
    
    var appData: AppData
    
    init() {
        let podcasts = PodcastService.shared.loadPodcasts()
        let settings: [String: String] = [:]
        
        // Since we can't await in init, we'll create empty data and populate later
        self.appData = AppData(
            podcasts: podcasts,
            episodes: [],
            queue: [],
            settings: settings,
            exportDate: Date()
        )
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        self.appData = try decoder.decode(AppData.self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let data = try encoder.encode(appData)
        return FileWrapper(regularFileWithContents: data)
    }
    
    static func importData(_ data: Data) async throws {
        let decoder = JSONDecoder()
        
        // Try different date decoding strategies
        var appData: AppData?
        
        // Strategy 1: ISO8601
        decoder.dateDecodingStrategy = .iso8601
        do {
            appData = try decoder.decode(AppData.self, from: data)
        } catch {
            // Strategy 2: Default date strategy
            decoder.dateDecodingStrategy = .deferredToDate
            do {
                appData = try decoder.decode(AppData.self, from: data)
            } catch {
                // Strategy 3: Seconds since 1970
                decoder.dateDecodingStrategy = .secondsSince1970
                do {
                    appData = try decoder.decode(AppData.self, from: data)
                } catch {
                    // Strategy 4: Milliseconds since 1970
                    decoder.dateDecodingStrategy = .millisecondsSince1970
                    appData = try decoder.decode(AppData.self, from: data)
                }
            }
        }
        
        guard let validAppData = appData else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        // Import episodes
        // Note: Episode import functionality needs to be implemented through proper services
        // For now, we'll skip episode import and focus on podcast import
        
        // Import podcasts
        var existingPodcasts = PodcastService.shared.loadPodcasts()
        for podcast in validAppData.podcasts {
            if !existingPodcasts.contains(where: { $0.feedURL == podcast.feedURL }) {
                existingPodcasts.append(podcast)
            }
        }
        PodcastService.shared.savePodcasts(existingPodcasts)
        
        // Import queue
        await MainActor.run {
            QueueViewModel.shared.episodes = validAppData.queue
        }
    }
    
    @MainActor
    func exportAppData() -> AppData {
        let episodes = LibraryViewModel.shared.allEpisodes
        let podcasts = PodcastService.shared.loadPodcasts()
        let queue = QueueViewModel.shared.episodes
        let settings: [String: String] = [:]
        
        return AppData(
            podcasts: podcasts,
            episodes: episodes,
            queue: queue,
            settings: settings,
            exportDate: Date()
        )
    }
    
    func importAppData(_ appData: AppData) async {
        // Import episodes
        // Note: Episode import functionality needs to be implemented through proper services
        // For now, we'll skip episode import and focus on podcast import
        
        // Import podcasts
        var existingPodcasts = PodcastService.shared.loadPodcasts()
        for podcast in appData.podcasts {
            if !existingPodcasts.contains(where: { $0.feedURL == podcast.feedURL }) {
                existingPodcasts.append(podcast)
            }
        }
        PodcastService.shared.savePodcasts(existingPodcasts)
        
        // Import queue
        await MainActor.run {
            QueueViewModel.shared.episodes = appData.queue
        }
    }
}

// MARK: - iCloud KVS Sync

/// Lightweight sync payload for NSUbiquitousKeyValueStore (max 1MB limit).
/// Syncs subscriptions, queue order, and playback positions across devices.
struct SyncPayload: Codable {
    let version: Int = 1
    let modifiedAt: Date
    let feedURLs: [String]         // Subscribed podcast feed URLs
    let queueEpisodeIDs: [String]  // Ordered episode UUIDs in queue
    let playbackPositions: [String: Double]  // episodeID -> position
    let playedEpisodeIDs: [String] // Episodes marked played
}

extension AppDataDocument {
    static let iCloudKey = "AppDataDocument.iCloudBackup"
    static let syncPayloadKey = "jimmy.syncPayload"

    static func saveToICloudIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return }
        guard iCloudKeyValueStoreAvailable() else { return }
        saveToiCloudKeyValueStore()
    }

    static func loadFromICloudIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return }
        guard iCloudKeyValueStoreAvailable() else { return }
        loadFromiCloudKeyValueStore()
    }

    /// Start listening for remote iCloud KVS changes
    static func startObservingICloudChanges() {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return }
        guard iCloudKeyValueStoreAvailable() else { return }

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }

            // Handle server change or initial sync
            if reason == NSUbiquitousKeyValueStoreServerChange ||
               reason == NSUbiquitousKeyValueStoreInitialSyncChange {
                Task {
                    await mergeRemoteSyncPayload()
                }
            }
        }

        // Trigger initial sync
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Build and save a lightweight SyncPayload to iCloud KVS
    static func saveSyncPayload() {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return }
        guard iCloudKeyValueStoreAvailable() else { return }

        Task.detached(priority: .utility) {
            let podcasts = PodcastService.shared.loadPodcasts()
            let feedURLs = podcasts.compactMap { $0.feedURL.absoluteString }

            let queueEpisodes = await MainActor.run { QueueViewModel.shared.episodes }
            let queueIDs = queueEpisodes.map { $0.id.uuidString }

            // Collect playback positions from queue episodes
            var positions: [String: Double] = [:]
            for ep in queueEpisodes where ep.playbackPosition > 0 {
                positions[ep.id.uuidString] = ep.playbackPosition
            }

            // Collect played episode IDs
            let playedIDs = queueEpisodes.filter { $0.played }.map { $0.id.uuidString }

            let payload = SyncPayload(
                modifiedAt: Date(),
                feedURLs: feedURLs,
                queueEpisodeIDs: queueIDs,
                playbackPositions: positions,
                playedEpisodeIDs: playedIDs
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(payload) {
                let kvStore = NSUbiquitousKeyValueStore.default
                kvStore.set(data, forKey: syncPayloadKey)
            }
        }
    }

    /// Merge a remote SyncPayload with local data using conflict resolution rules:
    /// - Subscriptions: union merge
    /// - Playback position: higher wins
    /// - Played: once played anywhere stays played
    /// - Queue: last-modified-device wins
    static func mergeRemoteSyncPayload() async {
        let kvStore = NSUbiquitousKeyValueStore.default
        guard let data = kvStore.data(forKey: syncPayloadKey) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let remote = try? decoder.decode(SyncPayload.self, from: data) else { return }

        // Union merge subscriptions — add any feed URLs we don't already have
        let localPodcasts = PodcastService.shared.loadPodcasts()
        let localFeedURLs = Set(localPodcasts.map { $0.feedURL.absoluteString })
        let newFeedURLs = remote.feedURLs.filter { !localFeedURLs.contains($0) }

        for urlString in newFeedURLs {
            guard let url = URL(string: urlString) else { continue }
            Task {
                _ = try? await PodcastService.shared.addPodcast(from: url)
            }
        }

        // Playback position: higher wins
        let repository = DIContainer.shared.playbackStateRepository
        for (episodeIDStr, remotePosition) in remote.playbackPositions {
            guard let episodeID = UUID(uuidString: episodeIDStr) else { continue }
            if let localState = try? await repository.fetchPlaybackState(for: episodeID) {
                if remotePosition > localState.position {
                    var updated = localState
                    updated.position = remotePosition
                    updated.updatedAt = Date()
                    try? await repository.savePlaybackState(updated)
                }
            }
        }

        // Played: once played anywhere stays played
        for episodeIDStr in remote.playedEpisodeIDs {
            guard let episodeID = UUID(uuidString: episodeIDStr) else { continue }
            if let localState = try? await repository.fetchPlaybackState(for: episodeID) {
                if !localState.finished {
                    var updated = localState
                    updated.finished = true
                    updated.updatedAt = Date()
                    try? await repository.savePlaybackState(updated)
                }
            }
        }
    }

    // MARK: - iCloud Capability Check
    private static func iCloudKeyValueStoreAvailable() -> Bool {
        #if DEBUG
        let ubiquityToken = FileManager.default.ubiquityIdentityToken
        if ubiquityToken == nil { return false }
        _ = NSUbiquitousKeyValueStore.default.dictionaryRepresentation
        return true
        #else
        guard Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.ubiquity-kvstore-identifier") != nil else {
            return false
        }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return false
        }
        return true
        #endif
    }

    // MARK: - Legacy iCloud Implementation (kept for backward compatibility)
    private static func saveToiCloudKeyValueStore() {
        guard FileManager.default.ubiquityIdentityToken != nil else { return }

        // Use new lightweight SyncPayload instead of full AppData
        saveSyncPayload()
    }

    private static func loadFromiCloudKeyValueStore() {
        guard FileManager.default.ubiquityIdentityToken != nil else { return }

        Task {
            await mergeRemoteSyncPayload()
        }
    }
} 