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
        try? await EpisodeRepository.shared.addNewEpisodes(validAppData.episodes)
        
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
            QueueViewModel.shared.queuedEpisodes = validAppData.queue
        }
    }
    
    @MainActor
    func exportAppData() -> AppData {
        let episodes = LibraryViewModel.shared.allEpisodes
        let podcasts = PodcastService.shared.loadPodcasts()
        let queue = QueueViewModel.shared.queuedEpisodes
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
        try? await EpisodeRepository.shared.addNewEpisodes(appData.episodes)
        
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
            QueueViewModel.shared.queuedEpisodes = appData.queue
        }
    }
}

extension AppDataDocument {
    static let iCloudKey = "AppDataDocument.iCloudBackup"
    
    static func saveToICloudIfEnabled() {
        // Check if iCloud sync is enabled in settings
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else {
            return
        }
        
        // Additional check: verify iCloud capability is available
        guard iCloudKeyValueStoreAvailable() else {
            #if DEBUG
            print("⚠️ iCloud Key-Value Store not available - skipping backup")
            #endif
            return
        }
        
        // Save to iCloud Key-Value Store
        saveToiCloudKeyValueStore()
    }
    
    static func loadFromICloudIfEnabled() {
        // Check if iCloud sync is enabled in settings
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else {
            return
        }
        
        // Additional check: verify iCloud capability is available
        guard iCloudKeyValueStoreAvailable() else {
            #if DEBUG
            print("⚠️ iCloud Key-Value Store not available - skipping restore")
            #endif
            return
        }
        
        // Load from iCloud Key-Value Store
        loadFromiCloudKeyValueStore()
    }
    
    // MARK: - iCloud Capability Check
    private static func iCloudKeyValueStoreAvailable() -> Bool {
        // For development/debug builds, skip the entitlement check and just check if iCloud is available
        #if DEBUG
        // Check if iCloud is available on the device
        let ubiquityToken = FileManager.default.ubiquityIdentityToken
        
        if ubiquityToken == nil {
            print("⚠️ iCloud not available: ubiquityIdentityToken is nil")
            print("   This could mean:")
            print("   - Not signed into iCloud")
            print("   - iCloud Drive is disabled in Settings")
            print("   - iCloud Key-Value Store is disabled for this app")
            return false
        }
        
        // Additional check: try to see if we can access NSUbiquitousKeyValueStore
        do {
            let store = NSUbiquitousKeyValueStore.default
            // Just try to get the synchronization status - this will fail if iCloud KVS isn't available
            _ = store.dictionaryRepresentation
            print("✓ iCloud Key-Value Store appears to be available")
            return true
        } catch {
            print("⚠️ iCloud Key-Value Store not accessible: \(error.localizedDescription)")
            return false
        }
        #else
        // In release builds, check both entitlement and iCloud availability
        guard Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.ubiquity-kvstore-identifier") != nil else {
            return false
        }
        
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return false
        }
        
        return true
        #endif
    }
    
    // MARK: - iCloud Implementation
    private static func saveToiCloudKeyValueStore() {
        // Check if iCloud is available before accessing NSUbiquitousKeyValueStore
        guard FileManager.default.ubiquityIdentityToken != nil else {
            #if DEBUG
            print("⚠️ iCloud is not available - skipping backup")
            #endif
            return
        }
        
        DispatchQueue.global(qos: .utility).async {
            do {
                let doc = AppDataDocument()
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(doc.appData) {
                    let kvStore = NSUbiquitousKeyValueStore.default
                    kvStore.set(data, forKey: iCloudKey)
                    
                    // Don't call synchronize() as it's blocking - let the system handle sync timing
                    // kvStore.synchronize()
                    

                }
            } catch {
                #if DEBUG
                DispatchQueue.main.async {
                    print("⚠️ Failed to save to iCloud: \(error.localizedDescription)")
                }
                #endif
            }
        }
    }
    
    private static func loadFromiCloudKeyValueStore() {
        // Check if iCloud is available before accessing NSUbiquitousKeyValueStore
        guard FileManager.default.ubiquityIdentityToken != nil else {
            #if DEBUG
            print("⚠️ iCloud is not available - skipping restore")
            #endif
            return
        }
        
        let kvStore = NSUbiquitousKeyValueStore.default
        if let data = kvStore.data(forKey: iCloudKey) {
            Task {
                do {
                    try await importData(data)
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to import iCloud data: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }
} 