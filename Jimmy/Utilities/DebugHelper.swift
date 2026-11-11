import Foundation
import os
import UserNotifications

class DebugHelper {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "DebugHelper")
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
            Self.logger.error("Error clearing documents directory: \(error)")
        }
        
        Self.logger.info("All app data reset successfully")
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
                Self.logger.error("Error sending test notification: \(error)")
            } else {
                Self.logger.info("Test notification sent successfully")
            }
        }
    }
    
    // Print current app state
    @MainActor
    func printAppState() {
        let podcasts = PodcastService.shared.loadPodcasts()
        let queue = QueueViewModel.shared.queuedEpisodes
        
        Self.logger.debug("=== Jimmy App State ===")
        Self.logger.debug("Podcasts: \(podcasts.count)")
        Self.logger.debug("Queue episodes: \(queue.count)")
        let darkModeValue = UserDefaults.standard.bool(forKey: "darkMode")
        Self.logger.debug("Settings: darkMode = \(darkModeValue)")
        Self.logger.debug("========================")
    }
} 