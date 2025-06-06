import Foundation
import UserNotifications

class DebugHelper {
    static let shared = DebugHelper()
    
    private init() {}
    
    // Reset all app data for testing
    func resetAllData() {
        // Clear UserDefaults
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        dictionary.keys.forEach { key in
            defaults.removeObject(forKey: key)
        }
        
        // Clear documents directory
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let directoryContents = try fileManager.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            for url in directoryContents {
                try fileManager.removeItem(at: url)
            }
        } catch {
            AppLogger.error("Error clearing documents directory: \(error)")
        }

        AppLogger.info("All app data reset successfully")
    }
    
    // Send test notification
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Jimmy Test"
        content.body = "This is a test notification from the debug helper"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.error("Error sending test notification: \(error)")
            } else {
                AppLogger.info("Test notification sent successfully")
            }
        }
    }
    
    // Print current app state
    func printAppState() {
        let podcasts = PodcastService.shared.loadPodcasts()
        let queue = QueueViewModel.shared.queue
        
        AppLogger.info("=== Jimmy App State ===")
        AppLogger.info("Podcasts: \(podcasts.count)")
        AppLogger.info("Queue episodes: \(queue.count)")
        AppLogger.info("Settings: darkMode = \(UserDefaults.standard.bool(forKey: \"darkMode\"))")
        AppLogger.info("========================")
    }
} 