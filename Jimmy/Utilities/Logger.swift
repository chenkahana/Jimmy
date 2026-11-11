import Foundation

/// Centralized error logging backed by OSLog and a persistent file.
final class ErrorLogger {
    static let shared = ErrorLogger()
    private let fileURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fileURL = caches.appendingPathComponent("JimmyErrors.log")
    }

    /// Log a message to OSLog and append it to the log file.
    func log(_ message: String) {

        guard let data = (message + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// URL of the exported log file.
    func exportLogFile() -> URL { fileURL }
}
