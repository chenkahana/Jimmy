import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel.shared

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
                            subtitle: viewModel.darkMode ? "Currently using dark appearance" : "Currently using light appearance",
                            icon: viewModel.darkMode ? "moon.fill" : "sun.max.fill",
                            isOn: $viewModel.darkMode
                        )
                        
                        SettingsToggle(
                            title: "High Contrast Mode",
                            icon: "eye.circle.fill",
                            isOn: $viewModel.highContrastMode
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
                            isLoading: viewModel.isJSONImporting,
                            action: { 
                                Task {
                                    await viewModel.importFromJSON()
                                }
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
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: ProMotionDebugView()) {
                            HStack {
                                Image(systemName: "display")
                                    .foregroundColor(.green)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ProMotion Debug")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                    Text("Monitor 120Hz display performance")
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
                            action: { viewModel.showingFeedbackForm = true }
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
                
                // Footer spacing
                Color.clear
                    .frame(height: 50)
            }
            .padding(.horizontal, 20)
        }
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
                    await viewModel.importFromJSON()
                }
            case .failure(let error):
                viewModel.jsonImportMessage = "Error selecting file: \(error.localizedDescription)"
                viewModel.showAlert(.jsonImport(viewModel.jsonImportMessage ?? "Unknown error"))
            }
        }
        .sheet(isPresented: $viewModel.showingAnalytics) {
            AnalyticsView()
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
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add Podcast by URL")
                    .font(.title2.bold())
                
                TextField("Enter RSS feed URL", text: $urlText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Add Podcast") {
                    // Handle URL import
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.isEmpty)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title2)
                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Spacer()
            }
            
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
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
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.title3)
            
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
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isDestructive ? .red : .accentColor)
                    .font(.title3)
                
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
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .font(.title3)
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
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
    }
}

// MARK: - Document Type for Export
// AppDataDocument is defined in Jimmy/Utilities/AppDataDocument.swift
