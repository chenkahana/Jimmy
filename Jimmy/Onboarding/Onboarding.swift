import Foundation
import Observation

/// Whether the first-run import shows, and the one import that's running.
@Observable
@MainActor
final class Onboarding {
    static let shared = Onboarding()

    static let completedKey = "onboardingCompleted"
    /// Shows onboarding again on this launch, even with shows in the library.
    static let resetArgument = "-resetOnboarding"
    /// Never shows onboarding on this launch (UI tests, screenshots).
    static let skipArgument = "-skipOnboarding"

    var isPresented = false
    /// Files shared to Jimmy (an OPML from Overcast's share sheet, say) waiting for the flow.
    var pendingFiles: [URL] = []
    private(set) var session = LibraryImportSession()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Pure first-run rule: never for `-skipOnboarding`; always for `-resetOnboarding`; never
    /// for `-demoLibrary` screenshots; otherwise only until it has been finished once, and never
    /// for a library that already has shows (someone updating from an older Jimmy).
    static func shouldPresent(hasCompleted: Bool, podcastCount: Int, arguments: [String]) -> Bool {
        if arguments.contains(skipArgument) { return false }
        if arguments.contains(resetArgument) { return true }
        if arguments.contains(DemoLibrary.launchArgument) { return false }
        return !hasCompleted && podcastCount == 0
    }

    /// Called once the store is open on launch.
    func presentIfNeeded(podcastCount: Int, arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains(Self.resetArgument) {
            defaults.removeObject(forKey: Self.completedKey)
        }
        let hasCompleted = defaults.bool(forKey: Self.completedKey)
        if Self.shouldPresent(hasCompleted: hasCompleted, podcastCount: podcastCount, arguments: arguments) {
            isPresented = true
        } else if podcastCount > 0 {
            defaults.set(true, forKey: Self.completedKey)
        }
    }

    /// Opens the flow from Settings, or with files shared to Jimmy.
    func present(files: [URL] = []) {
        pendingFiles = files
        isPresented = true
    }

    func finish() {
        defaults.set(true, forKey: Self.completedKey)
        isPresented = false
    }

    /// A fresh session for another attempt after a failure.
    func startOver() {
        guard !session.isRunning else { return }
        session = LibraryImportSession()
    }

    /// Whether a shared file is one the import flow reads rather than an audio file.
    static func isImportFile(_ url: URL) -> Bool {
        ["opml", "xml", "json", "txt", "csv"].contains(url.pathExtension.lowercased())
    }
}
