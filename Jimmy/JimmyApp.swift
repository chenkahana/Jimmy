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
    // Initialize the update service
    private let updateService = EpisodeUpdateService.shared
    // Initialize the undo manager for shake-to-undo functionality
    private let undoManager = ShakeUndoManager.shared
    // Initialize background task manager for BGTaskScheduler
    private let backgroundTaskManager = BackgroundTaskManager.shared
    @State private var showFileImportSheet = false
    @State private var pendingAudioURL: URL?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleURL(url)
                }
                .onAppear {
                    // Defer heavy startup operations to avoid blocking UI
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // Start background services after UI is loaded
                        updateService.startPeriodicUpdates()
                        
                        // DISABLED: Don't schedule background refresh on startup to prevent Signal 9 crashes
                        // backgroundTaskManager.scheduleBackgroundRefresh()
                        
                        // Setup shake detection for undo functionality
                        undoManager.setupShakeDetection()
                        
                        // Setup file import callback
                        setupFileImportCallback()
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
                    // Try to add the podcast using existing service
                    PodcastService.shared.addPodcast(from: feedURL) { podcast, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("Error importing podcast via URL scheme: \(error.localizedDescription)")
                                // Could show a notification or alert here
                            } else if let podcast = podcast {
    
                                // Could show a success notification here
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
