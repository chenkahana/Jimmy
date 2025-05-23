import Foundation

class WidgetDataService {
    static let shared = WidgetDataService()
    
    private let groupName = "group.com.chenkahana.jimmy"
    private let userDefaults: UserDefaults
    
    private init() {
        guard let defaults = UserDefaults(suiteName: groupName) else {
            fatalError("Could not create UserDefaults with suite name: \(groupName)")
        }
        userDefaults = defaults
    }
    
    // MARK: - Current Episode Data
    func saveCurrentEpisode(_ episode: Episode?) {
        if let episode = episode {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(episode) {
                userDefaults.set(encoded, forKey: "current_episode")
            }
        } else {
            userDefaults.removeObject(forKey: "current_episode")
        }
    }
    
    func getCurrentEpisode() -> Episode? {
        guard let data = userDefaults.data(forKey: "current_episode") else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(Episode.self, from: data)
    }
    
    // MARK: - Playback State
    func savePlaybackState(isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        userDefaults.set(isPlaying, forKey: "is_playing")
        userDefaults.set(position, forKey: "playback_position")
        userDefaults.set(duration, forKey: "duration")
    }
    
    func getPlaybackState() -> (isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        let isPlaying = userDefaults.bool(forKey: "is_playing")
        let position = userDefaults.double(forKey: "playback_position")
        let duration = userDefaults.double(forKey: "duration")
        return (isPlaying, position, duration)
    }
    
    // MARK: - Widget Update Notification
    func notifyWidgetUpdate() {
        userDefaults.set(Date().timeIntervalSince1970, forKey: "last_update")
    }
} 