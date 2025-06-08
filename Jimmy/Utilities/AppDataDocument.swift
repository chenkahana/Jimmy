import SwiftUI
import UniformTypeIdentifiers

struct AppData: Codable {
    var podcasts: [Podcast]
    var episodes: [Episode]
    var queue: [Episode]
    var settings: [String: AnyCodable]
}

struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let string = try? container.decode(String.self) { value = string }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type") }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let string as String: try container.encode(string)
        default: throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

struct AppDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var appData: AppData
    init(appData: AppData) { self.appData = appData }
    init() {
        let podcasts = PodcastService.shared.loadPodcasts()
        let episodes = EpisodeViewModel.shared.episodes
        let queue = QueueViewModel.shared.queue
        let settings: [String: AnyCodable] = [
            "playbackSpeed": AnyCodable(UserDefaults.standard.double(forKey: "playbackSpeed")),
            "darkMode": AnyCodable(UserDefaults.standard.bool(forKey: "darkMode")),
            "episodeSwipeAction": AnyCodable(UserDefaults.standard.string(forKey: "episodeSwipeAction") ?? "addToQueue"),
            "queueSwipeAction": AnyCodable(UserDefaults.standard.string(forKey: "queueSwipeAction") ?? "markAsPlayed")
        ]
        self.appData = AppData(podcasts: podcasts, episodes: episodes, queue: queue, settings: settings)
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        self.appData = try decoder.decode(AppData.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(appData)
        return .init(regularFileWithContents: data)
    }
    static func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        let appData = try decoder.decode(AppData.self, from: data)
        print("🔄 iCloud Import: Restoring \(appData.podcasts.count) podcasts, \(appData.episodes.count) episodes, \(appData.queue.count) queue items")
        
        PodcastService.shared.savePodcasts(appData.podcasts)
        EpisodeViewModel.shared.addEpisodes(appData.episodes)
        QueueViewModel.shared.queue = appData.queue
        for (key, value) in appData.settings {
            if let double = value.value as? Double { UserDefaults.standard.set(double, forKey: key) }
            else if let bool = value.value as? Bool { UserDefaults.standard.set(bool, forKey: key) }
            else if let string = value.value as? String { UserDefaults.standard.set(string, forKey: key) }
        }
        
        print("✅ iCloud Import: Successfully restored data from iCloud")
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
            do {
                try importData(data)
            } catch {
                #if DEBUG
                print("⚠️ Failed to import iCloud data: \(error.localizedDescription)")
                #endif
            }
        }
    }
} 