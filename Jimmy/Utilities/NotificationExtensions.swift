import Foundation

extension Notification.Name {
    /// Notification sent when a file import is requested
    static let fileImportRequested = Notification.Name("fileImportRequested")
    
    /// Notification sent when a file import completes successfully
    static let fileImportCompleted = Notification.Name("fileImportCompleted")
    
    /// Notification sent when a file import fails
    static let fileImportFailed = Notification.Name("fileImportFailed")
    
    /// Notification sent when an episode is added to the queue
    static let episodeAddedToQueue = Notification.Name("episodeAddedToQueue")
    
    /// Notification sent when an episode is removed from the queue
    static let episodeRemovedFromQueue = Notification.Name("episodeRemovedFromQueue")
    
    /// Notification sent when the queue order changes
    static let queueOrderChanged = Notification.Name("queueOrderChanged")
    
    /// Notification sent when the queue needs to be refreshed
    static let queueNeedsRefresh = Notification.Name("queueNeedsRefresh")
} 