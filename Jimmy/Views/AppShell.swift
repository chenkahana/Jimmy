import SwiftUI

/// Queue, Library and Search, with the mini player as the tab bar's bottom accessory.
struct AppShell: View {
    @Environment(AppModel.self) private var appModel
    @Bindable private var shell = ShellStore.shared
    @ObservedObject private var audioImporter = LocalAudioImporter.shared
    @Bindable private var onboarding = Onboarding.shared
    /// The last tab open, so a relaunch comes back to it even after the app was quit.
    @AppStorage("selectedTab") private var savedTab = ShellTab.queue.rawValue
    /// Morphs the mini player's artwork into Now Playing's on open, and back on an interactive dismiss.
    @Namespace private var nowPlayingNamespace

    var body: some View {
        TabView(selection: Binding(get: { shell.selectedTab }, set: { shell.handleUserSelectedTab($0) })) {
            Tab("Queue", systemImage: "list.bullet", value: ShellTab.queue) {
                NavigationStack { QueueView() }
            }
            Tab("Library", systemImage: "music.note.list", value: ShellTab.library) {
                NavigationStack { LibraryView() }
            }
            Tab(value: ShellTab.search, role: .search) {
                NavigationStack { DiscoverView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: appModel.playback?.currentEpisode != nil) {
            NativeMiniPlayerView(namespace: nowPlayingNamespace) {
                Task { await MiniPlayerTip.openedNowPlaying.donate() }
                shell.present(.nowPlaying)
            }
        }
        .modifier(OutcomeAnnouncements())
        .sheet(isPresented: Binding(
            get: { shell.presentation == .nowPlaying },
            set: { isPresented in if !isPresented { shell.clearPresentation() } }
        )) {
            ExpandedNowPlayingView {
                shell.clearPresentation()
            }
            .navigationTransition(.zoom(sourceID: NowPlayingGeometryID.artwork, in: nowPlayingNamespace))
            .environment(ShellStore.shared)
            .environment(InteractionLatencyTracker.shared)
            .environment(appModel)
        }
        .onAppear {
            // Demo screenshots always start on Queue.
            guard !DemoLibrary.isRequested(), let tab = ShellTab(rawValue: savedTab), tab != shell.selectedTab else { return }
            shell.handleUserSelectedTab(tab)
        }
        .onChange(of: shell.selectedTab) { _, tab in savedTab = tab.rawValue }
        .fullScreenCover(isPresented: $onboarding.isPresented) {
            OnboardingView()
        }
        .sheet(item: $shell.sheet) { sheet in
            switch sheet {
            case .settings:
                NavigationStack { SettingsView().toolbar { doneButton } }
            case .addByURL:
                ManualImportView()
            case .stats:
                NavigationStack { ListeningStatsView().toolbar { doneButton } }
            case .feedback:
                FeedbackFormView()
            }
        }
        .sheet(isPresented: Binding(
            get: { audioImporter.pendingURL != nil },
            set: { if !$0 { audioImporter.pendingURL = nil } }
        )) {
            if let url = audioImporter.pendingURL {
                LocalAudioImportView(
                    audioURL: url,
                    onSuccess: { _ in audioImporter.pendingURL = nil },
                    onCancel: { audioImporter.pendingURL = nil }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { shell.sheet = nil }
        }
    }
}

/// Library's `ellipsis.circle` menu: everything that isn't a tab.
struct ShellMenu: View {
    @Environment(ShellStore.self) private var shell

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Settings", systemImage: "gearshape") { shell.sheet = .settings }
            Button("Add Podcast by URL", systemImage: "link") { shell.sheet = .addByURL }
            Button("Listening Stats", systemImage: "chart.bar") { shell.sheet = .stats }
            Button("Send Feedback", systemImage: "envelope") { shell.sheet = .feedback }
        }
    }
}
