//
//  JimmyApp.swift
//  Jimmy
//
//  Created by Chen Kahana on 23/05/2025.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct JimmyApp: App {
    // MARK: - CHAT_HELP.md Architecture Services
    
    // 1. Repository (GRDB + WAL) - Core data layer
    private let repository = PodcastRepository.shared
    
    // 2. FetchWorker (Task + GCD barriers) - Network operations
    private let fetchWorker = FetchWorker.shared
    
    // 3. PodcastStore (Swift Actor) - Thread-safe storage
    private let podcastStore = PodcastStore.shared
    
    // 4. ViewModel (AsyncPublisher) - UI data binding
    private let podcastViewModel = PodcastViewModel.shared
    
    // 5. Background Refresh Service (BGAppRefreshTask)
    private let backgroundRefreshService = BackgroundRefreshService.shared
    
    // 6. Performance Monitor (os_signpost)
    private let performanceMonitor = PerformanceMonitor.shared
    
    // MARK: - Legacy Services (for compatibility)
    private let updateService = EpisodeUpdateService.shared
    private let undoManager = ShakeUndoManager.shared
    private let backgroundTaskManager = BackgroundTaskManager.shared
    private let optimizedPodcastService = OptimizedPodcastService.shared
    private let uiPerformanceManager = UIPerformanceManager.shared
    private let crashPreventionManager = CrashPreventionManager.shared
    
    // Legacy episode services (being phased out)
    private let episodeRepository = EpisodeRepository.shared
    private let episodeFetchWorker = EpisodeFetchWorker.shared
    private let enhancedEpisodeController = EnhancedEpisodeController.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFileImportSheet = false
    @State private var pendingAudioURL: URL?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(podcastViewModel)
                .environmentObject(UnifiedEpisodeController.shared)
                .environmentObject(uiPerformanceManager)
                .environmentObject(undoManager)
                .onAppear {
                    // Register background tasks for CHAT_HELP.md architecture
                    backgroundRefreshService.registerBackgroundTasks()
                    backgroundRefreshService.scheduleBackgroundRefresh()
                }
                .onOpenURL { url in
                    handleURL(url)
                }
                .onAppear {
                    // Defer heavy startup operations to avoid blocking UI
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // CRITICAL: Load from iCloud first before anything else
                        print("🔄 JimmyApp: Loading from iCloud...")
                        AppDataDocument.loadFromICloudIfEnabled()
                        
                        // DEBUG: Check what data we have after iCloud load
                        let loadedPodcasts = PodcastService.shared.loadPodcasts()
                        let episodes = UnifiedEpisodeController.shared.episodes
                        print("📊 JimmyApp: After iCloud load - Podcasts: \(loadedPodcasts.count), Episodes: \(episodes.count)")
                        
                        // RECOVERY: Check for orphaned episodes and recover missing podcasts
                        if loadedPodcasts.isEmpty && episodes.count > 0 {
                            print("🔧 JimmyApp: Detected orphaned episodes, starting recovery...")
                            Task {
                                await PodcastRecoveryService.shared.recoverMissingPodcasts()
                                // Notify LibraryController after recovery
                                await MainActor.run {
                                    NotificationCenter.default.post(name: NSNotification.Name("iCloudDataLoaded"), object: nil)
                                }
                            }
                        } else {
                            // Notify LibraryController that iCloud data has been loaded
                            NotificationCenter.default.post(name: NSNotification.Name("iCloudDataLoaded"), object: nil)
                        }
                        
                        // Start crash prevention first for maximum stability
                        crashPreventionManager.startCrashPrevention()
                        
                        // ENHANCED EPISODE ARCHITECTURE: Initialize award-winning episode system
                        print("🏆 JimmyApp: Initializing enhanced episode architecture...")
                        
                        // Repository and fetch worker are already initialized via their singletons
                        // Enhanced controller will automatically load cached data and queue background updates
                        
                        // Start optimized services first for better performance
                        let optimizedPodcasts = optimizedPodcastService.loadPodcasts()
                        if !optimizedPodcasts.isEmpty {
                            optimizedPodcastService.startBackgroundProcessing()
                        }
                        
                        // UI performance manager is now lightweight - no background processing needed
                        
                        // Start background services after UI is loaded
                        updateService.startPeriodicUpdates()
                        
                        // DISABLED: Don't schedule background refresh on startup to prevent Signal 9 crashes
                        // backgroundTaskManager.scheduleBackgroundRefresh()
                        
                        // Setup shake detection for undo functionality
                        undoManager.setupShakeDetection()
                        
                        // Setup file import callback
                        setupFileImportCallback()
                        
                        print("✅ JimmyApp: Enhanced episode architecture initialized successfully!")
                    }
                }
                .sheet(isPresented: $showFileImportSheet) {
                    if let audioURL = pendingAudioURL {
                        FileImportNamingView(audioURL: audioURL) { fileName, showName, existingShowID in
                            SharedAudioImporter.shared.importFile(
                                from: audioURL,
                                fileName: fileName,
                                showName: showName,
                                existingShowID: existingShowID
                            )
                            pendingAudioURL = nil
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background, .inactive:
                // App is moving to the background or becoming inactive.
                // This is the last chance to save data.
                // Note: UnifiedEpisodeController doesn't have saveImmediately method
                // Saving is now handled automatically by the repository
                // EpisodeRepository.shared.saveImmediately()
                break
            case .active:
                // App is now active.
                break
            @unknown default:
                break
            }
        }
    }
    
    private func setupFileImportCallback() {
        SharedAudioImporter.shared.onFileRequiresNaming = { url in
            pendingAudioURL = url
            showFileImportSheet = true
        }
    }
    
    private func handleURL(_ url: URL) {
        // If a local audio file was shared to the app, trigger the naming popup
        if url.isFileURL {
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               type.conforms(to: .audio) {
                SharedAudioImporter.shared.handleSharedFile(from: url)
            }
            return
        }

        // Handle jimmy://import?url=PODCAST_URL
        guard url.scheme == "jimmy",
              url.host == "import" else {
            return
        }
        
        // Extract the podcast URL from the query parameters
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let queryItems = components?.queryItems,
              let podcastURLString = queryItems.first(where: { $0.name == "url" })?.value,
              let podcastURL = URL(string: podcastURLString) else {
            return
        }
        
        // Import the podcast
        importPodcastFromURL(podcastURL)
    }
    
    private func importPodcastFromURL(_ url: URL) {
        // Use the existing URL resolver to get RSS feed
        PodcastURLResolver.shared.resolveToRSSFeed(from: url.absoluteString) { feedURL in
            DispatchQueue.main.async {
                if let feedURL = feedURL {
                    // Try to add the podcast using existing service with async/await
                    Task {
                        do {
                            let podcast = try await PodcastService.shared.addPodcast(from: feedURL)
                            await MainActor.run {
                                print("Successfully imported podcast: \(podcast.title)")
                                // Could show a success notification here
                            }
                        } catch {
                            await MainActor.run {
                                print("Error importing podcast via URL scheme: \(error.localizedDescription)")
                                // Could show a notification or alert here
                            }
                        }
                    }
                } else {
                    print("Could not find RSS feed for URL: \(url.absoluteString)")
                }
            }
        }
    }
}
