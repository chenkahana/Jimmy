import SwiftUI
import UniformTypeIdentifiers

/// Clean Architecture App Entry Point
/// Uses dependency injection and structured concurrency
@main
struct CleanJimmyApp: App {
    // MARK: - Dependency Injection
    private let container = DIContainer.shared
    
    // MARK: - Background Coordinators
    private let backgroundTaskCoordinator = BackgroundTaskCoordinator.shared
    private let backgroundRefreshCoordinator = BackgroundRefreshCoordinator.shared
    
    // MARK: - State
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFileImportSheet = false
    @State private var pendingAudioURL: URL?
    @State private var viewModelsReady = false
    
    var body: some Scene {
        WindowGroup {
            Group {
                if viewModelsReady {
                    ContentView()
                        .environmentObject(UIUpdateService.shared)
                        .onAppear {
                            setupApp()
                        }
                } else {
                    AppLoadingView(progress: .constant(0.5))
                        .task {
                            await setupViewModels()
                        }
                }
            }
            .onOpenURL { url in
                handleURL(url)
            }
            .sheet(isPresented: $showFileImportSheet) {
                if let audioURL = pendingAudioURL {
                    FileImportNamingView(audioURL: audioURL) { fileName, showName, existingShowID in
                        Task {
                            await handleFileImport(
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    // MARK: - App Setup
    
    @MainActor
    private func setupViewModels() async {
        // Initialize ViewModels on MainActor
        _ = container.libraryViewModel
        _ = container.queueViewModel
        _ = container.discoveryViewModel
        viewModelsReady = true
    }
    
    private func setupApp() {
        Task { @MainActor in
            // Show immediate UI first
            await loadCachedData()
            
            // MEMORY FIX: Remove Task.detached to prevent background task accumulation
            // Initialize services synchronously to prevent memory leaks
            await initializeBackgroundServices()
        }
    }
    
    private func loadCachedData() async {
        // Load cached data immediately for responsive UI
        await container.libraryViewModel.refreshData()
    }
    
    private func initializeBackgroundServices() async {
        // MEMORY FIX: Initialize services on main actor to prevent memory leaks
        await backgroundRefreshCoordinator.startRefresh()
        
        // MEMORY FIX: Initialize memory monitoring
        _ = MemoryMonitor.shared
        
        // Setup file import handling
        setupFileImportCallback()
        
        // MEMORY FIX: Don't schedule background refresh to prevent memory accumulation
        // Only refresh when explicitly needed
        
        await backgroundRefreshCoordinator.finishRefresh()
    }
    
    // MARK: - URL Handling
    
    private func handleURL(_ url: URL) {
        Task {
            if url.isFileURL {
                await handleFileURL(url)
            } else {
                await handlePodcastURL(url)
            }
        }
    }
    
    private func handleFileURL(_ url: URL) async {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
              type.conforms(to: .audio) else {
            return
        }
        
        await MainActor.run {
            pendingAudioURL = url
            showFileImportSheet = true
        }
    }
    
    private func handlePodcastURL(_ url: URL) async {
        guard url.scheme == "jimmy",
              url.host == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let podcastURLString = queryItems.first(where: { $0.name == "url" })?.value,
              let podcastURL = URL(string: podcastURLString) else {
            return
        }
        
        await container.libraryViewModel.subscribeToPodcast(feedURL: podcastURL)
    }
    
    // MARK: - File Import
    
    private func setupFileImportCallback() {
        // This would be handled by a file import service in the clean architecture
        // For now, we'll keep it simple
    }
    
    private func handleFileImport(
        from url: URL,
        fileName: String,
        showName: String,
        existingShowID: UUID?
    ) async {
        // This would use a file import use case in the clean architecture
        // For now, we'll delegate to the existing service
        SharedAudioImporter.shared.importFile(
            from: url,
            fileName: fileName,
            showName: showName,
            existingShowID: existingShowID
        )
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            Task {
                await saveAppState()
            }
        case .active:
            Task {
                await refreshDataIfNeeded()
            }
        @unknown default:
            break
        }
    }
    
    private func saveAppState() async {
        // Save current state using repositories
        // This is handled automatically by the stores and repositories
    }
    
    private func refreshDataIfNeeded() async {
        if await backgroundRefreshCoordinator.shouldRefresh() {
            await container.libraryViewModel.refreshData()
        }
    }
    
    // MARK: - Background Refresh
    
    private func scheduleBackgroundRefresh() async {
        // MEMORY FIX: Remove Task.detached to prevent untracked background tasks
        // Use regular Task instead
        Task(priority: .background) {
            await refreshAllData()
        }
    }
    
    private func refreshAllData() async {
        // Refresh all data in background
        await container.libraryViewModel.refreshData()
    }
}

// MARK: - Clean Content View

/// Main content view using clean architecture ViewModels
struct CleanContentView: View {
    @EnvironmentObject var libraryViewModel: CleanLibraryViewModel
    @EnvironmentObject var queueViewModel: CleanQueueViewModel
    @EnvironmentObject var discoveryViewModel: CleanDiscoveryViewModel
    
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CleanLibraryView()
                .environmentObject(libraryViewModel)
                .tabItem {
                    Image(systemName: "books.vertical")
                    Text("Library")
                }
                .tag(0)
            
            CleanDiscoveryView()
                .environmentObject(discoveryViewModel)
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Discover")
                }
                .tag(1)
            
            CleanQueueView()
                .environmentObject(queueViewModel)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Queue")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
    }
}

// MARK: - Clean Views (Placeholder implementations)

struct CleanLibraryView: View {
    @EnvironmentObject var viewModel: CleanLibraryViewModel
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                } else {
                    List(viewModel.filteredPodcasts, id: \.id) { podcast in
                        VStack(alignment: .leading) {
                            Text(podcast.title)
                                .font(.headline)
                            Text(podcast.author)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .refreshable {
                await viewModel.refreshData()
            }
            .searchable(text: $viewModel.searchText)
        }
    }
}

struct CleanDiscoveryView: View {
    @EnvironmentObject var viewModel: CleanDiscoveryViewModel
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isSearching {
                    ProgressView("Searching...")
                } else {
                    List(viewModel.searchResults, id: \.id) { podcast in
                        VStack(alignment: .leading) {
                            Text(podcast.title)
                                .font(.headline)
                            Text(podcast.author)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Subscribe") {
                                Task {
                                    await viewModel.subscribeToPodcast(feedURL: podcast.feedURL)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $viewModel.searchText)
        }
    }
}

struct CleanQueueView: View {
    @EnvironmentObject var viewModel: CleanQueueViewModel
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(viewModel.queue.enumerated()), id: \.element.id) { index, episode in
                    VStack(alignment: .leading) {
                        Text(episode.title)
                            .font(.headline)
                        if index == viewModel.currentIndex {
                            Text("Now Playing")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .onTapGesture {
                        Task {
                            await viewModel.playEpisode(at: index)
                        }
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await viewModel.removeEpisode(at: index)
                        }
                    }
                }
                .onMove { source, destination in
                    Task {
                        if let sourceIndex = source.first {
                            await viewModel.moveEpisode(from: sourceIndex, to: destination)
                        }
                    }
                }
            }
            .navigationTitle("Queue")
        }
    }
} 