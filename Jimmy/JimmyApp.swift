import SwiftUI
import os.log
import UIKit
import TipKit

/// Timeout error for service initialization
struct ServiceTimeoutError: Error {
    let message: String

    init(_ message: String = "Operation timed out") {
        self.message = message
    }
}

/// Forwards the background `URLSession` continuation UIKit hands the app (e.g. after it was
/// killed while a background download was still running) to `Downloads`, so its queued
/// `URLSessionDownloadDelegate` callbacks get delivered and the finished download gets saved.
final class JimmyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard let downloads = AppModel.current?.downloads else {
            completionHandler()
            return
        }
        downloads.handleBackgroundEvents(identifier: identifier, completion: completionHandler)
    }
}

/// Main app entry point with optimized initialization
@main
struct JimmyApp: App {
    // MARK: - App State
    // MARK: - App State
    @UIApplicationDelegateAdaptor(JimmyAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel: AppModel
    private let showsPerformanceHUD = ProcessInfo.processInfo.environment["JIMMY_SHOW_PERF_HUD"] == "1"
    private let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    // MARK: - Logging
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "JimmyApp")

    init() {
        let isDemoLibrary = DemoLibrary.isRequested()
        let databasePath = AppModel.launchDatabasePath(isRunningUnitTests: isRunningUnitTests)
        let model = AppModel(
            databasePath: databasePath,
            // Demo-library screenshots start from an empty store seeded over the network (see
            // below), never from whatever legacy data happens to be on disk.
            legacyInput: (isRunningUnitTests || isDemoLibrary) ? { nil } : { AppModel.legacyInputFromDisk() }
        )
        _appModel = State(initialValue: model)
        AppModel.current = model

        // BGTaskScheduler only accepts registrations before launch finishes, so this can't wait
        // for a launch-failure retry; the handlers' `refreshAll()` does nothing until the store opens.
        if !isRunningUnitTests {
            BackgroundTaskManager.shared.registerBackgroundTasks()
        }

        startOldServicesIfReady(model)

        if isDemoLibrary {
            Task {
                await DemoLibrary.seed(into: model)
                await DemoLibrary.navigateToScreenshotRouteIfRequested()
            }
        }
    }

    /// Everything `init()` used to do unconditionally — skipped while the store failed to open,
    /// so the old services never touch a database `AppModel` couldn't make sense of. Called again
    /// after a launch-failure retry succeeds (`init()` itself only ever runs once).
    private func startOldServicesIfReady(_ model: AppModel) {
        guard case .ready = model.launchState else { return }

        if !isRunningUnitTests {
            configureTips()

            // Collect crash/hang diagnostics via MetricKit
            MetricsSubscriber.shared.start()
        }

        // Apply dark mode setting
        applyInitialDarkModeSetting()

        // Restore whatever was last playing (paused) — after `applyInitialDarkModeSetting()`,
        // which is what first writes `SettingsViewModel`'s `autoRestoreLastEpisode` default.
        // Skipped for `-demoLibrary`: `DemoLibrary.seed(into:)` drives `model.playback` itself,
        // and refreshing podcasts that were just subscribed to would only race it.
        if !isRunningUnitTests {
            Task {
                let podcastCount = (try? await model.readyStore?.podcasts().count) ?? 0
                Onboarding.shared.presentIfNeeded(podcastCount: podcastCount)
            }
        }

        if !isRunningUnitTests && !DemoLibrary.isRequested() {
            Task { await model.restoreLastEpisodeIfEnabled() }
            Task { await model.refreshAll() }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch appModel.launchState {
                case .ready:
                    readyContent
                case .failed(let failure):
                    LaunchFailureView(
                        message: failure.message,
                        onRetry: {
                            appModel.retry()
                            startOldServicesIfReady(appModel)
                        },
                        onResetLibrary: {
                            appModel.resetLibrary()
                            startOldServicesIfReady(appModel)
                        }
                    )
                }
            }
            .environment(appModel)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        ZStack {
            AppShell()

            #if DEBUG
            if showsPerformanceHUD {
                PerformanceDebugOverlay()
            }
            #endif
        }
        .environment(ShellStore.shared)
        .environment(InteractionLatencyTracker.shared)
        .fullScreenCover(
            isPresented: Binding(
                get: { ShellStore.shared.presentation == .nowPlaying },
                set: { isPresented in
                    if !isPresented {
                        ShellStore.shared.clearPresentation()
                    }
                }
            )
        ) {
            ExpandedNowPlayingView {
                ShellStore.shared.clearPresentation()
            }
            .environment(ShellStore.shared)
            .environment(InteractionLatencyTracker.shared)
            .environment(appModel)
        }
        .onAppear {
            if !isRunningUnitTests {
                initializeServices()
            }
        }
        .onOpenURL { url in
            handleURL(url)
        }
    }
    
    // MARK: - Initialization

    private func configureTips() {
        // Screenshots for the README show the screens, not first-run tips.
        if ProcessInfo.processInfo.environment["JIMMY_SCREENSHOT_ROUTE"] != nil {
            Tips.hideAllTipsForTesting()
        }
        do {
            try Tips.configure([
                .displayFrequency(.daily),
                .datastoreLocation(.applicationDefault)
            ])
        } catch {
            Self.logger.error("TipKit configuration failed: \(error.localizedDescription)")
        }
    }

    private func initializeServices() {
        let startTime = CFAbsoluteTimeGetCurrent()

        let criticalElapsed = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("Critical services initialized in \(String(format: "%.3f", criticalElapsed))s")

        // Background initialization for non-critical services
        // These will initialize lazily when first accessed
        Task(priority: .background) {
            let bgStart = CFAbsoluteTimeGetCurrent()
            
            // Network (needed for data fetching, but not blocking UI)
            _ = UnifiedNetworkService.shared

            // Start iCloud KVS sync observer
            AppDataDocument.startObservingICloudChanges()
            
            let bgElapsed = CFAbsoluteTimeGetCurrent() - bgStart
            Self.logger.info("Background services initialized in \(String(format: "%.3f", bgElapsed))s")
        }
    }
    
    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard !isRunningUnitTests else {
            return
        }

        switch newPhase {
        case .background:
            appModel.flushPlaybackForBackground()
            Task(priority: .background) {
                await BackgroundTaskManager.shared.scheduleBackgroundRefresh()
                await BackgroundTaskManager.shared.scheduleLibraryIncrementalRefresh()
            }
        default:
            break
        }
    }
    
    // MARK: - URL Handling
    
    private func handleURL(_ url: URL) {
        // Try deep link router first
        if let deepLink = DeepLinkRouter.shared.parse(url: url) {
            Task { @MainActor in
                DeepLinkRouter.shared.navigate(to: deepLink)
            }
            return
        }

        // Fallback: handle file imports and legacy subscribe URLs
        Task {
            if url.isFileURL, Onboarding.isImportFile(url) {
                Onboarding.shared.present(files: [url])
            } else if url.isFileURL {
                await LocalAudioImporter.shared.handleSharedFile(from: url)
            } else if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let queryItems = components.queryItems,
                      let feedURLString = queryItems.first(where: { $0.name == "url" })?.value,
                      let feedURL = URL(string: feedURLString) {
                _ = try? await AppModel.current?.subscribe(feedURL: feedURL)
            }
        }
    }
    
    // MARK: - Dark Mode Setup
    
    private func applyInitialDarkModeSetting() {
        // Eagerly initialise SettingsViewModel so its Combine bindings are active.
        // SettingsViewModel.loadSettings() will apply the correct UIUserInterfaceStyle.
        _ = SettingsViewModel.shared
    }
}
