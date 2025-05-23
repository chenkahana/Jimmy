import Foundation
import UserNotifications

class QueueViewModel: ObservableObject {
    static let shared = QueueViewModel()
    @Published var queue: [Episode] = []
    private let queueKey = "queueKey"
    
    private init() {
        loadQueue()
    }
    
    func addToQueue(_ episode: Episode) {
        queue.append(episode)
        saveQueue()
    }
    
    func removeFromQueue(at offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
        saveQueue()
    }
    
    func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        saveQueue()
    }
    
    func removeEpisodes(withIDs ids: Set<UUID>) {
        queue.removeAll { ids.contains($0.id) }
        saveQueue()
    }
    
    func markEpisodesAsPlayed(withIDs ids: Set<UUID>) {
        for i in queue.indices {
            if ids.contains(queue[i].id) {
                queue[i].played = true
            }
        }
        saveQueue()
    }
    
    func autoAddNewEpisodesFromSubscribedPodcasts() {
        let podcasts = PodcastService.shared.loadPodcasts().filter { $0.autoAddToQueue }
        for podcast in podcasts {
            PodcastService.shared.fetchEpisodes(for: podcast) { [weak self] episodes in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let existingIDs = Set(self.queue.map { $0.id })
                    let newEpisodes = episodes.filter { !existingIDs.contains($0.id) }
                    for episode in newEpisodes {
                        self.addToQueue(episode)
                        if podcast.notificationsEnabled {
                            self.scheduleNotification(for: episode, podcast: podcast)
                        }
                    }
                }
            }
        }
    }
    
    private func scheduleNotification(for episode: Episode, podcast: Podcast) {
        let content = UNMutableNotificationContent()
        content.title = "New Episode: \(podcast.title)"
        content.body = episode.title
        content.sound = .default
        let request = UNNotificationRequest(identifier: episode.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    func saveQueue() {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
            AppDataDocument.saveToICloudIfEnabled()
        }
    }
    
    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let savedQueue = try? JSONDecoder().decode([Episode].self, from: data) {
            queue = savedQueue
        }
    }
} 