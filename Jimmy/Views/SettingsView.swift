import SwiftUI

struct SettingsView: View {
    @AppStorage("playbackSpeed") private var playbackSpeed: Double = 1.0
    @AppStorage("darkMode") private var darkMode: Bool = true
    @AppStorage("episodeSwipeAction") private var episodeSwipeAction: String = "addToQueue"
    @AppStorage("queueSwipeAction") private var queueSwipeAction: String = "markAsPlayed"
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = true
    @AppStorage("highContrastMode") private var highContrastMode: Bool = false
    @AppStorage("autoRestoreLastEpisode") private var autoRestoreLastEpisode: Bool = true
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingAnalytics = false
    @State private var isImportingFromApplePodcasts = false
    @State private var showingManualImport = false
    @State private var showingShortcutsGuide = false
    @State private var isSpotifyImporting = false
    @State private var spotifyImportMessage: String?
    @State private var showingFeedbackForm = false
    @State private var activeAlert: SettingsAlert?
    @State private var showDeleteConfirmation = false
    @State private var isJSONImporting = false
    @State private var jsonImportMessage: String?
    @State private var showClearSubscriptionsConfirmation = false

    enum SettingsAlert {
        case resetData
        case appleImport(String)
        case spotifyImport(String)
        case jsonImport(String)
        case clearSubscriptions
        case subscriptionImport(String) // Keep for management operations
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Settings")
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                    
                    Text("Customize your podcast experience")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Playback Section
                SettingsCard(
                    title: "Playback",
                    icon: "play.circle.fill",
                    iconColor: .green
                ) {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("Playback Speed")
                                .font(.body.weight(.medium))
                            Spacer()
                            Picker("", selection: $playbackSpeed) {
                                Text("0.75x").tag(0.75)
                                Text("1x").tag(1.0)
                                Text("1.25x").tag(1.25)
                                Text("1.5x").tag(1.5)
                                Text("2x").tag(2.0)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: playbackSpeed) { oldValue, newValue in
                                AudioPlayerService.shared.updatePlaybackSpeed(Float(newValue))
                            }
                        }
                        
