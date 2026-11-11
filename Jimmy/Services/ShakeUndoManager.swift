import Foundation
import CoreMotion
import UIKit
import os

// Enum to define different types of undoable operations
enum UndoableOperation {
    case subscriptionRemoved(podcast: Podcast)
    case podcastSubscribed(podcast: Podcast)
}

// Structure to hold operation details with timestamp
struct UndoableAction {
    let operation: UndoableOperation
    let timestamp: Date
    let description: String
}

class ShakeUndoManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ShakeUndoManager")
    static let shared = ShakeUndoManager()
    
    @Published var lastAction: UndoableAction?
    @Published var showUndoToast: Bool = false
    @Published var undoToastMessage: String = ""
    private let maxUndoTimeInterval: TimeInterval = 60.0 // 1 minute
    
    // Motion manager for shake detection
    private let motionManager = CMMotionManager()
    private var isShakeDetectionActive = false
    private var lastShakeTimestamp = Date.distantPast
    
    init() {
        // Start shake detection when the manager is initialized
        startShakeDetection()
    }
    
    // MARK: - Operation Tracking
    
    func recordOperation(_ operation: UndoableOperation, description: String) {
        // PERFORMANCE FIX: Direct assignment to prevent publishing warnings
        self.lastAction = UndoableAction(
            operation: operation,
            timestamp: Date(),
            description: description
        )
        
        Self.logger.debug("Recorded undoable operation: \(description)")
    }
    
    func canUndo() -> Bool {
        guard let lastAction = lastAction else { return false }
        let timeSinceAction = Date().timeIntervalSince(lastAction.timestamp)
        return timeSinceAction <= maxUndoTimeInterval
    }
    
    func performUndo() {
        guard canUndo(), let action = lastAction else {
            Self.logger.warning("Cannot undo: No valid action within time limit")
            return
        }
        
        Self.logger.info("Performing undo: \(action.description)")
        
        switch action.operation {
        case .subscriptionRemoved(let podcast):
            undoSubscriptionRemoval(podcast)

        case .podcastSubscribed(let podcast):
            undoPodcastSubscription(podcast)
        }
        
        // Clear the last action after undo - PERFORMANCE FIX: Direct assignment to prevent publishing warnings
        self.lastAction = nil
    }
    
    // MARK: - Undo Implementations
    
    private func undoSubscriptionRemoval(_ podcast: Podcast) {
        // Re-add the podcast to subscriptions
        var podcasts = PodcastService.shared.loadPodcasts()
        podcasts.append(podcast)
        PodcastService.shared.savePodcasts(podcasts)
    }
    
    private func undoPodcastSubscription(_ podcast: Podcast) {
        // Remove the podcast from subscriptions
        var podcasts = PodcastService.shared.loadPodcasts()
        podcasts.removeAll { $0.id == podcast.id }
        PodcastService.shared.savePodcasts(podcasts)
    }

    // MARK: - Shake Detection
    
    func startShakeDetection() {
        guard CMMotionManager().isAccelerometerAvailable else {
            return
        }
        
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            
            // Simple shake detection logic
            if abs(data.acceleration.x) > 1.5 || abs(data.acceleration.y) > 1.5 || abs(data.acceleration.z) > 1.5 {
                let now = Date()
                if now.timeIntervalSince(self.lastShakeTimestamp) > 1.0 { // 1 second cooldown
                    self.lastShakeTimestamp = now
                    self.shakeDetected()
                }
            }
        }
    }
    
    func stopShakeDetection() {
        motionManager.stopAccelerometerUpdates()
    }
    
    private func shakeDetected() {
        // Post a notification that a shake was detected
        NotificationCenter.default.post(name: .deviceDidShake, object: nil)
    }
    
    private func showUndoNotification() {
        guard let action = lastAction else { return }
        
        // Show toast notification - PERFORMANCE FIX: Direct assignment to prevent publishing warnings
        self.undoToastMessage = "Undid: \(action.description)"
        self.showUndoToast = true
    }
    
    func showUndoToast(message: String) {
        // PERFORMANCE FIX: Direct assignment to prevent publishing warnings
        self.undoToastMessage = message
        self.showUndoToast = true
        
        // Auto-hide after 3 seconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            self?.showUndoToast = false
        }
    }
    
    deinit {
        if isShakeDetectionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
}

extension NSNotification.Name {
    static let deviceDidShake = NSNotification.Name("deviceDidShake")
} 