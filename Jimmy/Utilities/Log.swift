import os

/// Centralized os.Logger categories used across the app in place of analytics/crash reporting.
enum Log {
    static let app = Logger(subsystem: "com.chenkahana.Jimmy", category: "app")
    static let playback = Logger(subsystem: "com.chenkahana.Jimmy", category: "playback")
    static let network = Logger(subsystem: "com.chenkahana.Jimmy", category: "network")
    static let data = Logger(subsystem: "com.chenkahana.Jimmy", category: "data")
}