                        SettingsToggle(
                            title: "Auto-Load Last Episode",
                            subtitle: "Loads your last episode when the app opens",
                            icon: "arrow.clockwise.circle.fill",
                            isOn: $autoRestoreLastEpisode
                        )
                    }
                }
                
                // Appearance Section
                SettingsCard(
                    title: "Appearance",
                    icon: "paintbrush.fill",
                    iconColor: .purple
                ) {
                    VStack(spacing: 12) {
                        SettingsToggle(
                            title: "Dark Mode",
                            subtitle: darkMode ? "Currently using dark appearance" : "Currently using light appearance",
                            icon: darkMode ? "moon.fill" : "sun.max.fill",
                            isOn: $darkMode
                        )
                        
                        SettingsToggle(
                            title: "High Contrast Mode",
                            icon: "eye.circle.fill",
                            isOn: $highContrastMode
                        )
                    }
                }
                
                // Data & Sync Section
                SettingsCard(
                    title: "Data & Sync",
                    icon: "icloud.fill",
                    iconColor: .blue
                ) {
                    VStack(spacing: 12) {
                        SettingsToggle(
                            title: "iCloud Sync",
                            subtitle: "Sync your data across devices",
                            icon: "icloud.circle.fill",
                            isOn: $iCloudSyncEnabled
                        )
                        
                        SettingsButton(
                            title: "Export App Data",
                            subtitle: "Backup your podcasts and settings",
                            icon: "square.and.arrow.up.circle.fill",
                            action: { isExporting = true }
                        )
                    }
                }
                // Podcast Import Section
                SettingsCard(
                    title: "Podcast Import",
                    icon: "square.and.arrow.down.fill",
                    iconColor: .orange
                ) {
                    VStack(spacing: 16) {
                        // JSON import - primary option
                        ImportButton(
                            title: "Import from JSON File",
                            subtitle: "Import podcasts from a JSON file with title, publisher, and url fields",
                            icon: "doc.text.fill",
                            isLoading: isJSONImporting,
                            action: { isJSONImporting = true }
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Other import methods
                        ImportButton(
                            title: "Import from Spotify",
                            subtitle: "Import from Spotify playlist export",
                            icon: "music.note.list",
                            action: { isSpotifyImporting = true }
                        )
                        
                        ImportButton(
                            title: "Import from Apple Podcasts",
                            subtitle: "Get all your Apple Podcasts subscriptions",
                            icon: "externaldrive.badge.plus",
                            isLoading: isImportingFromApplePodcasts,
                            action: { performComprehensiveApplePodcastsImport() }
                        )
                        
                        ImportButton(
                            title: "Add Single Podcast by URL",
                            subtitle: "Import one podcast by RSS feed URL",
                            icon: "plus.circle.fill",
                            action: { showingManualImport = true }
                        )
                    }
                }
                
                // Management Section
                SettingsCard(
                    title: "Management",
                    icon: "folder.fill",
                    iconColor: .red
                ) {
                    VStack(spacing: 12) {
                        SettingsButton(
                            title: "Clear All Subscriptions",
                            subtitle: "Remove all podcasts and episodes",
                            icon: "trash.circle.fill",
                            isDestructive: true,
                            action: { showClearSubscriptionsConfirmation = true }
                        )
                        
                        NavigationLink(destination: DocumentationView()) {
                            HStack {
                                Image(systemName: "book.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Browse Documentation")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                    Text("Help and guides")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        SettingsButton(
                            title: "Submit Feedback",
                            subtitle: "Report bugs or request features",
                            icon: "envelope.circle.fill",
                            action: { showingFeedbackForm = true }
                        )
                    }
                }
                
                // Debug Section (Developer Mode)
                SettingsCard(
                    title: "Developer Tools",
                    icon: "hammer.fill",
                    iconColor: .gray
                ) {
                    VStack(spacing: 12) {
                        SettingsButton(
                            title: "View Analytics",
                            subtitle: "App usage statistics",
                            icon: "chart.bar.fill",
                            action: { showingAnalytics = true }
                        )
                        
                        SettingsButton(
                            title: "Clear Episode Cache",
                            subtitle: "Free up storage space",
                            icon: "trash.circle.fill",
                            isDestructive: true,
                            action: { clearEpisodeCache() }
                        )
                        
                        SettingsButton(
                            title: "Force Fetch Episodes",
                            subtitle: "Refresh all episode data",
                            icon: "arrow.clockwise.circle.fill",
                            action: { forceFetchAllEpisodes() }
                        )
                        
                        SettingsButton(
                            title: "Recover Episodes & Queue",
                            subtitle: "Fix missing episodes",
                            icon: "wrench.and.screwdriver.fill",
                            isDestructive: true,
                            action: { recoverEpisodesAndQueue() }
                        )
                        
                        SettingsButton(
                            title: "Reset All Data",
                            subtitle: "Complete app reset",
                            icon: "exclamationmark.triangle.fill",
                            isDestructive: true,
                            action: { activeAlert = .resetData }
                        )
                    }
                }
                
                // Footer spacing
                Color.clear
                    .frame(height: 50)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Settings")
        .onAppear {
            // WORLD-CLASS NAVIGATION: Instant display with deferred operations
            
            // DEFERRED: Update playback speed in background with delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                DispatchQueue.global(qos: .background).async {
                    // CRITICAL FIX: Use asyncAfter to prevent "Publishing changes from within view updates"
                    DispatchQueue.main.async {
                        AudioPlayerService.shared.updatePlaybackSpeed(Float(playbackSpeed))
                    }
                }
            }
        }
        .fileExporter(isPresented: $isExporting, document: AppDataDocument(), contentType: .json, defaultFilename: "JimmyBackup") { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                // PERFORMANCE FIX: Move file operations to background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: url)
                        // CRITICAL FIX: Use asyncAfter to prevent "Publishing changes from within view updates"
                        Task { @MainActor in
                            do {
                                try await AppDataDocument.importData(data)
                            } catch {
                                importError = error.localizedDescription
                            }
                        }
                    } catch {
                        // CRITICAL FIX: Use asyncAfter to prevent "Publishing changes from within view updates"
                        DispatchQueue.main.async {
                            importError = error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }

        .fileImporter(isPresented: $isSpotifyImporting, allowedContentTypes: [.text, .data]) { result in
            switch result {
            case .success(let url):
                importSpotifyFile(from: url)
            case .failure(let error):
                spotifyImportMessage = "Error selecting file: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isJSONImporting, 
            allowedContentTypes: [.json, .plainText, .data, .text]
        ) { result in
            switch result {
            case .success(let url):
                print("📁 Selected file: \(url.lastPathComponent)")
                print("📁 File path: \(url.path)")
                print("📁 File exists: \(FileManager.default.fileExists(atPath: url.path))")
                importJSONFile(from: url)
            case .failure(let error):
                print("❌ File selection error: \(error)")
                DispatchQueue.main.async {
                    self.jsonImportMessage = "Error selecting file: \(error.localizedDescription)"
                    self.activeAlert = .jsonImport(self.jsonImportMessage ?? "Unknown error")
                }
            }
        }
        .sheet(isPresented: $showingAnalytics) {
            AnalyticsView()
        }
        .alert(
            alertTitle(),
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { if !$0 { activeAlert = nil } }
            )
        ) {
            alertButtons()
        } message: {
            alertMessage()
        }
        .sheet(isPresented: $showingManualImport) {
            ManualPodcastImportView()
        }
        .sheet(isPresented: $showingShortcutsGuide) {
            ShortcutsGuideSheet()
        }

        .sheet(isPresented: $showingFeedbackForm) {
            FeedbackFormView()
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete All Local Storage"),
                message: Text("Are you sure you want to delete all subscriptions and listening history? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteAllLocalStorage()
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showClearSubscriptionsConfirmation) {
            Alert(
                title: Text("Clear All Subscriptions"),
                message: Text("Are you sure you want to remove all podcast subscriptions? This will also clear your episode queue. This action cannot be undone."),
                primaryButton: .destructive(Text("Clear")) {
                    clearAllSubscriptions()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func performComprehensiveApplePodcastsImport() {
        // Prevent multiple simultaneous imports
        guard !isImportingFromApplePodcasts else { return }
        
        // Clear any existing alerts
        activeAlert = nil
        isImportingFromApplePodcasts = true
        
        ApplePodcastService.shared.importAllApplePodcastSubscriptions { podcasts, error in
            // CRITICAL FIX: Use asyncAfter to prevent "Publishing changes from within view updates"
            DispatchQueue.main.async {
                isImportingFromApplePodcasts = false
                
                let message: String
                if let error = error {
                    message = error.localizedDescription
                } else if podcasts.isEmpty {
                    message = "No new podcasts found. Use the guide below to manually import your subscriptions."
                } else {
                    var currentPodcasts = PodcastService.shared.loadPodcasts()
                    var newPodcastsImportedCount = 0
                    
                    for podcast in podcasts {
                        if !currentPodcasts.contains(where: { $0.feedURL == podcast.feedURL }) {
                            currentPodcasts.append(podcast)
                            newPodcastsImportedCount += 1
                        }
                    }
                    
                    PodcastService.shared.savePodcasts(currentPodcasts)
                    
                    if newPodcastsImportedCount == 0 {
                        message = "No new podcasts imported - all found podcasts are already in your library."
                    } else {
                        message = "🎉 Successfully imported \(newPodcastsImportedCount) podcast(s)!"
                    }
                }
                
                self.activeAlert = .appleImport(message)
            }
        }
    }
    


    private func importSpotifyFile(from url: URL) {
        spotifyImportMessage = "Processing file..."
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        // PERFORMANCE FIX: Move file operations to background thread
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url) else {
                DispatchQueue.main.async {
                    self.spotifyImportMessage = "Could not read file"
                    self.activeAlert = .spotifyImport(self.spotifyImportMessage ?? "")
                }
                return
            }

            let urls = SpotifyListParser.parse(data: data)
            guard !urls.isEmpty else {
                DispatchQueue.main.async {
                    self.spotifyImportMessage = "No URLs found in file"
                    self.activeAlert = .spotifyImport(self.spotifyImportMessage ?? "")
                }
                return
            }

            // Move back to main thread for podcast operations
            DispatchQueue.main.async {
                var current = PodcastService.shared.loadPodcasts()
                var newCount = 0
                let group = DispatchGroup()
                
                for url in urls {
                    group.enter()
                    PodcastURLResolver.shared.resolveToRSSFeed(from: url.absoluteString) { feedURL in
                        if let feedURL = feedURL, !current.contains(where: { $0.feedURL == feedURL }) {
                            Task {
                                do {
                                    let podcast = try await PodcastService.shared.addPodcast(from: feedURL)
                                    current.append(podcast)
                                    newCount += 1
                                } catch {
                                    print("Failed to add podcast: \(error)")
                                }
                                group.leave()
                            }
                        } else {
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                    PodcastService.shared.savePodcasts(current)
                    self.spotifyImportMessage = "🎉 Imported \(newCount) podcast(s)"
                    self.activeAlert = .spotifyImport(self.spotifyImportMessage ?? "")
                }
            }
        }
    }
    

    
    private func importJSONFile(from url: URL) {
        print("📁 Starting JSON import from: \(url.lastPathComponent)")
        print("📁 File URL: \(url.absoluteString)")
        print("📁 Is file URL: \(url.isFileURL)")
        print("📁 File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        // Reset state
        isJSONImporting = true
        jsonImportMessage = "Processing JSON file..."
        
        // Try multiple approaches for file access
        var data: Data?
        var accessError: Error?
        
        // Approach 1: Direct access with security scoping
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                data = try Data(contentsOf: url)
                print("✅ Successfully read file with security scoping")
            } catch {
                print("❌ Security scoped access failed: \(error)")
                accessError = error
            }
        }
        
        // Approach 2: Try coordinator-based access if first approach failed
        if data == nil {
            var coordinatorError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { (readingURL) in
                do {
                    data = try Data(contentsOf: readingURL)
                    print("✅ Successfully read file with coordinator")
                } catch {
                    print("❌ Coordinator access failed: \(error)")
                    accessError = error
                }
            }
            
            if let coordinatorError = coordinatorError {
                print("❌ Coordinator error: \(coordinatorError)")
                accessError = coordinatorError
            }
        }
        
        // If we still don't have data, show error
        guard let fileData = data else {
            isJSONImporting = false
            let errorMessage = "Could not read JSON file: \(accessError?.localizedDescription ?? "Unknown access error")"
            jsonImportMessage = errorMessage
            activeAlert = .jsonImport(errorMessage)
            return
        }
        
        print("📁 Successfully read \(fileData.count) bytes from file")
        
        // Validate JSON format
        do {
            let _ = try JSONSerialization.jsonObject(with: fileData, options: [])
            print("✅ Valid JSON format confirmed")
        } catch {
            print("❌ Invalid JSON format: \(error)")
            isJSONImporting = false
            jsonImportMessage = "Invalid JSON format: \(error.localizedDescription)"
            activeAlert = .jsonImport(jsonImportMessage ?? "Unknown error")
            return
        }
        
        // Preview file content for debugging
        if let jsonString = String(data: fileData, encoding: .utf8) {
            print("📄 File content preview: \(String(jsonString.prefix(200)))...")
        }
        
        // Process the JSON data with proper background handling
        SubscriptionImportService.shared.importFromJSONFile(data: fileData) { podcasts, error in
            Task { @MainActor in
                self.isJSONImporting = false
                
                if let error = error {
                    print("❌ Import error: \(error)")
                    self.jsonImportMessage = "Import failed: \(error.localizedDescription)"
                    self.activeAlert = .jsonImport(self.jsonImportMessage ?? "Unknown error")
                    return
                }
                
                guard !podcasts.isEmpty else {
                    self.jsonImportMessage = "No podcasts could be imported. Please check the JSON file format."
                    self.activeAlert = .jsonImport(self.jsonImportMessage ?? "No podcasts found")
                    return
                }
                
                // STEP 1: Add podcasts to library IMMEDIATELY (no episode fetching)
                let currentPodcasts = PodcastService.shared.loadPodcasts()
                var newPodcasts: [Podcast] = []
                var skippedCount = 0
                
                for podcast in podcasts {
                    // Check if podcast already exists
                    if currentPodcasts.contains(where: { $0.feedURL.absoluteString == podcast.feedURL.absoluteString }) {
                        skippedCount += 1
                        continue
                    }
                    newPodcasts.append(podcast)
                }
                
                if !newPodcasts.isEmpty {
                    // Add all new podcasts to library immediately
                    let allPodcasts = currentPodcasts + newPodcasts
                    PodcastService.shared.savePodcasts(allPodcasts)
                    
                    // STEP 2: Update UI immediately to show new podcasts
                    LibraryController.shared.reloadData()
                    
                    print("✅ Added \(newPodcasts.count) podcasts to library immediately")
                    
                    // STEP 3: Fetch episodes in background (non-blocking)
                    Task.detached(priority: .background) {
                        print("🔄 Starting background episode fetch for \(newPodcasts.count) podcasts...")
                        
                        for podcast in newPodcasts {
                            // Fetch episodes for each podcast in background
                            do {
                                let episodes = try await EpisodeUpdateService.shared.fetchEpisodesForSinglePodcast(podcast)
                                print("📥 Fetched \(episodes.count) episodes for \(podcast.title)")
                                
                                // Update UI dynamically as each podcast's episodes are fetched
                                await MainActor.run {
                                    LibraryController.shared.refreshEpisodeData()
                                }
                            } catch {
                                print("❌ Failed to fetch episodes for \(podcast.title): \(error)")
                            }
                        }
                        
                        print("✅ Background episode fetch completed for all podcasts")
                    }
                }
                
                // STEP 4: Show success message immediately
                let message: String
                if newPodcasts.count > 0 {
                    if skippedCount > 0 {
                        message = "🎉 Successfully imported \(newPodcasts.count) new podcasts! (\(skippedCount) already in library)\n\n📥 Episodes are being fetched in the background..."
                    } else {
                        message = "🎉 Successfully imported \(newPodcasts.count) podcasts from JSON file!\n\n📥 Episodes are being fetched in the background..."
                    }
                } else {
                    message = "No new podcasts to import. All \(podcasts.count) podcasts are already in your library."
                }
                
                self.jsonImportMessage = message
                self.activeAlert = .jsonImport(message)
            }
        }
    }
    
    private func clearAllSubscriptions() {
        PodcastService.shared.clearAllSubscriptions()
        
        // Show success message
        activeAlert = .subscriptionImport("🗑️ All subscriptions have been cleared successfully!")
    }
    
    private func clearEpisodeCache() {
        // Clear episode cache service
        EpisodeCacheService.shared.clearAllCache()
        
        // Clear global episode view model
        Task {
            try? await EpisodeRepository.shared.clearAllEpisodes()
        }
        
        // Show confirmation (we can reuse the existing alert system)
        activeAlert = .subscriptionImport("🗑️ Episode cache cleared successfully! Episodes will be re-fetched when you visit podcast pages.")
    }
    
    private func forceFetchAllEpisodes() {
        // Clear all cached episodes first
        EpisodeCacheService.shared.clearAllCache()
        Task {
            try? await EpisodeRepository.shared.clearAllEpisodes()
        }
        
        // Force fetch episodes for all podcasts
        let podcasts = PodcastService.shared.loadPodcasts()
        
        if podcasts.isEmpty {
            activeAlert = .subscriptionImport("⚠️ No podcasts found to fetch episodes for.")
            return
        }
        
        // Force a background update which will fetch all episodes
        EpisodeUpdateService.shared.forceUpdate()
        
        activeAlert = .subscriptionImport("🔄 Force fetching episodes for \(podcasts.count) podcasts. This may take a few moments. Check the Episodes tab to see progress.")
    }
    
    private func recoverEpisodesAndQueue() {
        print("🔧 Starting Episodes & Queue Recovery...")
        
        // 1. Clear corrupted episode data
        Task {
            try? await EpisodeRepository.shared.clearAllEpisodes()
        }
        
        // 2. Clear corrupted queue data
        UserDefaults.standard.removeObject(forKey: "queueKey")
        QueueViewModel.shared.queue.removeAll()
        
        // 3. Clear episode cache to force fresh data
        EpisodeCacheService.shared.clearAllCache()
        
        // 4. Force reload episodes from podcasts
        let podcasts = PodcastService.shared.loadPodcasts()
        
        if podcasts.isEmpty {
            activeAlert = .subscriptionImport("⚠️ No podcasts found. Please add some podcasts first.")
            return
        }
        
        // 5. Trigger episode update service to fetch all episodes
        EpisodeUpdateService.shared.forceUpdate()
        
        activeAlert = .subscriptionImport("🔧 Recovery started! Clearing corrupted data and re-fetching episodes for \(podcasts.count) podcasts. Your episodes and queue will be restored shortly. Check the Episodes tab to see progress.")
    }
    
    private func diagnosePodcastArtwork() {
        let podcasts = PodcastService.shared.loadPodcasts()
        print("\n🔍 PODCAST ARTWORK DIAGNOSIS")
        print(String(repeating: "=", count: 50))
        for podcast in podcasts {
            print("📺 \(podcast.title)")
            print("   🎨 Artwork: \(podcast.artworkURL?.absoluteString ?? "❌ NIL")")
            print("   📡 Feed: \(podcast.feedURL.absoluteString)")
            print("")
        }
        print(String(repeating: "=", count: 50))
        
        activeAlert = .subscriptionImport("Check console for detailed artwork diagnosis. Found \(podcasts.count) podcasts.")
    }
    
    private func refreshAllPodcastMetadata() {
        let podcasts = PodcastService.shared.loadPodcasts()
        guard !podcasts.isEmpty else {
            activeAlert = .subscriptionImport("No podcasts found to refresh.")
            return
        }
        
        activeAlert = .subscriptionImport("🔄 Fixing artwork for \(podcasts.count) podcasts...")
        
        PodcastService.shared.refreshAllPodcastArtwork { updatedCount, totalProcessed in
            DispatchQueue.main.async {
                if updatedCount > 0 {
                    self.activeAlert = .subscriptionImport("🎨 Successfully fixed artwork for \(updatedCount) of \(totalProcessed) podcasts! Library should now show proper show artwork.")
                } else {
                    self.activeAlert = .subscriptionImport("ℹ️ All \(totalProcessed) podcasts already have correct artwork, or no artwork could be found in their RSS feeds.")
                }
            }
        }
    }
    
    private func deleteAllLocalStorage() {
        // 1. Delete Subscriptions
        UserDefaults.standard.removeObject(forKey: "podcastsKey")
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        PodcastService.shared.clearAllSubscriptions()

        // 2. Delete All Episodes and History
        Task {
            try? await EpisodeRepository.shared.clearAllEpisodes()
        }

        // 3. Delete Episode Cache
        EpisodeCacheService.shared.clearAllCache()

        // 4. Delete Play Queue
        QueueViewModel.shared.queue.removeAll()
        UserDefaults.standard.removeObject(forKey: "queueKey")


        // 5. Delete Downloaded Files
        let fileManager = FileManager.default
        let documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsUrl = documentsUrl {
            do {
                let fileUrls = try fileManager.contentsOfDirectory(at: documentsUrl,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: .skipsHiddenFiles)
                for fileUrl in fileUrls {
                    try fileManager.removeItem(at: fileUrl)
                }
            } catch {
                print("Error deleting downloaded files: \(error)")
            }
        }
        
        // 6. Reload data in view models to reflect changes in UI
        PodcastDataManager.shared.loadPodcasts()
    }
    
    private func alertTitle() -> String {
        switch activeAlert {
        case .resetData:
            return "Reset All Data"
        case .appleImport(_):
            return "Apple Podcasts Import"
        case .subscriptionImport(_):
            return "Subscription Import"
        case .spotifyImport(_):
            return "Spotify Import"
        case .jsonImport(_):
            return "JSON Import"
        case .clearSubscriptions:
            return "Clear Subscriptions"
        case .none:
            return ""
        }
    }
    
    private func alertButtons() -> AnyView {
        switch activeAlert {
        case .resetData:
            return AnyView(
                Group {
                    Button("Cancel", role: .cancel) { 
                        activeAlert = nil
                    }
                    Button("Reset", role: .destructive) {
                        DebugHelper.shared.resetAllData()
                        activeAlert = nil
                    }
                }
            )
        case .clearSubscriptions:
            return AnyView(
                Group {
                    Button("Cancel", role: .cancel) { 
                        activeAlert = nil
                    }
                    Button("Clear", role: .destructive) {
                        clearAllSubscriptions()
                        activeAlert = nil
                    }
                }
            )
        case .appleImport(_), .subscriptionImport(_), .spotifyImport(_), .jsonImport(_), .none:
            return AnyView(
                Button("OK") {
                    activeAlert = nil
                }
            )
        }
    }
    
    private func alertMessage() -> Text {
        switch activeAlert {
        case .resetData:
            return Text("This will delete all subscriptions, queue, and settings. This action cannot be undone.")
        case .appleImport(let message):
            return Text(message)
        case .subscriptionImport(let message):
            return Text(message)
        case .spotifyImport(let message):
            return Text(message)
        case .jsonImport(let message):
            return Text(message)
        case .clearSubscriptions:
            return Text("This will remove all podcast subscriptions and clear your episode queue. This action cannot be undone.")
        case .none:
            return Text("")
        }
    }
}

// MARK: - Apple Podcast Import Guide Sheet

struct ApplePodcastImportGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🎧 Import All Your Apple Podcasts")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Due to iOS limitations, Apple Podcasts only shares downloaded episodes with other apps. Here's how to get ALL your subscriptions:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        ImportStepView(
                            number: "1",
                            title: "Use the Auto-Import Button",
                            description: "Tap 'Get All My Subscriptions' above. This will find podcasts you've recently played or downloaded.",
                            icon: "externaldrive.badge.plus",
                            color: .green
                        )
                        
                        ImportStepView(
                            number: "2",
                            title: "Share Directly from Apple Podcasts",
                            description: "In Apple Podcasts, tap any show → Share → Copy Link, then use 'Import from URL' in Jimmy",
                            icon: "square.and.arrow.up",
                            color: .blue
                        )
                        
                        ImportStepView(
                            number: "3",
                            title: "Manual Search & Add",
                            description: "Go to Jimmy's Search tab and search for your favorite podcasts by name",
                            icon: "magnifyingglass",
                            color: .purple
                        )
                        
                        ImportStepView(
                            number: "4",
                            title: "Export as OPML (Advanced)",
                            description: "Use third-party tools or export your subscriptions from podcast.apple.com if needed",
                            icon: "doc.badge.gearshape",
                            color: .orange
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("💡 Pro Tips")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(icon: "play.circle.fill", text: "Play a few episodes in Apple Podcasts to help detection", color: .blue)
                            TipRow(icon: "arrow.down.circle.fill", text: "Download episodes of your favorites before importing", color: .green)
                            TipRow(icon: "link", text: "Use Jimmy's URL scheme: jimmy://import?url=[PODCAST_URL]", color: .orange)
                            TipRow(icon: "rectangle.3.group", text: "Screenshot your Apple Podcasts library as a backup list", color: .purple)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔍 Why This Limitation Exists")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("For privacy and security, iOS only allows apps to access media that's actually downloaded to your device. Your subscription list is considered private data that Apple Podcasts doesn't share with third-party apps.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Import Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ImportStepView: View {
    let number: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number circle
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 24, height: 24)
                
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .frame(width: 20)
                    
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Manual Podcast Import View

struct ManualPodcastImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var statusMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add Podcast from URL")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste URL")
                        .font(.headline)
                    
                    Text("Supports:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• RSS feed URLs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("• Apple Podcasts URLs (podcasts.apple.com)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("• Most podcast platform URLs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                TextField("https://...", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                if let statusMessage = statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(statusMessage.starts(with: "Error") ? .red : 
                                       statusMessage.starts(with: "Success") ? .green : .primary)
                        .multilineTextAlignment(.center)
                }
                
                Button("Add Podcast") {
                    addPodcastFromURL()
                }
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Adding podcast...")
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .keyboardDismissToolbar()
        }
    }
    
    private func addPodcastFromURL() {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        
        isLoading = true
        statusMessage = nil
        
        // Try to resolve the URL to an RSS feed
        PodcastURLResolver.shared.resolveToRSSFeed(from: trimmedURL) { feedURL in
            DispatchQueue.main.async {
                if let feedURL = feedURL {
                    // Try to add the podcast
                    Task {
                        do {
                            let podcast = try await PodcastService.shared.addPodcast(from: feedURL)
                            await MainActor.run {
                                isLoading = false
                                statusMessage = "Successfully added \"\(podcast.title)\"!"
                                
                                // Clear the URL field and auto-dismiss after a delay
                                urlText = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    dismiss()
                                }
                            }
                        } catch {
                            await MainActor.run {
                                isLoading = false
                                statusMessage = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                } else {
                    isLoading = false
                    statusMessage = "Error: Could not find RSS feed for this URL. Please check the URL and try again."
                }
            }
        }
    }
}

// MARK: - Shortcuts Guide Sheet

struct ShortcutsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📱 Setup Siri Shortcuts for Jimmy")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Import podcasts easily using voice commands and automation")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        ShortcutStepView(
                            number: "1",
                            title: "Open Shortcuts App",
                            description: "Open the built-in Shortcuts app on your iPhone or iPad",
                            icon: "shortcuts",
                            color: .indigo
                        )
                        
                        ShortcutStepView(
                            number: "2",
                            title: "Create New Shortcut",
                            description: "Tap the '+' button and create a new shortcut called 'Add Podcast to Jimmy'",
                            icon: "plus.circle.fill",
                            color: .green
                        )
                        
                        ShortcutStepView(
                            number: "3",
                            title: "Add URL Actions",
                            description: "Add 'Get URLs from Input' → 'Open URLs' actions and set scheme to 'jimmy://import'",
                            icon: "link.circle.fill",
                            color: .blue
                        )
                        
                        ShortcutStepView(
                            number: "4",
                            title: "Set Voice Phrase",
                            description: "Add phrase like 'Add podcast to Jimmy' in shortcut settings",
                            icon: "mic.circle.fill",
                            color: .red
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to Use")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ShortcutBenefitRow(icon: "voice.fill", text: "Say 'Hey Siri, Add podcast to Jimmy'", color: .blue)
                            ShortcutBenefitRow(icon: "link", text: "Share any podcast URL to the shortcut", color: .green)
                            ShortcutBenefitRow(icon: "safari", text: "Copy URLs from Apple Podcasts, Spotify, etc.", color: .orange)
                            ShortcutBenefitRow(icon: "bolt.fill", text: "Jimmy will automatically import the podcast", color: .purple)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("💡 URL Scheme")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Jimmy supports the URL scheme: jimmy://import?url=[PODCAST_URL]")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔗 Share Extension")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("You can also share podcast URLs directly to Jimmy from Safari, Apple Podcasts, or any app using the system share sheet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Shortcuts Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ShortcutStepView: View {
    let number: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number circle
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 24, height: 24)
                
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .frame(width: 20)
                    
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ShortcutBenefitRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Apple Bulk Import Guide Sheet

struct AppleBulkImportGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Bulk Import Using Web Extractor")
                        .font(.title2)
                        .fontWeight(.bold)

                    VStack(alignment: .leading, spacing: 16) {
                        ImportStepView(number: "1",
                                       title: "Open the Extractor",
                                       description: "Visit the apple-podcasts-extractor.html file and follow the instructions.",
                                       icon: "safari",
                                       color: .blue)

                        ImportStepView(number: "2",
                                       title: "Download JSON",
                                       description: "The extractor saves a JSON file with all your subscriptions",
                                       icon: "arrow.down.doc",
                                       color: .green)

                        ImportStepView(number: "3",
                                       title: "Import in Jimmy",
                                       description: "Use 'Import Apple JSON File' in Settings",
                                       icon: "tray.and.arrow.down",
                                       color: .accentColor)
                    }
                }
                .padding()
            }
            .navigationTitle("Apple JSON Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Spotify Import Guide Sheet

struct SpotifyImportGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Import Subscriptions from Spotify")
                        .font(.title2)
                        .fontWeight(.bold)

                    VStack(alignment: .leading, spacing: 16) {
                        ImportStepView(number: "1",
                                       title: "Export Show Links",
                                       description: "Use the Spotify web player and our helper script to save your followed shows as a text file of links",
                                       icon: "safari",
                                       color: .green)

                        ImportStepView(number: "2",
                                       title: "Import File",
                                       description: "Select 'Import Spotify File' in Settings and choose the exported text file",
                                       icon: "tray.and.arrow.down",
                                       color: .accentColor)

                        ImportStepView(number: "3",
                                       title: "Verify Results",
                                       description: "Jimmy will match the links to RSS feeds automatically",
                                       icon: "checkmark",
                                       color: .purple)
                    }
                }
                .padding()
            }
            .navigationTitle("Spotify Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Custom Components

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: Content
    
    init(title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(0.15))
                    )
                
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            // Content
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(
                    color: Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    let icon: String
    @Binding var isOn: Bool
    
    init(title: String, subtitle: String? = nil, icon: String, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._isOn = isOn
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct SettingsButton: View {
    let title: String
    let subtitle: String?
    let icon: String
    let isDestructive: Bool
    let action: () -> Void
    
    init(title: String, subtitle: String? = nil, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isDestructive = isDestructive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(isDestructive ? .red : .blue)
                    .font(.title3)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(isDestructive ? .red : .primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ImportButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isLoading: Bool
    let action: () -> Void
    
    init(title: String, subtitle: String, icon: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.orange)
                    .font(.title3)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
    }
}
