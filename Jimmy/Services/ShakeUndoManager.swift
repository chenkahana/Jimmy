import Foundation
import CoreMotion
import UIKit

// Enum to define different types of undoable operations
enum UndoableOperation {
    case subscriptionRemoved(podcast: Podcast)
    case episodeRemovedFromQueue(episode: Episode, atIndex: Int)
    case queueReordered(previousQueue: [Episode])
    case episodeAddedToQueue(episode: Episode)
    case episodeMovedInQueue(episode: Episode, fromIndex: Int, toIndex: Int)
    case podcastSubscribed(podcast: Podcast)
    case bulkEpisodesRemovedFromQueue(episodes: [Episode], removedFromIndex: Int, targetEpisode: Episode)
}

// Structure to hold operation details with timestamp
struct UndoableAction {
    let operation: UndoableOperation
    let timestamp: Date
    let description: String
}

class ShakeUndoManager: ObservableObject {
    static let shared = ShakeUndoManager()
    
    @Published var lastAction: UndoableAction?
    @Published var showUndoToast: Bool = false
    @Published var undoToastMessage: String = ""
    private let maxUndoTimeInterval: TimeInterval = 60.0 // 1 minute
    
    // Motion manager for shake detection
    private let motionManager = CMMotionManager()
    private var isShakeDetectionActive = false
    
    private init() {
        // REMOVED: Don't setup shake detection automatically to reduce startup time
        // setupShakeDetection() - This will be called manually when needed
    }
    
    // MARK: - Operation Tracking
    
    func recordOperation(_ operation: UndoableOperation, description: String) {
        DispatchQueue.main.async {
            self.lastAction = UndoableAction(
                operation: operation,
                timestamp: Date(),
                description: description
            )
        }
        
        print("🔄 Recorded undoable operation: \(description)")
    }
    
    func canUndo() -> Bool {
        guard let lastAction = lastAction else { return false }
        let timeSinceAction = Date().timeIntervalSince(lastAction.timestamp)
        return timeSinceAction <= maxUndoTimeInterval
    }
    
    func performUndo() {
        guard canUndo(), let action = lastAction else {
            print("❌ Cannot undo: No valid action within time limit")
            return
        }
        
        print("↩️ Performing undo: \(action.description)")
        
        switch action.operation {
        case .subscriptionRemoved(let podcast):
            undoSubscriptionRemoval(podcast)
            
        case .episodeRemovedFromQueue(let episode, let atIndex):
            undoEpisodeRemovalFromQueue(episode, atIndex: atIndex)
            
        case .queueReordered(let previousQueue):
            undoQueueReorder(previousQueue)
            
        case .episodeAddedToQueue(let episode):
            undoEpisodeAddedToQueue(episode)
            
        case .episodeMovedInQueue(let episode, let fromIndex, let toIndex):
            undoEpisodeMove(episode, fromIndex: fromIndex, toIndex: toIndex)
            
        case .podcastSubscribed(let podcast):
            undoPodcastSubscription(podcast)
            
        case .bulkEpisodesRemovedFromQueue(let episodes, let removedFromIndex, let targetEpisode):
            undoBulkEpisodeRemovalFromQueue(episodes, removedFromIndex: removedFromIndex, targetEpisode: targetEpisode)
        }
        
        // Clear the last action after undo
        DispatchQueue.main.async {
            self.lastAction = nil
        }
    }
    
    // MARK: - Undo Implementations
    
    private func undoSubscriptionRemoval(_ podcast: Podcast) {
        // Re-add the podcast to subscriptions
        var podcasts = PodcastService.shared.loadPodcasts()
        podcasts.append(podcast)
        PodcastService.shared.savePodcasts(podcasts)
        print("✅ Restored subscription to: \(podcast.title)")
    }
    
    private func undoEpisodeRemovalFromQueue(_ episode: Episode, atIndex: Int) {
        let queue = QueueViewModel.shared
        
        // Insert the episode back at its original position
        if atIndex < queue.queue.count {
            queue.queue.insert(episode, at: atIndex)
        } else {
            queue.queue.append(episode)
        }
        queue.saveQueue()
        print("✅ Restored episode to queue: \(episode.title)")
    }
    
