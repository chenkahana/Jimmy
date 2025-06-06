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
    @State private var selectedTab: Int = 3
    @State private var isInitializing = true
    @ObservedObject private var updateService = EpisodeUpdateService.shared
    @ObservedObject private var undoManager = ShakeUndoManager.shared

    // PERFORMANCE FIX: Track which tabs have been loaded to prevent unnecessary reloads
    @State private var loadedTabs: Set<Int> = []
    @State private var isTabSwitching = false
    
    var body: some View {
        ZStack {
            if isInitializing {
                // Simple loading view during initialization
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "waveform.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundStyle(Color.accentColor)
                        
                        Text("Jimmy")
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                .onAppear {
                    // Hide loading view after brief delay to allow background initialization
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isInitializing = false
                        }
                    }
                }
            } else {
                // Main app content
                mainAppContent
            }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
    }
    
    private var mainAppContent: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                // Main content area with tab bar
                VStack(spacing: 0) {
                    // PERFORMANCE FIX: Lazy tab loading with background queue preparation
                    // Main content area - Custom tab switching without intermediate glimpses
                    ZStack {
                        // Show only the selected tab content with lazy loading
                        if selectedTab == 0 {
                            LazyTabContentView(tabIndex: 0, isSelected: selectedTab == 0, loadedTabs: $loadedTabs) {
                                NavigationView {
                                    DiscoverView()
                                }
                            }
                            .transition(.opacity)
                        } else if selectedTab == 1 {
                            LazyTabContentView(tabIndex: 1, isSelected: selectedTab == 1, loadedTabs: $loadedTabs) {
                                NavigationView {
                                    QueueView()
                                }
                            }
                            .transition(.opacity)
                        } else if selectedTab == 2 {
                            LazyTabContentView(tabIndex: 2, isSelected: selectedTab == 2, loadedTabs: $loadedTabs) {
                                CurrentPlayView()
                            }
                            .transition(.opacity)
                        } else if selectedTab == 3 {
                            LazyTabContentView(tabIndex: 3, isSelected: selectedTab == 3, loadedTabs: $loadedTabs) {
                                LibraryView()
                            }
                            .transition(.opacity)
                        } else if selectedTab == 4 {
                            LazyTabContentView(tabIndex: 4, isSelected: selectedTab == 4, loadedTabs: $loadedTabs) {
                                NavigationView {
                                    SettingsView()
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped() // Ensure no content leaks outside bounds
                    
                    // Custom Tab Bar with Enhanced 3D
                    CustomTabBar(selectedTab: $selectedTab, isTabSwitching: $isTabSwitching)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                    
                // Floating Mini Player - Above tab bar with enhanced 3D effect
                VStack {
                    Spacer()
                    FloatingMiniPlayerView(
                        onTap: {
                            // PERFORMANCE FIX: Prevent rapid tab switching
                            guard !isTabSwitching else { return }
                            
                            // Switch to "Now Playing" tab when mini player is tapped
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = 2
                            }
                        },
                        currentTab: selectedTab
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 88) // Position above tab bar (tab bar height ~76px + spacing)
                }
            }
            
            // Undo toast notification
            if undoManager.showUndoToast {
                UndoToastView(
                    message: undoManager.undoToastMessage,
                    isShowing: $undoManager.showUndoToast
                )
                .zIndex(1000) // Ensure it appears above everything
            }
        }
    }
    

    
    struct CustomTabBar: View {
        @Binding var selectedTab: Int
        @Binding var isTabSwitching: Bool
        
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
                            isTabSwitching: isTabSwitching,
                            onTap: {
                                // PERFORMANCE FIX: Simple debounce without blocking UI
                                guard selectedTab != index else { return }
                                
                                isTabSwitching = true
                                
                                // Fast, smooth tab switching
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = index
                                }
                                
                                // Quick reset to allow next tab switch
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isTabSwitching = false
                                }
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
                    // Enhanced 3D background with depth
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color("SurfaceElevated"),
                                    Color("SurfaceElevated").opacity(0.95),
                                    Color("DarkBackground").opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Top highlight line for 3D effect
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color("SurfaceHighlighted").opacity(0.3),
                                    Color("SurfaceHighlighted").opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                        .offset(y: -44)
                }
                .ignoresSafeArea(.all, edges: .bottom)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -4)
            }
        }
    }
    
    struct TabBarButton: View {
        let tab: TabItem
        let isSelected: Bool
        let isTabSwitching: Bool
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                VStack(spacing: 2) {
                    ZStack {
                        // Enhanced 3D background indicator for selected state
                        if isSelected {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.accentColor.opacity(0.2),
                                                Color.accentColor.opacity(0.1),
                                                Color.accentColor.opacity(0.05)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 64, height: 32)
                                
                                // Inner highlight for 3D effect
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.accentColor.opacity(0.4),
                                                Color.accentColor.opacity(0.1)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.5
                                    )
                                    .frame(width: 64, height: 32)
                            }
                            .shadow(color: Color.accentColor.opacity(0.2), radius: 4, x: 0, y: 2)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.8)),
                                removal: .opacity.combined(with: .scale(scale: 0.8))
                            ))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                        }
                        
                        // Tab icon
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(
                                isSelected ?
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.accentColor,
                                        Color.accentColor.opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(.systemGray2),
                                        Color(.systemGray3)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isSelected ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    }
                    
                    // Tab title (only show for selected tab)
                    if isSelected {
                        Text(tab.title)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.accentColor,
                                        Color.accentColor.opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .move(edge: .bottom))
                            ))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
                    } else {
                        Text("")
                            .font(.caption2)
                            .opacity(0)
                            .frame(height: 12) // Maintain consistent spacing
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(TabBarButtonStyle())
        }
    }
    
    struct TabBarButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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

// PERFORMANCE FIX: Optimized lazy tab content view for fast switching
struct LazyTabContentView<Content: View>: View {
    let tabIndex: Int
    let isSelected: Bool
    @Binding var loadedTabs: Set<Int>
    let content: () -> Content
    
    var body: some View {
        Group {
            if isSelected || loadedTabs.contains(tabIndex) {
                content()
                    .opacity(isSelected ? 1 : 0)
                    .onAppear {
                        // Mark this tab as loaded once
                        if !loadedTabs.contains(tabIndex) {
                            loadedTabs.insert(tabIndex)
                        }
                    }
            } else {
                // Minimal placeholder for unloaded tabs
                Color.clear
            }
        }
    }
}
