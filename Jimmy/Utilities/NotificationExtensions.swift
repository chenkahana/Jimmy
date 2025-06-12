import Foundation

extension Notification.Name {
    /// Notification sent when a file import is requested
    static let fileImportRequested = Notification.Name("fileImportRequested")
    
    /// Notification sent when a file import completes successfully
    static let fileImportCompleted = Notification.Name("fileImportCompleted")
    
    /// Notification sent when a file import fails
    static let fileImportFailed = Notification.Name("fileImportFailed")
} 