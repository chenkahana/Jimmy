import SwiftUI
import UniformTypeIdentifiers
import os

struct SettingsView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SettingsView")
    @StateObject private var viewModel = SettingsViewModel.shared
    @State private var showingBackupShare = false
    @State private var showingBackupImport = false
    @State private var backupFileURL: URL?
    @State private var showingAssistant = false

    var body: some View {
        ZStack {
            JimmyScreenBackground()

            ScrollView {
                LazyVStack(spacing: 20) { // Reduced spacing for better performance
                    settingsHero

                // Playback Section
                SettingsCard(
                    title: "Playback",
                    icon: "play.circle.fill",
                    iconColor: .green
                ) {
                    VStack(spacing: 16) {
                        HStack {
                            SettingsRowIcon(icon: "speedometer")
                            Text("Playback Speed")
                                .font(.body.weight(.medium))
                            Spacer()
                            Picker("", selection: $viewModel.playbackSpeed) {
                                Text("0.75x").tag(0.75)
                                Text("1x").tag(1.0)
                                Text("1.25x").tag(1.25)
                                Text("1.5x").tag(1.5)
                                Text("2x").tag(2.0)
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        SettingsToggle(
                            title: "Auto-Load Last Episode",
                            subtitle: "Loads your last episode when the app opens",
                            icon: "arrow.clockwise.circle.fill",
                            isOn: $viewModel.autoRestoreLastEpisode
                        )

                        Divider()

                        // Skip Controls
                        HStack {
                            SettingsRowIcon(icon: "gobackward")
                            Text("Skip Back")
                                .font(.body.weight(.medium))
                            Spacer()
                            Picker("", selection: $viewModel.skipBackwardDuration) {
                                Text("10s").tag(10.0)
                                Text("15s").tag(15.0)
                                Text("30s").tag(30.0)
                                Text("45s").tag(45.0)
                            }
                            .pickerStyle(MenuPickerStyle())
                        }

                        HStack {
                            SettingsRowIcon(icon: "goforward")
                            Text("Skip Forward")
                                .font(.body.weight(.medium))
                            Spacer()
                            Picker("", selection: $viewModel.skipForwardDuration) {
                                Text("10s").tag(10.0)
                                Text("15s").tag(15.0)
                                Text("30s").tag(30.0)
                                Text("45s").tag(45.0)
                                Text("60s").tag(60.0)
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                }
                .staggeredAppear(index: 0)

                // Appearance Section
                SettingsCard(
                    title: "Appearance",
                    icon: "paintbrush.fill",
                    iconColor: .accentColor
                ) {
                    VStack(spacing: 12) {
                        HStack {
                            SettingsRowIcon(icon: "circle.lefthalf.filled")
                            Text("Color Scheme")
                                .foregroundColor(.primary)
                            Spacer()
                            Picker("Color Scheme", selection: $viewModel.appearanceMode) {
                                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }

                        SettingsToggle(
                            title: "High Contrast Mode",
                            icon: "eye.circle.fill",
                            isOn: $viewModel.highContrastMode
                        )
                    }
                }
                .staggeredAppear(index: 1)

                // Data & Sync Section
                SettingsCard(
                    title: "Data & Sync",
                    icon: "icloud.fill",
                    iconColor: .accentColor
                ) {
                    VStack(spacing: 12) {
                        SettingsToggle(
                            title: "iCloud Sync",
                            subtitle: "Sync your data across devices",
                            icon: "icloud.circle.fill",
                            isOn: $viewModel.iCloudSyncEnabled
                        )
                        
                        SettingsButton(
                            title: "Export App Data",
                            subtitle: "Backup your podcasts and settings",
                            icon: "square.and.arrow.up.circle.fill",
                            action: {
                                Task {
                                    await viewModel.exportAppData()
                                }
                            }
                        )

                        Divider()

                        SettingsButton(
                            title: "Export Full Backup",
                            subtitle: "Backup all data including playback state and bookmarks",
                            icon: "externaldrive.fill.badge.plus",
                            action: {
                                Task {
                                    do {
                                        let url = try await BackupService.shared.exportBackup()
                                        await MainActor.run {
                                            backupFileURL = url
                                            showingBackupShare = true
                                        }
                                    } catch {
                                        logger.error("Backup export failed: \(error)")
                                    }
                                }
                            }
                        )

                        SettingsButton(
                            title: "Import Backup",
                            subtitle: "Restore from a Jimmy backup file",
                            icon: "externaldrive.fill.badge.timemachine",
                            action: { showingBackupImport = true }
                        )
                    }
                }
                .staggeredAppear(index: 2)

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
                            subtitle: viewModel.isJSONImporting ? (viewModel.jsonImportMessage ?? "Processing...") : "Import podcasts from a JSON file with title, publisher, and url fields",
                            icon: "doc.text.fill",
                            isLoading: viewModel.isJSONImporting,
                            action: { 
                                viewModel.isJSONImporting = true
                            }
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Other import methods
                        ImportButton(
                            title: "Import from Spotify",
                            subtitle: "Import from Spotify playlist export",
                            icon: "music.note.list",
                            action: { 
                                Task {
                                    await viewModel.importFromSpotify()
                                }
                            }
                        )
                        
                        ImportButton(
                            title: "Import from Apple Podcasts",
                            subtitle: "Get all your Apple Podcasts subscriptions",
                            icon: "externaldrive.badge.plus",
                            isLoading: viewModel.isImportingFromApplePodcasts,
                            action: { 
                                Task {
                                    await viewModel.performComprehensiveApplePodcastsImport()
                                }
                            }
                        )
                        
                        ImportButton(
                            title: "Add Single Podcast by URL",
                            subtitle: "Import one podcast by RSS feed URL",
                            icon: "plus.circle.fill",
                            action: { viewModel.showingManualImport = true }
                        )
                    }
                }
                .staggeredAppear(index: 3)

                // Assistant Section
                SettingsCard(
                    title: "Assistant",
                    icon: "sparkles",
                    iconColor: .purple
                ) {
                    SettingsButton(
                        title: "Assistant",
                        subtitle: "Ask Jimmy to play, queue, search, subscribe, or set a sleep timer",
                        icon: "sparkles",
                        action: { showingAssistant = true }
                    )
                }
                .staggeredAppear(index: 4)

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
                            action: { viewModel.showClearSubscriptionsConfirmation = true }
                        )

                        SettingsButton(
                            title: "Submit Feedback",
                            subtitle: "Report bugs or request features",
                            icon: "envelope.circle.fill",
                            action: { viewModel.showingFeedbackForm = true }
                        )
                    }
                }
                .staggeredAppear(index: 5)

                #if DEBUG
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
                            action: { viewModel.showingAnalytics = true }
                        )
                        
                        SettingsButton(
                            title: "Clear Episode Cache",
                            subtitle: "Free up storage space",
                            icon: "trash.circle.fill",
                            isDestructive: true,
                            action: {
                                Task {
                                    await viewModel.clearEpisodeCache()
                                }
                            }
                        )
                        
                        SettingsButton(
                            title: "Reset All Data",
                            subtitle: "Complete app reset",
                            icon: "exclamationmark.triangle.fill",
                            isDestructive: true,
                            action: { viewModel.showAlert(.resetData) }
                        )
                    }
                }
                .staggeredAppear(index: 6)
                #endif

                // Footer spacing for tab bar
                Color.clear
                    .frame(height: TabBarSpacing.totalSpacing)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .scrollContentBackground(.hidden) // Improve scrolling performance
        .navigationTitle("Settings")
        .onAppear {
            // ViewModel handles all initialization
        }
        .fileExporter(
            isPresented: $viewModel.isExporting, 
            document: AppDataDocument(), 
            contentType: .json, 
            defaultFilename: "JimmyBackup"
        ) { result in
            if case .failure(let error) = result {
                viewModel.importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $viewModel.isImporting, 
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        try await viewModel.importSubscriptions(from: url, progressHandler: { _ in })
                    } catch {
                        // Handle error
                    }
                }
            case .failure(let error):
                viewModel.importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $viewModel.isSpotifyImporting, 
            allowedContentTypes: [.text, .data]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    await viewModel.importFromSpotify()
                }
            case .failure(let error):
                viewModel.spotifyImportMessage = "Error selecting file: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $viewModel.isJSONImporting, 
            allowedContentTypes: [.json, .plainText, .data, .text]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    await viewModel.importFromJSON(fileURL: url)
                }
            case .failure(let error):
                viewModel.jsonImportMessage = "Error selecting file: \(error.localizedDescription)"
                viewModel.showAlert(.jsonImport(viewModel.jsonImportMessage ?? "Unknown error"))
            }
        }
        .sheet(isPresented: $viewModel.showingAnalytics) {
            NavigationStack {
                ListeningStatsView()
            }
        }
        .sheet(isPresented: $showingAssistant) {
            NavigationStack {
                AssistantView()
            }
        }
        .sheet(isPresented: $viewModel.showingFeedbackForm) {
            FeedbackFormView()
        }
        .sheet(isPresented: $viewModel.showingManualImport) {
            ManualImportView()
        }
        .alert(
            alertTitle(),
            isPresented: Binding(
                get: { viewModel.activeAlert != nil },
                set: { if !$0 { viewModel.dismissAlert() } }
            )
        ) {
            alertButtons()
        } message: {
            alertMessage()
        }
        .alert(
            "Clear Subscriptions",
            isPresented: $viewModel.showClearSubscriptionsConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await viewModel.clearAllSubscriptions()
                }
            }
        } message: {
            Text("This will remove all podcast subscriptions and clear your episode queue. This action cannot be undone.")
        }
        .sheet(isPresented: $showingBackupShare) {
            if let url = backupFileURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $showingBackupImport,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        let counts = try await BackupService.shared.importBackup(from: url)
                        await MainActor.run {
                            viewModel.showAlert(.jsonImport("Restored \(counts.podcasts) podcasts and \(counts.episodes) episodes"))
                        }
                    } catch {
                        await MainActor.run {
                            viewModel.showAlert(.jsonImport("Import failed: \(error.localizedDescription)"))
                        }
                    }
                }
            case .failure(let error):
                viewModel.showAlert(.jsonImport("Error selecting file: \(error.localizedDescription)"))
            }
        }
    }

    private var settingsHero: some View {
        JimmyCard(isHighlighted: true, padding: JimmyDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.lg) {
                VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
                    Text("Jimmy")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.62)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Tune playback, sync, and imports so the app feels like your listening room instead of a control panel.")
                        .font(JimmyDesign.Typography.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: JimmyDesign.Spacing.sm) {
                        settingsHeroChip(title: "Playback", icon: "speedometer")
                        settingsHeroChip(title: "Sync", icon: "icloud")
                        settingsHeroChip(title: "Import", icon: "square.and.arrow.down")
                    }

                    VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
                        settingsHeroChip(title: "Playback", icon: "speedometer")
                        settingsHeroChip(title: "Sync", icon: "icloud")
                        settingsHeroChip(title: "Import", icon: "square.and.arrow.down")
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func settingsHeroChip(title: String, icon: String) -> some View {
        HStack(spacing: JimmyDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.08))
        )
    }
    
    // MARK: - Alert Helper Methods
    private func alertTitle() -> String {
        switch viewModel.activeAlert {
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
        switch viewModel.activeAlert {
        case .resetData:
            return AnyView(
                HStack {
                    Button("Cancel", role: .cancel) { 
                        viewModel.dismissAlert()
                    }
                    Button("Reset", role: .destructive) {
                        Task {
                            await viewModel.resetAllData()
                        }
                        viewModel.dismissAlert()
                    }
                }
            )
        case .clearSubscriptions:
            return AnyView(
                HStack {
                    Button("Cancel", role: .cancel) { 
                        viewModel.dismissAlert()
                    }
                    Button("Clear", role: .destructive) {
                        Task {
                            await viewModel.clearAllSubscriptions()
                        }
                        viewModel.dismissAlert()
                    }
                }
            )
        case .appleImport(_), .subscriptionImport(_), .spotifyImport(_), .jsonImport(_), .none:
            return AnyView(
                Button("OK") {
                    viewModel.dismissAlert()
                }
            )
        }
    }
    
    private func alertMessage() -> Text {
        switch viewModel.activeAlert {
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

// MARK: - Supporting Views

struct ManualImportView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ManualImportView")
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var importMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                JimmyScreenBackground()

                VStack(spacing: 20) {
                    JimmyCard(isHighlighted: true, padding: JimmyDesign.Spacing.xl) {
                        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.lg) {
                            JimmySectionHeader(
                                eyebrow: "Import",
                                title: "Add a podcast by feed URL",
                                subtitle: "Paste an RSS feed and Jimmy will subscribe, fetch episodes, and place it in your library.",
                                icon: "link"
                            )

                            JimmySearchField(
                                text: $urlText,
                                placeholder: "https://example.com/feed.xml",
                                prompt: "Enter RSS feed URL",
                                accessibilityLabel: "Podcast feed URL"
                            )
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)

                            if !importMessage.isEmpty {
                                Text(importMessage)
                                    .font(.caption)
                                    .foregroundColor(importMessage.contains("Error") ? .red : .green)
                                    .multilineTextAlignment(.center)
                            }

                            JimmyPrimaryButton(
                                title: isImporting ? "Importing..." : "Add Podcast",
                                systemImage: "plus.circle.fill",
                                isLoading: isImporting
                            ) {
                                Task {
                                    await importPodcast()
                                }
                            }
                            .disabled(urlText.isEmpty || isImporting)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
            }
        }
        .alert("Import Result", isPresented: $showingAlert) {
            Button("OK") {
                if !importMessage.contains("Error") {
                    dismiss()
                }
            }
        } message: {
            Text(importMessage)
        }
    }
    
    private func importPodcast() async {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Manual Import: Attempting to import URL: \(trimmedURL)")
        
        guard let url = URL(string: trimmedURL) else {
            logger.error("Manual Import: Invalid URL format: \(trimmedURL)")
            importMessage = "Error: Invalid URL format"
            showingAlert = true
            return
        }
        
        isImporting = true
        importMessage = "Importing podcast..."
        logger.info("Manual Import: Starting import from URL: \(url.absoluteString)")
        
        do {
            guard let podcast = try await AppModel.current?.subscribe(feedURL: url) else {
                throw AppModelError.storeNotReady
            }
            let episodeCount = (try? await AppModel.current?.readyStore?.episodes(podcastID: podcast.id).count) ?? 0
            logger.info("Manual Import: Successfully imported \(podcast.title) with \(episodeCount) episodes")

            await MainActor.run {
                importMessage = "Successfully imported '\(podcast.title)' with \(episodeCount) episodes"
                isImporting = false
                showingAlert = true
            }
        } catch {
            logger.error("Manual Import: Failed to import podcast: \(error.localizedDescription)")
            await MainActor.run {
                importMessage = "Error: \(error.localizedDescription)"
                isImporting = false
                showingAlert = true
            }
        }
    }
}

