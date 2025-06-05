import SwiftUI

struct SettingsView: View {
    @AppStorage("playbackSpeed") private var playbackSpeed: Double = 1.0
    @AppStorage("darkMode") private var darkMode: Bool = true
    @AppStorage("episodeSwipeAction") private var episodeSwipeAction: String = "addToQueue"
    @AppStorage("queueSwipeAction") private var queueSwipeAction: String = "markAsPlayed"
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false
    @AppStorage("highContrastMode") private var highContrastMode: Bool = false
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingAnalytics = false
    @State private var isImportingFromApplePodcasts = false
    @State private var showingManualImport = false
    @State private var showingShortcutsGuide = false
    @State private var isOPMLImporting = false
    @State private var opmlImportMessage: String?
    @State private var showingAppleImportGuide = false
    @State private var showingAppleBulkGuide = false
    @State private var isAppleJSONImporting = false
    @State private var appleJSONImportMessage: String?
    @State private var showingSpotifyImportGuide = false
    @State private var isSpotifyImporting = false
    @State private var spotifyImportMessage: String?
    @State private var showingFeedbackForm = false
    @State private var activeAlert: SettingsAlert?
    @State private var isSubscriptionImporting = false
    @State private var subscriptionImportMessage: String?
    @StateObject private var authService = AuthenticationService.shared
    @State private var authError: String?

