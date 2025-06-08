//
//  ContentView.swift
//  Jimmy
//
//  Created by Chen Kahana on 23/05/2025.
//

import SwiftUI
import AVFoundation

// MARK: - Notification Extensions
extension Notification.Name {
    static let appInitializationComplete = Notification.Name("appInitializationComplete")
}

struct ContentView: View {
    @StateObject private var episodeViewModel = EpisodeViewModel.shared
    @StateObject private var podcastService = PodcastService.shared
    @StateObject private var audioPlayer = AudioPlayerService.shared
    @StateObject private var queueViewModel = QueueViewModel.shared
    @StateObject private var undoManager = ShakeUndoManager.shared
    @StateObject private var uiPerformanceManager = UIPerformanceManager.shared
    
    @AppStorage("darkMode") private var darkMode = false
    @State private var isInitializing = true
    @State private var isTabSwitching = false
    
    // WORLD-CLASS NAVIGATION: Pre-instantiated views for instant switching
    @State private var discoverView = AnyView(NavigationView { DiscoverView() })
    @State private var queueView = AnyView(NavigationView { QueueView() })
    @State private var currentPlayView = AnyView(CurrentPlayView())
    @State private var libraryView = AnyView(LibraryView())
    @State private var settingsView = AnyView(NavigationView { SettingsView() })
    
    private var selectedTab: Int { uiPerformanceManager.currentTab }
    
    var body: some View {
        ZStack {
            if isInitializing {
                // Loading screen
                ZStack {
                    Color("DarkBackground")
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.accentColor)
                            .scaleEffect(1.2)
                        
                        Text("Jimmy")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.accentColor)
                    }
                }
                .onAppear {
                    checkInitializationStatus()
                }
                .onReceive(NotificationCenter.default.publisher(for: .appInitializationComplete)) { _ in
                    // Hide loading screen when initialization is actually complete
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isInitializing = false
                    }
                }
            } else {
                // Main app content
                mainAppContent
            }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
    }
    
    private func checkInitializationStatus() {
        // Check if core services are ready using async/await instead of blocking
        Task {
            var isReady = false
            var attempts = 0
            let maxAttempts = 20 // 2 seconds max (20 * 0.1s)
            
            while !isReady && attempts < maxAttempts {
                // Check if essential services are initialized
                let episodesLoaded = !episodeViewModel.episodes.isEmpty || episodeViewModel.hasAttemptedLoad
                let podcastsLoaded = !podcastService.loadPodcasts().isEmpty || podcastService.hasAttemptedLoad
                
                isReady = episodesLoaded && podcastsLoaded
                
                if !isReady {
                    // Use Task.sleep instead of Thread.sleep to avoid blocking
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    attempts += 1
                }
            }
            
            await MainActor.run {
                if isReady || attempts >= maxAttempts {
                    NotificationCenter.default.post(name: .appInitializationComplete, object: nil)
                }
            }
        }
    }
    
    private var mainAppContent: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                // WORLD-CLASS NAVIGATION: Instant tab switching with pre-loaded views
                VStack(spacing: 0) {
                    // CRITICAL FIX: Only load the current view to prevent background processing
                    Group {
                        switch selectedTab {
                        case 0:
                            discoverView
                        case 1:
                            queueView
                        case 2:
                            currentPlayView
                        case 3:
                            libraryView
                        case 4:
                            settingsView
                        default:
                            libraryView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    
                    // Custom Tab Bar - Optimized for speed
                    CustomTabBar()
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                    
                // Floating Mini Player
                VStack {
                    Spacer()
                    FloatingMiniPlayerView(
                        onTap: {
                            uiPerformanceManager.switchToTab(2)
                        },
                        currentTab: selectedTab
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 88)
                }
            }
            
            // Undo toast notification
            if undoManager.showUndoToast {
                UndoToastView(
                    message: undoManager.undoToastMessage,
                    isShowing: $undoManager.showUndoToast
                )
                .zIndex(1000)
            }
        }
    }
    
    struct CustomTabBar: View {
        @ObservedObject private var uiPerformanceManager = UIPerformanceManager.shared
        
        private var selectedTab: Int { uiPerformanceManager.currentTab }
        
        let tabs = [
            TabItem(title: "Discover", icon: "globe", selectedIcon: "globe"),
            TabItem(title: "Queue", icon: "list.bullet", selectedIcon: "list.bullet"),
            TabItem(title: "Now Playing", icon: "play.circle", selectedIcon: "play.circle.fill"),
            TabItem(title: "Library", icon: "waveform.circle", selectedIcon: "waveform.circle.fill"),
            TabItem(title: "Settings", icon: "gear", selectedIcon: "gear")
        ]
        
        var body: some View {
            VStack(spacing: 0) {
                // Top border
                Rectangle()
                    .fill(Color(.separator).opacity(0.2))
                    .frame(height: 0.5)
                
                HStack(spacing: 0) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        TabBarButton(
                            tab: tabs[index],
                            isSelected: selectedTab == index,
                            onTap: {
                                // INSTANT tab switching - no delays or debouncing
                                uiPerformanceManager.switchToTab(index)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .background {
                ZStack {
                    Rectangle()
                        .fill(Color("SurfaceElevated"))
                    
                    Rectangle()
                        .fill(Color("SurfaceHighlighted").opacity(0.1))
                        .frame(height: 0.5)
                        .offset(y: -44)
                }
                .ignoresSafeArea(.all, edges: .bottom)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: -2)
            }
        }
    }
    
    struct TabBarButton: View {
        let tab: TabItem
        let isSelected: Bool
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                VStack(spacing: 2) {
                    ZStack {
                        // Minimal selected state indicator
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 56, height: 28)
                        }
                        
                        // Tab icon - no complex animations
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                    }
                    
                    // Tab title (only for selected)
                    if isSelected {
                        Text(tab.title)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    } else {
                        Text("")
                            .font(.caption2)
                            .opacity(0)
                            .frame(height: 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(InstantButtonStyle())
        }
    }
    
    struct InstantButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .opacity(configuration.isPressed ? 0.9 : 1.0)
        }
    }
    
    struct TabItem {
        let title: String
        let icon: String
        let selectedIcon: String
    }
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
}
