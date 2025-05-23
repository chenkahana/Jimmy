//
//  ContentView.swift
//  Jimmy
//
//  Created by Chen Kahana on 23/05/2025.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("darkMode") private var darkMode: Bool = false
    @AppStorage("highContrastMode") private var highContrastMode: Bool = false
    @State private var selectedEpisode: Episode?
    
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                PodcastSearchView()
                    .tabItem {
                        Label("Discover", systemImage: "globe")
                    }
                QueueView()
                    .tabItem {
                        Label("Queue", systemImage: "list.bullet")
                    }
                CurrentPlayView()
                    .tabItem {
                        Label("Current Play", systemImage: "play.circle")
                    }
                PodcastListView()
                    .tabItem {
                        Label("Subscriptions", systemImage: "heart.fill")
                    }
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            
            // Mini Player at bottom
            MiniPlayerView(onTap: {
                if let currentEpisode = AudioPlayerService.shared.currentEpisode {
                    selectedEpisode = currentEpisode
                }
            })
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .sheet(item: $selectedEpisode) { episode in
            EpisodePlayerView(episode: episode)
        }
    }
}

#Preview {
    ContentView()
}