// MARK: - Helper Components

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
        JimmyCard(padding: 20) {
            JimmySectionHeader(
                title: title,
                icon: icon,
                tint: iconColor
            )

            VStack(alignment: .leading, spacing: 16) {
                content
            }
        }
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
        HStack(spacing: JimmyDesign.Spacing.md) {
            SettingsRowIcon(icon: icon)

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
            HStack(spacing: JimmyDesign.Spacing.md) {
                SettingsRowIcon(
                    icon: icon,
                    tint: isDestructive ? .red : .accentColor
                )

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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
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
            HStack(spacing: JimmyDesign.Spacing.md) {
                if isLoading {
                    ZStack {
                        RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                            .frame(width: 36, height: 36)

                        ProgressView()
                            .scaleEffect(0.8)
                    }
                } else {
                    SettingsRowIcon(icon: icon)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct SettingsRowIcon: View {
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                .fill(tint.opacity(0.08))
                .frame(width: 36, height: 36)

            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.system(size: 16, weight: .semibold))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Document Type for Export
// AppDataDocument is defined in Jimmy/Utilities/AppDataDocument.swift

// MARK: - 120fps ProMotion Scroll Optimizer (Shared)
// Note: ProMotionScrollOptimizer and HighPerformanceScrollModifier are defined in LibraryView.swift
