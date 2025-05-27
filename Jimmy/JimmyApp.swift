//
//  JimmyApp.swift
//  Jimmy
//
//  Created by Chen Kahana on 23/05/2025.
//

import SwiftUI

@main
struct JimmyApp: App {
    // Initialize the update service
    private let updateService = EpisodeUpdateService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleURL(url)
                }
                .onAppear {
                    // Ensure background updates are running
                    updateService.startPeriodicUpdates()
                }
        }
    }
    
    private func handleURL(_ url: URL) {
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
                                print("Successfully imported \"\(podcast.title)\" via URL scheme!")
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
