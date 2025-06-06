#if canImport(os)
import os
#endif
import Foundation

public enum LogCategory: String {
    case general
    case network
    case storage
}

public struct AppLogger {
    #if canImport(os)
    private static func logger(for category: LogCategory) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Jimmy", category: category.rawValue)
    }

    public static func info(_ message: String, category: LogCategory = .general) {
        logger(for: category).info("\(message, privacy: .public)")
    }

    public static func error(_ message: String, category: LogCategory = .general) {
        logger(for: category).error("\(message, privacy: .public)")
    }
    #else
    public static func info(_ message: String, category: LogCategory = .general) {
        print("[\(category.rawValue)] \(message)")
    }

    public static func error(_ message: String, category: LogCategory = .general) {
        print("[\(category.rawValue)] ERROR: \(message)")
    }
    #endif
}
