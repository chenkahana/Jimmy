import Foundation
import Combine

/// ViewModel for Queue functionality following MVVM patterns
@MainActor
class QueueViewModel: ObservableObject {
    static let shared = QueueViewModel()
    
    // MARK: - Published Properties
    @Published var queuedEpisodes: [Episode] = []
    @Published var currentEpisode: Episode?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let audioPlayerService: AudioPlayerService
    private let cacheService: EpisodeCacheService
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.audioPlayerService = AudioPlayerService.shared
        self.cacheService = EpisodeCacheService.shared
        setupBindings()
        loadQueue()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Bind to audio player current episode
        audioPlayerService.$currentEpisode
            .assign(to: \.currentEpisode, on: self)
            .store(in: &cancellables)
    }
    
    private func loadQueue() {
        // Load queue from persistent storage
        if let data = UserDefaults.standard.data(forKey: "episode_queue"),
           let episodes = try? JSONDecoder().decode([Episode].self, from: data) {
            queuedEpisodes = episodes
        }
    }
    
    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(queuedEpisodes)
            UserDefaults.standard.set(data, forKey: "episode_queue")
        } catch {
            errorMessage = "Failed to save queue: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Public Methods
    func addEpisode(_ episode: Episode) async throws {
        guard !queuedEpisodes.contains(where: { $0.id == episode.id }) else {
            throw QueueError.episodeAlreadyInQueue
        }
        
        queuedEpisodes.append(episode)
        saveQueue()
    }
    
    func addEpisodeToTop(_ episode: Episode) async throws {
        guard !queuedEpisodes.contains(where: { $0.id == episode.id }) else {
            throw QueueError.episodeAlreadyInQueue
        }
        
        queuedEpisodes.insert(episode, at: 0)
        saveQueue()
    }
    
    func removeEpisode(_ episode: Episode) async throws {
        queuedEpisodes.removeAll { $0.id == episode.id }
        saveQueue()
    }
    
    func removeEpisode(at index: Int) async throws {
        guard index < queuedEpisodes.count else {
            throw QueueError.invalidIndex
        }
        
        queuedEpisodes.remove(at: index)
        saveQueue()
    }
    
    func moveEpisode(from source: IndexSet, to destination: Int) {
        queuedEpisodes.move(fromOffsets: source, toOffset: destination)
        saveQueue()
    }
    
    func playEpisode(_ episode: Episode) async {
        audioPlayerService.loadEpisode(episode)
        audioPlayerService.play()
        errorMessage = nil
    }
    
    func playEpisode(at index: Int) async {
        guard index < queuedEpisodes.count else { return }
        let episode = queuedEpisodes[index]
        await playEpisode(episode)
    }
    
    func playNext() async {
        guard !queuedEpisodes.isEmpty else { return }
        
        let nextEpisode = queuedEpisodes.removeFirst()
        saveQueue()
        await playEpisode(nextEpisode)
    }
    
    func clearQueue() {
        queuedEpisodes.removeAll()
        saveQueue()
    }
    
    func shuffleQueue() {
        queuedEpisodes.shuffle()
        saveQueue()
    }
    
    func getNextEpisode() -> Episode? {
        return queuedEpisodes.first
    }
    
    func removeCurrentEpisode() {
        if !queuedEpisodes.isEmpty {
            queuedEpisodes.removeFirst()
            saveQueue()
        }
    }
    
    // MARK: - Computed Properties
    var isEmpty: Bool {
        queuedEpisodes.isEmpty
    }
    
    var count: Int {
        queuedEpisodes.count
    }
    
    var totalDuration: TimeInterval {
        queuedEpisodes.reduce(0) { $0 + ($1.duration ?? 0) }
    }
    
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Supporting Types
enum QueueError: LocalizedError {
    case episodeAlreadyInQueue
    case invalidIndex
    case emptyQueue
    
    var errorDescription: String? {
        switch self {
        case .episodeAlreadyInQueue:
            return "Episode is already in the queue"
        case .invalidIndex:
            return "Invalid queue index"
        case .emptyQueue:
            return "Queue is empty"
        }
    }
} 