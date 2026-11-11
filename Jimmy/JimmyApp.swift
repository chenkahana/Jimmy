import SwiftUI
import AVFoundation
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

/// Main app entry point with optimized initialization
@main
struct JimmyApp: App {
    // MARK: - App State
    // MARK: - App State
    @Environment(\.scenePhase) private var scenePhase
    private let showsPerformanceHUD = ProcessInfo.processInfo.environment["JIMMY_SHOW_PERF_HUD"] == "1"
    private let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    
    // MARK: - Logging
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "JimmyApp")

    init() {
        _ = DIContainer.shared
        _ = DIContainer.shared.podcastService

        if !isRunningUnitTests {
            configureTips()

            // Register background tasks
            BackgroundTaskManager.shared.registerBackgroundTasks()

            // Collect crash/hang diagnostics via MetricKit
            MetricsSubscriber.shared.start()
        }
        
        // Apply dark mode setting
        applyInitialDarkModeSetting()
        
        // Configure audio session
        if !isRunningUnitTests {
            configureAudioSession()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                HostTabBarControllerRepresentable()
                    .ignoresSafeArea()

                #if DEBUG
                if showsPerformanceHUD {
                    PerformanceDebugOverlay()
                }
                #endif
            }
            .environment(ShellStore.shared)
            .environment(ShellStore.shared.chrome)
            .environment(InteractionLatencyTracker.shared)
            .fullScreenCover(
                isPresented: Binding(
                    get: { ShellStore.shared.presentation == .nowPlaying },
                    set: { isPresented in
                        if !isPresented {
                            ShellStore.shared.chrome.isPresentingModal = false
                            ShellStore.shared.clearPresentation()
                        }
                    }
                )
            ) {
                ExpandedNowPlayingView {
                    ShellStore.shared.chrome.isPresentingModal = false
                    ShellStore.shared.clearPresentation()
                }
                .environment(ShellStore.shared)
                .environment(ShellStore.shared.chrome)
                .environment(InteractionLatencyTracker.shared)
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    // MARK: - Initialization

    private func configureTips() {
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

        // DIContainer already initialized in init(); avoid redundant second access
        let dbStart = CFAbsoluteTimeGetCurrent()
        _ = DatabaseManager.shared
        let dbElapsed = CFAbsoluteTimeGetCurrent() - dbStart

        let audioStart = CFAbsoluteTimeGetCurrent()
        _ = AudioPlayerService.shared
        let audioElapsed = CFAbsoluteTimeGetCurrent() - audioStart

        let criticalElapsed = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("Critical services initialized in \(String(format: "%.3f", criticalElapsed))s | DatabaseManager: \(String(format: "%.3f", dbElapsed))s | AudioPlayerService: \(String(format: "%.3f", audioElapsed))s")
        
        // Background initialization for non-critical services
        // These will initialize lazily when first accessed
        Task.detached(priority: .background) {
            let bgStart = CFAbsoluteTimeGetCurrent()
            
            // Network (needed for data fetching, but not blocking UI)
            _ = UnifiedNetworkService.shared
            
            // Utilities & Engines (Lazy load in background)
            await self.initializeUtilityServices()
            
            // Post-launch tasks
            SimplePerformanceMonitor.shared.startMonitoring()

            // Start iCloud KVS sync observer
            await MainActor.run {
                AppDataDocument.startObservingICloudChanges()
            }
            
            let bgElapsed = CFAbsoluteTimeGetCurrent() - bgStart
            Self.logger.info("Background services initialized in \(String(format: "%.3f", bgElapsed))s")
        }
    }
    
    private func initializeUtilityServices() async {
        // These are truly non-critical services - initialize in background
        // with low priority to avoid main thread contention
        
        // Only initialize ResourceMonitor - other services will be lazy loaded on demand
        ResourceMonitor.shared.startMonitoring()
        
        // NOTE: The following services are now lazy-loaded when first accessed:
        // - ShakeUndoManager.shared
        // - SharedAudioImporter.shared
        // - BulletproofAudioImporter.shared
        // - CrashPreventionManager.shared
        // - LoadingStateManager.shared
        // - PodcastEngine.shared
        // - SubscriptionViewModel.shared
    }
    
    // MARK: - App Setup
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            Self.logger.error("Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard !isRunningUnitTests else {
            return
        }

        switch newPhase {
        case .background:
            Task.detached(priority: .background) {
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
            if url.isFileURL {
                await BulletproofAudioImporter.shared.handleSharedFile(from: url)
            } else if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let queryItems = components.queryItems,
                      let feedURLString = queryItems.first(where: { $0.name == "url" })?.value,
                      let feedURL = URL(string: feedURLString) {
                _ = try? await PodcastService.shared.addPodcast(from: feedURL)
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

// MARK: - Service Container

/// Container for managing service lifecycle and dependencies
@MainActor
class ServiceContainer: ObservableObject {
    lazy var uiUpdateService = UIUpdateService.shared
    lazy var shakeUndoManager = ShakeUndoManager.shared
    lazy var uiPerformanceManager = UIPerformanceManager.shared
}

// MARK: - UIKit Bridge

struct HostTabBarControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> StandardTabBarController {
        return StandardTabBarController()
    }
    
    func updateUIViewController(_ uiViewController: StandardTabBarController, context: Context) {
        // No updates needed
    }
}
