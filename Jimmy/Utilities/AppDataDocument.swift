import SwiftUI
import UniformTypeIdentifiers

struct AppData: Codable {
    var podcasts: [Podcast]
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
        let queue = QueueViewModel.shared.queue
        let settings: [String: AnyCodable] = [
            "playbackSpeed": AnyCodable(UserDefaults.standard.double(forKey: "playbackSpeed")),
            "darkMode": AnyCodable(UserDefaults.standard.bool(forKey: "darkMode")),
            "episodeSwipeAction": AnyCodable(UserDefaults.standard.string(forKey: "episodeSwipeAction") ?? "addToQueue"),
            "queueSwipeAction": AnyCodable(UserDefaults.standard.string(forKey: "queueSwipeAction") ?? "markAsPlayed")
        ]
        self.appData = AppData(podcasts: podcasts, queue: queue, settings: settings)
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
        PodcastService.shared.savePodcasts(appData.podcasts)
        QueueViewModel.shared.queue = appData.queue
        for (key, value) in appData.settings {
            if let double = value.value as? Double { UserDefaults.standard.set(double, forKey: key) }
            else if let bool = value.value as? Bool { UserDefaults.standard.set(bool, forKey: key) }
            else if let string = value.value as? String { UserDefaults.standard.set(string, forKey: key) }
        }
    }
}

extension AppDataDocument {
    static let iCloudKey = "AppDataDocument.iCloudBackup"
    static func saveToICloudIfEnabled() {
        if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
            let doc = AppDataDocument()
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(doc.appData) {
                NSUbiquitousKeyValueStore.default.set(data, forKey: iCloudKey)
                NSUbiquitousKeyValueStore.default.synchronize()
            }
        }
    }
    static func loadFromICloudIfEnabled() {
        if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
            if let data = NSUbiquitousKeyValueStore.default.data(forKey: iCloudKey) {
                try? importData(data)
            }
        }
    }
} 