    private func undoQueueReorder(_ previousQueue: [Episode]) {
        let queue = QueueViewModel.shared
        queue.queue = previousQueue
        queue.saveQueue()
        print("✅ Restored previous queue order")
    }
    
    private func undoEpisodeAddedToQueue(_ episode: Episode) {
        let queue = QueueViewModel.shared
        queue.removeFromQueue(episode)
        print("✅ Removed episode from queue: \(episode.title)")
    }
    
    private func undoEpisodeMove(_ episode: Episode, fromIndex: Int, toIndex: Int) {
        let queue = QueueViewModel.shared
        
        // Move the episode back to its original position
        if let currentIndex = queue.queue.firstIndex(where: { $0.id == episode.id }) {
            let removedEpisode = queue.queue.remove(at: currentIndex)
            queue.queue.insert(removedEpisode, at: fromIndex)
            queue.saveQueue()
        }
        print("✅ Restored episode position: \(episode.title)")
    }
    
    private func undoPodcastSubscription(_ podcast: Podcast) {
        // Remove the podcast from subscriptions
        var podcasts = PodcastService.shared.loadPodcasts()
        podcasts.removeAll { $0.id == podcast.id }
        PodcastService.shared.savePodcasts(podcasts)
        print("✅ Removed subscription to: \(podcast.title)")
    }
    
    private func undoBulkEpisodeRemovalFromQueue(_ removedEpisodes: [Episode], removedFromIndex: Int, targetEpisode: Episode) {
        let queue = QueueViewModel.shared
        
        // Stop current playback to properly restore the queue state
        AudioPlayerService.shared.stop()
        
        // Remove the target episode from its current position (should be at index 0)
        queue.queue.removeAll { $0.id == targetEpisode.id }
        
        // Restore all the removed episodes at their original positions
        for (index, episode) in removedEpisodes.enumerated() {
            let insertIndex = removedFromIndex + index
            if insertIndex <= queue.queue.count {
                queue.queue.insert(episode, at: insertIndex)
            }
        }
        
        // Re-add the target episode at its original position
        let originalTargetIndex = removedEpisodes.count + removedFromIndex
        if originalTargetIndex <= queue.queue.count {
            queue.queue.insert(targetEpisode, at: originalTargetIndex)
        } else {
            queue.queue.append(targetEpisode)
        }
        
        // Update the episode IDs set to match the restored queue
        queue.updateEpisodeIDs()
        
        queue.saveQueue()
        print("✅ Restored \(removedEpisodes.count) episodes to queue before \"\(targetEpisode.title)\"")
    }
    
    // MARK: - Shake Detection
    
    func setupShakeDetection() {
        guard motionManager.isDeviceMotionAvailable else {
            print("❌ Device motion not available for shake detection")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion, error == nil else { return }
            
            self?.detectShake(from: motion)
        }
        
        isShakeDetectionActive = true
        print("📱 Shake detection initialized")
    }
    
    private func detectShake(from motion: CMDeviceMotion) {
        let acceleration = motion.userAcceleration
        let threshold: Double = 2.5
        
        // Calculate total acceleration magnitude
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        // If magnitude exceeds threshold, it's likely a shake
        if magnitude > threshold {
            handleShakeDetected()
        }
    }
    
    private var lastShakeTime: Date = Date.distantPast
    private let minShakeInterval: TimeInterval = 1.0 // Prevent multiple shake detections
    
    private func handleShakeDetected() {
        let now = Date()
        guard now.timeIntervalSince(lastShakeTime) > minShakeInterval else { return }
        lastShakeTime = now
        
        print("📱 Shake detected!")
        
        if canUndo() {
            performUndo()
            
            // Provide haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Show a brief notification
            showUndoNotification()
        } else {
            print("❌ No action to undo or action too old")
            
            // Light haptic feedback to indicate nothing to undo
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }
    
    private func showUndoNotification() {
        guard let action = lastAction else { return }
        
        // Show toast notification
        DispatchQueue.main.async {
            self.undoToastMessage = "Undid: \(action.description)"
            self.showUndoToast = true
        }
        
        print("✅ Undo completed successfully")
    }
    
    deinit {
        if isShakeDetectionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
} 