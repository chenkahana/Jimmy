import Foundation
import GRDB
import Combine
import OSLog

/// GRDB-based Repository following CHAT_HELP.md specification
/// Uses WAL mode for zero-lock readers and barrier writes for thread safety
/// 
/// GRDB dependency is configured in Jimmy.xcodeproj:
/// - Package: https://github.com/groue/GRDB.swift
/// - Version: Up to Next Major (6.0.0)
final class PodcastRepository: ObservableObject, @unchecked Sendable {
    static let shared = PodcastRepository()
    
    // MARK: - Published Properties
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    private let dbQueue: DatabaseQueue
    private let changeSubject = PassthroughSubject<EpisodeChanges, Never>()
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "PodcastRepository")
    #endif
    
    // MARK: - Change Notifications
    var changesPublisher: AnyPublisher<EpisodeChanges, Never> {
        changeSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    private init() {
        #if canImport(OSLog)
        logger.info("🗄️ Initializing PodcastRepository with GRDB database")
        #endif
        
        do {
            // Setup database with WAL mode
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dbPath = documentsPath.appendingPathComponent("podcast.db").path
            
            var config = Configuration()
            config.prepareDatabase { db in
                // Enable WAL mode for zero-lock readers
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                try db.execute(sql: "PRAGMA synchronous=NORMAL")
                try db.execute(sql: "PRAGMA cache_size=10000")
                try db.execute(sql: "PRAGMA temp_store=MEMORY")
            }
            
            dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
            
            // Create tables
            try dbQueue.write { db in
                try db.create(table: "episodes", ifNotExists: true) { t in
                    t.column("id", .text).primaryKey()
                    t.column("title", .text).notNull()
                    t.column("description", .text)
                    t.column("audioURL", .text)
                    t.column("artworkURL", .text)
                    t.column("publishedDate", .datetime)
                    t.column("duration", .integer)
                    t.column("podcastID", .text)
                    t.column("played", .boolean).defaults(to: false)
                    t.column("playbackPosition", .double).defaults(to: 0.0)
                    t.column("localFileURL", .text)
                    t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
                    t.column("updatedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
                }
                
                try db.create(index: "idx_episodes_podcast_id", on: "episodes", columns: ["podcastID"], ifNotExists: true)
                try db.create(index: "idx_episodes_published_date", on: "episodes", columns: ["publishedDate"], ifNotExists: true)
            }
            
            #if canImport(OSLog)
            logger.info("✅ GRDB Repository initialized with WAL mode")
            #endif
            
        } catch {
            fatalError("Failed to initialize GRDB database: \(error)")
        }
    }
    
    // MARK: - Read Operations (Concurrent)
    
    /// Fetch cached episodes (concurrent read)
    func fetchCachedEpisodes() async -> [Episode] {
        return await withCheckedContinuation { continuation in
            dbQueue.asyncRead { result in
                do {
                    let db = try result.get()
                    let episodes = try Episode.fetchAll(db)
                    continuation.resume(returning: episodes)
                } catch {
                    #if canImport(OSLog)
                    self.logger.error("❌ Failed to fetch episodes: \(error.localizedDescription)")
                    #endif
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Get episodes for specific podcast
    func getEpisodes(for podcastID: UUID) async -> [Episode] {
        return await withCheckedContinuation { continuation in
            dbQueue.asyncRead { result in
                do {
                    let db = try result.get()
                    let episodes = try Episode
                        .filter(Column("podcastID") == podcastID.uuidString)
                        .fetchAll(db)
                    continuation.resume(returning: episodes)
                } catch {
                    #if canImport(OSLog)
                    self.logger.error("❌ Failed to fetch episodes for podcast \(podcastID): \(error.localizedDescription)")
                    #endif
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // MARK: - Write Operations (Barrier)
    
    /// Apply episode changes with barrier write
    func applyChanges(_ changes: EpisodeChanges) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.asyncWrite({ db in
                // Apply inserts
                for var episode in changes.inserted {
                    try episode.insert(db)
                }
                
                // Apply updates
                for var episode in changes.updated {
                    try episode.update(db)
                }
                
                // Apply deletes
                for episodeID in changes.deleted {
                    try Episode.deleteOne(db, key: episodeID.uuidString)
                }
                
                #if canImport(OSLog)
                self.logger.info("✅ Applied changes: \(changes.inserted.count) inserted, \(changes.updated.count) updated, \(changes.deleted.count) deleted")
                #endif
                
            }, completion: { _, result in
                switch result {
                case .success:
                    // Notify observers
                    DispatchQueue.main.async {
                        self.changeSubject.send(changes)
                    }
                case .failure(let error):
                    #if canImport(OSLog)
                    self.logger.error("❌ Failed to apply changes: \(error.localizedDescription)")
                    #endif
                }
                
                continuation.resume()
            })
        }
    }
    
    /// Update episodes with diff-merge
    func updateEpisodes(_ newEpisodes: [Episode]) async {
        let currentEpisodes = await fetchCachedEpisodes()
        let changes = computeDiff(current: currentEpisodes, new: newEpisodes)
        
        if !changes.isEmpty {
            await applyChanges(changes)
            
            // Update published property on main thread
            await MainActor.run {
                self.episodes = newEpisodes
            }
        }
    }
    
    // MARK: - Diff Computation
    
    private func computeDiff(current: [Episode], new: [Episode]) -> EpisodeChanges {
        let currentDict = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let newDict = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        
        let inserted = new.filter { currentDict[$0.id] == nil }
        let deleted = current.compactMap { currentDict[$0.id] != nil && newDict[$0.id] == nil ? $0.id : nil }
        let updated = new.filter { episode in
            if let currentEpisode = currentDict[episode.id] {
                return !episode.isEqual(to: currentEpisode)
            }
            return false
        }
        
        return EpisodeChanges(inserted: inserted, updated: updated, deleted: deleted)
    }
}

// MARK: - Episode Changes Model

struct EpisodeChanges {
    let inserted: [Episode]
    let updated: [Episode] 
    let deleted: [UUID]
    
    var isEmpty: Bool {
        inserted.isEmpty && updated.isEmpty && deleted.isEmpty
    }
}

// MARK: - Episode Extensions (for GRDB compatibility)

extension Episode {
    func isEqual(to other: Episode) -> Bool {
        return id == other.id &&
               title == other.title &&
               description == other.description &&
               audioURL == other.audioURL &&
               publishedDate == other.publishedDate &&
               duration == other.duration &&
               played == other.played &&
               abs(playbackPosition - other.playbackPosition) < 0.1
    }
}

// MARK: - GRDB Extensions

extension Episode: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "episodes"
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let description = Column(CodingKeys.description)
        static let audioURL = Column(CodingKeys.audioURL)
        static let artworkURL = Column(CodingKeys.artworkURL)
        static let publishedDate = Column(CodingKeys.publishedDate)
        static let duration = Column(CodingKeys.duration)
        static let podcastID = Column(CodingKeys.podcastID)
        static let played = Column(CodingKeys.played)
        static let playbackPosition = Column(CodingKeys.playbackPosition)
        static let localFileURL = Column(CodingKeys.localFileURL)
    }
    
    // Customize database encoding/decoding
    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.title] = title
        container[Columns.description] = description
        container[Columns.audioURL] = audioURL?.absoluteString
        container[Columns.artworkURL] = artworkURL?.absoluteString
        container[Columns.publishedDate] = publishedDate
        container[Columns.duration] = duration
        container[Columns.podcastID] = podcastID?.uuidString
        container[Columns.played] = played
        container[Columns.playbackPosition] = playbackPosition
        container[Columns.localFileURL] = localFileURL?.absoluteString
    }
    
    init(row: Row) {
        id = UUID(uuidString: row[Columns.id]) ?? UUID()
        title = row[Columns.title]
        description = row[Columns.description]
        let audioURLString: String? = row[Columns.audioURL]
        audioURL = audioURLString.flatMap(URL.init(string:))
        let artworkURLString: String? = row[Columns.artworkURL]
        artworkURL = artworkURLString.flatMap(URL.init(string:))
        publishedDate = row[Columns.publishedDate]
        duration = row[Columns.duration]
        let podcastIDString: String? = row[Columns.podcastID]
        podcastID = podcastIDString.flatMap(UUID.init(uuidString:))
        played = row[Columns.played]
        playbackPosition = row[Columns.playbackPosition]
        let localFileURLString: String? = row[Columns.localFileURL]
        localFileURL = localFileURLString.flatMap(URL.init(string:))
    }
} 