    enum SettingsAlert {
        case resetData
        case appleImport(String)
        case opmlImport(String)
        case subscriptionImport(String)
        case appleBulkImport(String)
        case spotifyImport(String)
    }

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                if let user = authService.currentUser {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Logged in as")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(user.name)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        Button("Sign Out", role: .destructive) {
                            authService.signOut()
                        }
                    }
                } else {
                    Button("Sign in with Apple") {
                        authService.login(with: .apple) { result in
                            if case .failure(let error) = result {
                                authError = error.localizedDescription
                            }
                        }
                    }
                    Button("Sign in with Google") {
                        authService.login(with: .google) { result in
                            if case .failure(let error) = result {
                                authError = error.localizedDescription
                            }
                        }
                    }
                }
            }
            Section(header: Text("Playback")) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Picker("", selection: $playbackSpeed) {
                        Text("0.75x").tag(0.75)
                        Text("1x").tag(1.0)
                        Text("1.25x").tag(1.25)
                        Text("1.5x").tag(1.5)
                        Text("2x").tag(2.0)
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            Section(header: Text("Appearance")) {
                Toggle(isOn: $darkMode) {
                    Text("Dark Mode")
                }
                Toggle(isOn: $highContrastMode) {
                    Text("High Contrast Mode")
                }
            }
            Section(header: Text("Swipe Actions")) {
                Picker("Episode List Swipe", selection: $episodeSwipeAction) {
                    Text("Add to Queue").tag("addToQueue")
                    Text("Download").tag("download")
                    Text("Mark as Played").tag("markAsPlayed")
                }
                Picker("Queue Swipe", selection: $queueSwipeAction) {
                    Text("Mark as Played").tag("markAsPlayed")
                    Text("Download").tag("download")
                    Text("Remove").tag("remove")
                }
            }
            Section(header: Text("Data & Sync")) {
                Toggle(isOn: $iCloudSyncEnabled) {
                    Text("Enable iCloud Sync")
                }
            }
            Section(header: Text("Backup & Restore")) {
                Button("Export App Data") {
                    isExporting = true
                }
            }
            
            Section(header: Text("Import from Apple Podcasts")) {
                VStack(alignment: .leading, spacing: 12) {
                    
                    // Primary import button
                    Button(action: {
                        performComprehensiveApplePodcastsImport()
                    }) {
                        HStack {
                            Image(systemName: "externaldrive.badge.plus")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Get All My Subscriptions")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Import all podcasts from Apple Podcasts")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                            if isImportingFromApplePodcasts {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(isImportingFromApplePodcasts)
                    
                    // Guidance button
                    Button(action: {
                        showingAppleImportGuide = true
                    }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.accentColor)
                            Text("How to Import All Subscriptions")
                                .foregroundColor(.accentColor)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    Button(action: {
                        showingAppleBulkGuide = true
                    }) {
                        HStack {
                            Image(systemName: "tray.and.arrow.down")
                                .foregroundColor(.accentColor)
                            Text("Import from Extractor File")
                                .foregroundColor(.accentColor)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Other Import Options")) {
                Button("Import Podcast From URL") {
                    showingManualImport = true
                }

                Button("Import OPML File") {
                    isOPMLImporting = true
                }

                Button("Import Apple JSON File") {
                    isAppleJSONImporting = true
                }

                Button("Import Spotify File") {
                    isSpotifyImporting = true
                }

                Button("Spotify Import Guide") {
                    showingSpotifyImportGuide = true
                }

                Button("Import from Subscription File") {
                    importFromSubscriptionFile()
                }
                .disabled(isSubscriptionImporting)
                
                if isSubscriptionImporting {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Importing subscriptions...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Feedback")) {
                Button("Submit a Request or Bug") {
                    showingFeedbackForm = true
                }
            }

            Section(header: Text("Debug/Developer Mode")) {
                Button("View Analytics") {
                    showingAnalytics = true
                }
                Button("Clear Episode Cache", role: .destructive) {
                    clearEpisodeCache()
                }
                Button("Force Fetch Episodes") {
                    forceFetchAllEpisodes()
                }
                Button("Diagnose Podcast Artwork") {
                    diagnosePodcastArtwork()
                }
                Button("Fix Podcast Artwork") {
                    refreshAllPodcastMetadata()
                }
                Button("Reset All Data", role: .destructive) {
                    activeAlert = .resetData
                }
                Button("Test Notification") {
                    DebugHelper.shared.sendTestNotification()
                }
            }
        }
        .navigationTitle("Settings")
        .fileExporter(isPresented: $isExporting, document: AppDataDocument(), contentType: .json, defaultFilename: "JimmyBackup") { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    try AppDataDocument.importData(data)
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isOPMLImporting, allowedContentTypes: [.xml, .data]) { result in
            switch result {
            case .success(let url):
                importOPMLFile(from: url)
            case .failure(let error):
                opmlImportMessage = "Error selecting file: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $isAppleJSONImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importAppleJSONFile(from: url)
            case .failure(let error):
                appleJSONImportMessage = "Error selecting file: \(error.localizedDescription)"
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
        .alert("Login Error", isPresented: Binding(
            get: { authError != nil },
            set: { if !$0 { authError = nil } }
        )) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            Text(authError ?? "")
        }
        .sheet(isPresented: $showingManualImport) {
            ManualPodcastImportView()
        }
        .sheet(isPresented: $showingShortcutsGuide) {
            ShortcutsGuideSheet()
        }
        .sheet(isPresented: $showingAppleImportGuide) {
            ApplePodcastImportGuideSheet()
        }
        .sheet(isPresented: $showingAppleBulkGuide) {
            AppleBulkImportGuideSheet()
        }
        .sheet(isPresented: $showingSpotifyImportGuide) {
            SpotifyImportGuideSheet()
        }
        .sheet(isPresented: $showingFeedbackForm) {
            FeedbackFormView()
        }
    }
    
    private func performComprehensiveApplePodcastsImport() {
        // Clear any existing alerts
        activeAlert = nil
        isImportingFromApplePodcasts = true
        
        ApplePodcastService.shared.importAllApplePodcastSubscriptions { podcasts, error in
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
    
    private func importOPMLFile(from url: URL) {
        opmlImportMessage = "Processing OPML file..."
        
        // Start accessing the security-scoped resource
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        let parser = OPMLParser()
        let importedPodcasts = parser.parseOPML(from: url)
        
        var currentPodcasts = PodcastService.shared.loadPodcasts()
        var newPodcastsCount = 0
        var skippedCount = 0
        
        for podcast in importedPodcasts {
            // Check if podcast already exists
            if currentPodcasts.contains(where: { $0.feedURL.absoluteString == podcast.feedURL.absoluteString }) {
                skippedCount += 1
                continue
            }
            
            currentPodcasts.append(podcast)
            newPodcastsCount += 1
        }
        
        // Save updated podcasts
        PodcastService.shared.savePodcasts(currentPodcasts)

        // Show success message
        if newPodcastsCount > 0 {
            if skippedCount > 0 {
                opmlImportMessage = "🎉 Successfully imported \(newPodcastsCount) new podcasts! (\(skippedCount) already in library)"
            } else {
                opmlImportMessage = "🎉 Successfully imported \(newPodcastsCount) podcasts from OPML file!"
            }
        } else {
            opmlImportMessage = "No new podcasts to import. All \(importedPodcasts.count) podcasts are already in your library."
        }
    }

    private func importAppleJSONFile(from url: URL) {
        appleJSONImportMessage = "Processing file..."
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            appleJSONImportMessage = "Could not read file"
            return
        }

        do {
            let podcasts = try AppleBulkImportParser.parse(data: data)
            var current = PodcastService.shared.loadPodcasts()
            var newCount = 0
            for p in podcasts {
                if !current.contains(where: { $0.feedURL == p.feedURL }) {
                    current.append(p)
                    newCount += 1
                }
            }
            PodcastService.shared.savePodcasts(current)
            appleJSONImportMessage = "🎉 Imported \(newCount) podcast(s)" 
        } catch {
            appleJSONImportMessage = "Import failed: \(error.localizedDescription)"
        }
        activeAlert = .appleBulkImport(appleJSONImportMessage ?? "Import finished")
    }

    private func importSpotifyFile(from url: URL) {
        spotifyImportMessage = "Processing file..."
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            spotifyImportMessage = "Could not read file"
            activeAlert = .spotifyImport(spotifyImportMessage ?? "")
            return
        }

        let urls = SpotifyListParser.parse(data: data)
        guard !urls.isEmpty else {
            spotifyImportMessage = "No URLs found in file"
            activeAlert = .spotifyImport(spotifyImportMessage ?? "")
            return
        }

        var current = PodcastService.shared.loadPodcasts()
        var newCount = 0
        let group = DispatchGroup()
        for url in urls {
            group.enter()
            PodcastURLResolver.shared.resolveToRSSFeed(from: url.absoluteString) { feedURL in
                if let feedURL = feedURL, !current.contains(where: { $0.feedURL == feedURL }) {
                    PodcastService.shared.addPodcast(from: feedURL) { podcast, _ in
                        if let podcast = podcast {
                            current.append(podcast)
                            newCount += 1
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
    
    private func importFromSubscriptionFile() {
        isSubscriptionImporting = true
        
        // Read the subscriptions.txt file from the app bundle or documents directory
        guard let fileURL = Bundle.main.url(forResource: "subscriptions", withExtension: "txt") ??
                FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("subscriptions.txt") else {
            
            // If file doesn't exist, create it with the subscription content for testing
            createTestSubscriptionFile()
            return
        }
        
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            isSubscriptionImporting = false
            activeAlert = .subscriptionImport("Could not read subscription file")
            return
        }
        
        SubscriptionImportService.shared.importFromSubscriptionContent(content) { podcasts, error in
            DispatchQueue.main.async {
                self.isSubscriptionImporting = false
                
                let message: String
                if let error = error {
                    message = "Import failed: \(error.localizedDescription)"
                } else if podcasts.isEmpty {
                    message = "No podcasts could be imported. Please check the file format."
                } else {
                    var currentPodcasts = PodcastService.shared.loadPodcasts()
                    var newPodcastsCount = 0
                    var skippedCount = 0
                    
                    for podcast in podcasts {
                        // Check if podcast already exists
                        if currentPodcasts.contains(where: { $0.feedURL.absoluteString == podcast.feedURL.absoluteString }) {
                            skippedCount += 1
                            continue
                        }
                        
                        currentPodcasts.append(podcast)
                        newPodcastsCount += 1
                    }
                    
                    // Save updated podcasts
                    PodcastService.shared.savePodcasts(currentPodcasts)
                    
                    if newPodcastsCount > 0 {
                        if skippedCount > 0 {
                            message = "🎉 Successfully imported \(newPodcastsCount) new podcasts! (\(skippedCount) already in library)"
                        } else {
                            message = "🎉 Successfully imported \(newPodcastsCount) podcasts from subscription file!"
                        }
                    } else {
                        message = "No new podcasts to import. All \(podcasts.count) podcasts are already in your library."
                    }
                }
                
                self.activeAlert = .subscriptionImport(message)
            }
        }
    }
    
    private func createTestSubscriptionFile() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            isSubscriptionImporting = false
            activeAlert = .subscriptionImport("Could not access documents directory")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("subscriptions.txt")
        
        // Use the actual subscription data from the user's file
        let subscriptionContent = """
עושים פוליטיקה Osim Politika by רשת עושים היסטוריה (https://podcasts.apple.com/us/podcast/%D7%A2%D7%95%D7%A9%D7%99%D7%9D-%D7%A4%D7%95%D7%9C%D7%99%D7%98%D7%99%D7%A7%D7%94-osim-politika/id1215589622?uo=4)--//--שיר אחד One Song by כאן | Kan (https://podcasts.apple.com/us/podcast/%D7%A9%D7%99%D7%A8-%D7%90%D7%97%D7%93-one-song/id1201883177?uo=4)--//--חיות כיס Hayot Kiss by כאן | Kan (https://podcasts.apple.com/us/podcast/%D7%97%D7%99%D7%95%D7%AA-%D7%9B%D7%99%D7%A1-hayot-kiss/id1198989209?uo=4)--//--The Joe Rogan Experience by Joe Rogan (https://podcasts.apple.com/us/podcast/the-joe-rogan-experience/id360084272?uo=4)
"""
        
        do {
            try subscriptionContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Created test subscription file at: \(fileURL.path)")
            // Now try to import again
            importFromSubscriptionFile()
        } catch {
            isSubscriptionImporting = false
            activeAlert = .subscriptionImport("Could not create subscription file: \(error.localizedDescription)")
        }
    }
    
    private func clearEpisodeCache() {
        // Clear episode cache service
        EpisodeCacheService.shared.clearAllCache()
        
        // Clear global episode view model
        EpisodeViewModel.shared.clearAllEpisodes()
        
        // Show confirmation (we can reuse the existing alert system)
        activeAlert = .subscriptionImport("🗑️ Episode cache cleared successfully! Episodes will be re-fetched when you visit podcast pages.")
    }
    
    private func forceFetchAllEpisodes() {
        // Clear all cached episodes first
        EpisodeCacheService.shared.clearAllCache()
        EpisodeViewModel.shared.clearAllEpisodes()
        
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
    
    private func alertTitle() -> String {
        switch activeAlert {
        case .resetData:
            return "Reset All Data"
        case .appleImport(_):
            return "Apple Podcasts Import"
        case .opmlImport(_):
            return "OPML Import"
        case .subscriptionImport(_):
            return "Subscription Import"
        case .appleBulkImport(_):
            return "Apple JSON Import"
        case .spotifyImport(_):
            return "Spotify Import"
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
        case .appleImport(_), .opmlImport(_), .subscriptionImport(_), .appleBulkImport(_), .spotifyImport(_), .none:
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
        case .opmlImport(let message):
            return Text(message)
        case .subscriptionImport(let message):
            return Text(message)
        case .appleBulkImport(let message):
            return Text(message)
        case .spotifyImport(let message):
            return Text(message)
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
                    PodcastService.shared.addPodcast(from: feedURL) { podcast, error in
                        DispatchQueue.main.async {
                            isLoading = false
                            
                            if let error = error {
                                statusMessage = "Error: \(error.localizedDescription)"
                            } else if let podcast = podcast {
                                statusMessage = "Successfully added \"\(podcast.title)\"!"
                                
                                // Clear the URL field and auto-dismiss after a delay
                                urlText = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    dismiss()
                                }
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
