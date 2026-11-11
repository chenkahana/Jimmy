import Foundation
import JimmyKit
import Combine
import UIKit
import os

/// Three-way appearance preference
enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorSchemeStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// ViewModel for Settings functionality following MVVM patterns
class SettingsViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SettingsViewModel")
    static let shared = SettingsViewModel()

    // MARK: - App Settings (KEEP @Published - bound to UI toggles/pickers)
    @Published var playbackSpeed: Double = 1.0
    @Published var appearanceMode: AppearanceMode = .system

    @Published var episodeSwipeAction: String = "addToQueue"
    @Published var queueSwipeAction: String = "markAsPlayed"
    @Published var iCloudSyncEnabled: Bool = true
    @Published var highContrastMode: Bool = false
    @Published var autoRestoreLastEpisode: Bool = true
    @Published var skipForwardDuration: Double = 15.0
    @Published var skipBackwardDuration: Double = 15.0
    
    // MARK: - UI States (KEEP @Published - bound to UI states)
    @Published var isLoading: Bool = false
    @Published var activeAlert: SettingsAlert?
    
    // Import/Export States (KEEP @Published - bound to UI loading states)
    @Published var isExporting = false
    @Published var isImporting = false
    @Published var isImportingFromApplePodcasts = false
    @Published var showingManualImport = false
    @Published var isSpotifyImporting = false
    @Published var spotifyImportMessage: String?
    @Published var isJSONImporting = false
    @Published var jsonImportMessage: String?
    @Published var showDeleteConfirmation = false
    @Published var showClearSubscriptionsConfirmation = false
    
    // Other UI States (KEEP @Published - bound to sheet presentations)
    @Published var showingAnalytics = false
    @Published var showingShortcutsGuide = false
    @Published var showingFeedbackForm = false
    
    // Cache Management (KEEP @Published - displayed in UI)
    @Published var cacheSize: String = "Calculating..."
    @Published var isCalculatingCache: Bool = false
    @Published var isClearingCache: Bool = false
    
    // MARK: - REMOVED @Published from these (not bound to UI or used internally only)
    // These don't need to trigger UI updates
    var errorMessage: String?
    var successMessage: String?
    var showingAlert: Bool = false
    var alertTitle: String = ""
    var alertMessage: String = ""
    var importError: String?
    var importProgress: Double = 0.0
    var exportProgress: Double = 0.0
    var debugInfo: [String: String] = [:]
    var isLoadingDebugInfo: Bool = false
    
    // MARK: - Private Properties
    private let cacheService: EpisodeCacheService
    private let podcastService: PodcastService
    private let importService: SubscriptionImportService
    private let feedbackService: FeedbackService
    private let crashPreventionManager: CrashPreventionManager
    private let podcastRepository: PodcastRepository
    private var cancellables = Set<AnyCancellable>()
    private var isInitializing = true

    // MARK: - Initialization
    private init(
        cacheService: EpisodeCacheService = .shared,
        podcastService: PodcastService = .shared,
        importService: SubscriptionImportService = .shared,
        feedbackService: FeedbackService = .shared,
        crashPreventionManager: CrashPreventionManager = .shared,
        podcastRepository: PodcastRepository = .shared
    ) {
        self.cacheService = cacheService
        self.podcastService = podcastService
        self.importService = importService
        self.feedbackService = feedbackService
        self.crashPreventionManager = crashPreventionManager
        self.podcastRepository = podcastRepository
        
        loadInitialData()
        setupSettingsBindings()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    private func loadInitialData() {
        loadSettings()
        isInitializing = false // Mark initialization as complete
        // Defer heavy operations to prevent blocking during initialization
        Task { @MainActor in
            // Small delay to let the view load first
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await calculateCacheSize()
            await loadDebugInfo()
        }
    }
    
    private func loadSettings() {
        playbackSpeed = UserDefaults.standard.double(forKey: "playbackSpeed")
        if playbackSpeed == 0 { playbackSpeed = 1.0 }

        // Load appearanceMode; migrate legacy keys if needed
        if let raw = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        } else {
            // Migrate from legacy followSystemAppearance + darkMode keys
            let followsSystem = UserDefaults.standard.object(forKey: "followSystemAppearance").flatMap { $0 as? Bool } ?? true
            if followsSystem {
                appearanceMode = .system
            } else {
                appearanceMode = UserDefaults.standard.bool(forKey: "darkMode") ? .dark : .light
            }
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
        applyAppearance(appearanceMode)

        episodeSwipeAction = UserDefaults.standard.string(forKey: "episodeSwipeAction") ?? "addToQueue"
        queueSwipeAction = UserDefaults.standard.string(forKey: "queueSwipeAction") ?? "markAsPlayed"
        iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        highContrastMode = UserDefaults.standard.bool(forKey: "highContrastMode")
        // Check if the setting has been set before, if not, default to true
        if UserDefaults.standard.object(forKey: "autoRestoreLastEpisode") != nil {
            autoRestoreLastEpisode = UserDefaults.standard.bool(forKey: "autoRestoreLastEpisode")
        } else {
            autoRestoreLastEpisode = true  // Default to true - users expect episode restoration
            UserDefaults.standard.set(true, forKey: "autoRestoreLastEpisode")
        }

        let fwd = UserDefaults.standard.double(forKey: "skipForwardDuration")
        skipForwardDuration = fwd > 0 ? fwd : 15.0
        let bwd = UserDefaults.standard.double(forKey: "skipBackwardDuration")
        skipBackwardDuration = bwd > 0 ? bwd : 15.0
    }
    
    private func applyAppearance(_ mode: AppearanceMode) {
        // .preferredColorScheme in ContentView handles SwiftUI appearance reactively.
        // Override UIKit windows to keep UIKit and SwiftUI in sync.
        let style = mode.colorSchemeStyle
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }

    private func setupSettingsBindings() {
        // Bind playback speed changes to audio player
        $playbackSpeed
            .sink { [weak self] speed in
                guard let self = self, !self.isInitializing else { return }
                Task { @MainActor in
                    AppModel.current?.playback?.setRate(Float(speed))
                }
                UserDefaults.standard.set(speed, forKey: "playbackSpeed")
            }
            .store(in: &cancellables)

        // Save appearanceMode and apply to windows
        $appearanceMode
            .sink { [weak self] mode in
                guard let self = self, !self.isInitializing else { return }
                UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
                self.applyAppearance(mode)
            }
            .store(in: &cancellables)
        
        $episodeSwipeAction
            .sink { UserDefaults.standard.set($0, forKey: "episodeSwipeAction") }
            .store(in: &cancellables)
        
        $queueSwipeAction
            .sink { UserDefaults.standard.set($0, forKey: "queueSwipeAction") }
            .store(in: &cancellables)
        
        $iCloudSyncEnabled
            .sink { UserDefaults.standard.set($0, forKey: "iCloudSyncEnabled") }
            .store(in: &cancellables)
        
        $highContrastMode
            .sink { UserDefaults.standard.set($0, forKey: "highContrastMode") }
            .store(in: &cancellables)
        
        $autoRestoreLastEpisode
            .sink { UserDefaults.standard.set($0, forKey: "autoRestoreLastEpisode") }
            .store(in: &cancellables)

        $skipForwardDuration
            .sink { [weak self] duration in
                guard let self = self, !self.isInitializing else { return }
                UserDefaults.standard.set(duration, forKey: "skipForwardDuration")
                let backward = self.skipBackwardDuration
                Task { @MainActor in
                    AppModel.current?.updateSkipIntervals(forward: duration, backward: backward)
                }
            }
            .store(in: &cancellables)

        $skipBackwardDuration
            .sink { [weak self] duration in
                guard let self = self, !self.isInitializing else { return }
                UserDefaults.standard.set(duration, forKey: "skipBackwardDuration")
                let forward = self.skipForwardDuration
                Task { @MainActor in
                    AppModel.current?.updateSkipIntervals(forward: forward, backward: duration)
                }
            }
            .store(in: &cancellables)
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
    
    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showAlert(title: "Error", message: error.localizedDescription)
    }
    
    private func showSuccess(_ message: String) {
        successMessage = message
        showAlert(title: "Success", message: message)
    }
    
    // MARK: - Cache Management
    func calculateCacheSize() async {
        await MainActor.run {
            isCalculatingCache = true
        }

        let totalBytes = await Task.detached(priority: .utility) {
            var bytes: Int64 = 0

            // URLCache disk usage
            bytes += Int64(URLCache.shared.currentDiskUsage)

            // App Caches directory
            let fm = FileManager.default
            if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                bytes += (try? Self.directorySize(at: cachesDir, fm: fm)) ?? 0
            }

            return bytes
        }.value

        let formatted = Self.formatBytes(totalBytes)

        await MainActor.run {
            self.cacheSize = formatted
            self.isCalculatingCache = false
        }
    }

    private static func directorySize(at url: URL, fm: FileManager) throws -> Int64 {
        var total: Int64 = 0
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(resourceKeys)) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            if resourceValues.isDirectory == false {
                total += Int64(resourceValues.fileSize ?? 0)
            }
        }
        return total
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else {
            return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
        }
    }
    
    func clearAllCache() async {
        await MainActor.run {
            isLoading = true
        }
        errorMessage = nil

        // Clear URLCache
        URLCache.shared.removeAllCachedResponses()

        // Clear image caches
        ImageCache.shared.clearAllCaches()

        // Clear episode cache for all podcasts
        let podcasts = podcastService.loadPodcasts()
        for podcast in podcasts {
            await cacheService.clearCache(for: podcast.id)
        }

        // Update LibraryViewModel to reflect cache changes
        await LibraryViewModel.shared.refreshData()

        // Recalculate cache size
        await calculateCacheSize()

        await MainActor.run {
            self.isLoading = false
        }
        showSuccess("All cached episodes cleared")
    }
    
    func clearEpisodeCache() async {
        // Note: clearEpisodeCache method doesn't exist
        // Use clearCache for all podcasts instead
        await clearAllCache()
    }
    
    func importSubscriptions(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> Int {
        progressHandler(0.1)
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        progressHandler(0.3)
        let data = try Data(contentsOf: url)
        progressHandler(0.5)

        let parser = OPMLParser()
        let parsed = parser.parse(data)
        progressHandler(0.7)

        let existing = podcastService.loadPodcasts()
        let existingURLs = Set(existing.map { $0.feedURL.absoluteString })
        let newPodcasts = parsed.filter { !existingURLs.contains($0.feedURL.absoluteString) }

        if !newPodcasts.isEmpty {
            let allPodcasts = existing + newPodcasts
            try await podcastRepository.savePodcasts(allPodcasts)
            await LibraryViewModel.shared.refreshData()
        }

        progressHandler(1.0)
        return newPodcasts.count
    }
    
    func exportSubscriptions(progressHandler: @escaping (Double) -> Void) async throws -> URL {
        progressHandler(0.1)
        let podcasts = podcastService.loadPodcasts()
        progressHandler(0.4)

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<opml version=\"2.0\">")
        lines.append("  <head>")
        lines.append("    <title>Jimmy Subscriptions</title>")
        lines.append("  </head>")
        lines.append("  <body>")
        for podcast in podcasts {
            let title = podcast.title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let feedURL = podcast.feedURL.absoluteString
            lines.append("    <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(feedURL)\"/>")
        }
        lines.append("  </body>")
        lines.append("</opml>")

        progressHandler(0.8)
        let content = lines.joined(separator: "\n")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("jimmy_subscriptions.opml")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        progressHandler(1.0)
        return tempURL
    }
    
    // MARK: - Debug Information
    func loadDebugInfo() async {
        isLoadingDebugInfo = true
        
        let info = await gatherDebugInformation()
        debugInfo = info
        
        isLoadingDebugInfo = false
    }
    
    private func gatherDebugInformation() async -> [String: String] {
        var info: [String: String] = [:]
        
        // App Information
        info["App Version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        info["Build Number"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        // System Information
        info["iOS Version"] = await UIDevice.current.systemVersion
        info["Device Model"] = await UIDevice.current.model
        
        // Storage Information
        info["Cache Size"] = self.cacheSize
        
        // Podcast Information
        let podcasts = podcastService.loadPodcasts()
        info["Subscribed Podcasts"] = "\(podcasts.count)"
        
        return info
    }
    
    func copyDebugInfo() {
        let debugText = debugInfo.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        UIPasteboard.general.string = debugText
        showSuccess("Debug information copied to clipboard")
    }
    
    // MARK: - Feedback
    func submitFeedback(subject: String, message: String) async throws {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let fullSubject = subject.isEmpty ? "Jimmy v\(appVersion) Feedback" : subject
        let body = message.isEmpty ? "" : "\(message)\n\n---\nApp version: \(appVersion) (\(buildNumber))"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "feedback@jimmypodcasts.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: fullSubject),
            URLQueryItem(name: "body", value: body)
        ]

        guard let url = components.url else { return }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Data Management
    func resetAllData() async {
        await MainActor.run {
            isLoading = true
        }
        errorMessage = nil
        
        // Get all podcasts to clear their caches
        let podcasts = podcastService.loadPodcasts()
        
        for podcast in podcasts {
            await cacheService.clearCache(for: podcast.id)
        }
        
        // Clear all podcasts from storage
        do {
            try await podcastRepository.savePodcasts([])
            Self.logger.info("SettingsViewModel: Successfully cleared all podcasts")
        } catch {
            Self.logger.error("SettingsViewModel: Failed to clear podcasts: \(error)")
        }
        
        // Update LibraryViewModel to reflect the changes
        await LibraryViewModel.shared.refreshData()
        
        // Recalculate cache size
        await calculateCacheSize()
        
        await MainActor.run {
            self.isLoading = false
        }
        showSuccess("All data has been reset")
    }
    
    func refreshData() async {
        await MainActor.run {
            isLoading = true
        }
        
        await calculateCacheSize()
        await loadDebugInfo()
        showSuccess("Data refreshed successfully")
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    // MARK: - Additional Import/Export Actions
    func exportAppData() async {
        await MainActor.run {
            isExporting = true
        }
        defer { 
            Task { @MainActor in
                self.isExporting = false
            }
        }
        
        _ = try? await exportSubscriptions(progressHandler: { _ in })
    }
    
    func importFromJSON(fileURL: URL? = nil) async {
        guard let fileURL = fileURL else {
            await MainActor.run {
                self.jsonImportMessage = "No file selected"
                self.showAlert(.jsonImport("No file selected"))
            }
            return
        }
        
        await MainActor.run {
            self.isJSONImporting = true
            self.jsonImportMessage = "Reading JSON file..."
        }
        
        defer { 
            Task { @MainActor in
                self.isJSONImporting = false
            }
        }
        
        do {
            // Start accessing the security-scoped resource
            let hasAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // Read the file data
            let data = try Data(contentsOf: fileURL)
            await MainActor.run {
                self.jsonImportMessage = "Parsing JSON data..."
            }
            
            // Use the subscription import service to parse and import
            let importedPodcasts = await withCheckedContinuation { continuation in
                SubscriptionImportService.shared.importFromJSONFile(
                    data: data,
                    progressHandler: { [weak self] message in
                        Task { @MainActor in
                            self?.jsonImportMessage = message
                        }
                    }
                ) { podcasts, error in
                    if let error = error {
                        continuation.resume(returning: Result<[Podcast], Error>.failure(error))
                    } else {
                        continuation.resume(returning: Result<[Podcast], Error>.success(podcasts))
                    }
                }
            }
            
            switch importedPodcasts {
            case .success(let podcasts):
                if podcasts.isEmpty {
                    await MainActor.run {
                        self.jsonImportMessage = "No valid podcasts found in the JSON file"
                        self.showAlert(.jsonImport("No valid podcasts found in the JSON file"))
                    }
                } else {
                    // Add podcasts to the user's library
                    let existingPodcasts = podcastService.loadPodcasts()
                    let newPodcasts = podcasts.filter { newPodcast in
                        !existingPodcasts.contains { $0.feedURL == newPodcast.feedURL }
                    }
                    
                    if newPodcasts.isEmpty {
                        await MainActor.run {
                            self.jsonImportMessage = "All podcasts from the JSON file are already in your library"
                            self.showAlert(.jsonImport("All podcasts from the JSON file are already in your library"))
                        }
                    } else {
                        // Save the new podcasts
                        let allPodcasts = existingPodcasts + newPodcasts
                        try await podcastRepository.savePodcasts(allPodcasts)
                        
                        // Refresh the library to show new subscriptions
                        await LibraryViewModel.shared.refreshData()
                        
                        await MainActor.run {
                            self.jsonImportMessage = "Successfully imported \(newPodcasts.count) new podcast(s)"
                        }
                        showSuccess("Successfully imported \(newPodcasts.count) new podcast(s)")
                    }
                }
                
            case .failure(let error):
                await MainActor.run {
                    self.jsonImportMessage = "Failed to import: \(error.localizedDescription)"
                    self.showAlert(.jsonImport("Failed to import: \(error.localizedDescription)"))
                }
            }
            
        } catch {
            await MainActor.run {
                self.jsonImportMessage = "Failed to read file: \(error.localizedDescription)"
                self.showAlert(.jsonImport("Failed to read file: \(error.localizedDescription)"))
            }
        }
    }
    
    func importFromSpotify() async {
        await MainActor.run {
            isSpotifyImporting = true
        }
        defer {
            Task { @MainActor in
                self.isSpotifyImporting = false
            }
        }

        let message = """
        Spotify does not provide a direct podcast export. \
        To import your Spotify podcast follows:
        1. Open Spotify and find the podcast.
        2. Search for the podcast's RSS feed online (e.g. via Podcast Index).
        3. Use OPML import in Jimmy with the feed URL.

        Alternatively, export an OPML file from another podcast app you may have used.
        """
        await MainActor.run {
            self.spotifyImportMessage = message
            self.showAlert(.spotifyImport(message))
        }
    }
    
    func performComprehensiveApplePodcastsImport() async {
        await MainActor.run {
            isImportingFromApplePodcasts = true
        }
        defer {
            Task { @MainActor in
                self.isImportingFromApplePodcasts = false
            }
        }

        let guide = """
        To import from Apple Podcasts:
        1. Open Apple Podcasts on your Mac.
        2. Go to File > Export Subscriptions…
        3. Save the .opml file.
        4. Transfer the file to your iPhone via AirDrop or Files.
        5. In Jimmy, tap "Import OPML" and select the file.

        On iPhone only: Go to Settings > Privacy > Media & Apple Music \
        and grant Jimmy access, then use "Import from Apple Podcasts" in Jimmy Settings.
        """
        await MainActor.run {
            self.activeAlert = .appleImport(guide)
        }
    }
    
    // MARK: - Management Actions
    func clearAllSubscriptions() async {
        await MainActor.run {
            isLoading = true
        }
        errorMessage = nil
        
        // Clear all cached episodes first for a thorough cleanup.
        await cacheService.clearAllCache()
        
        // Clear all podcasts from storage
        do {
            try await podcastRepository.savePodcasts([])
            Self.logger.info("SettingsViewModel: Successfully cleared all podcasts")
        } catch {
            Self.logger.error("SettingsViewModel: Failed to clear podcasts: \(error)")
        }
        Self.logger.info("SettingsViewModel: Cleared all podcast subscriptions from database")
        
        // Update LibraryViewModel to reflect the changes
        await LibraryViewModel.shared.refreshData()
        
        // Recalculate cache size
        await calculateCacheSize()
        
        await MainActor.run {
            self.isLoading = false
        }
        showSuccess("All subscriptions and cached episodes cleared")
    }
    
    // MARK: - Alert Management
    func dismissAlert() {
        activeAlert = nil
        showingAlert = false
        errorMessage = nil
        successMessage = nil
        alertTitle = ""
        alertMessage = ""
    }
    
    func showAlert(_ alert: SettingsAlert) {
        activeAlert = alert
    }
}

// MARK: - Supporting Types
enum SettingsAlert {
    case resetData
    case appleImport(String)
    case spotifyImport(String)
    case jsonImport(String)
    case clearSubscriptions
    case subscriptionImport(String)
} 
