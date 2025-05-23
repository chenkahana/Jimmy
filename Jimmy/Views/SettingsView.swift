import SwiftUI

struct SettingsView: View {
    @AppStorage("playbackSpeed") private var playbackSpeed: Double = 1.0
    @AppStorage("darkMode") private var darkMode: Bool = false
    @AppStorage("episodeSwipeAction") private var episodeSwipeAction: String = "addToQueue"
    @AppStorage("queueSwipeAction") private var queueSwipeAction: String = "markAsPlayed"
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false
    @AppStorage("highContrastMode") private var highContrastMode: Bool = false
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingResetAlert = false
    @State private var showingAnalytics = false

    var body: some View {
        Form {
            Section(header: Text("Playback")) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Picker("Speed", selection: $playbackSpeed) {
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
            Section(header: Text("Backup & Restore")) {
                Toggle(isOn: $iCloudSyncEnabled) {
                    Text("Enable iCloud Sync")
                }
                Button("Export App Data") {
                    isExporting = true
                }
                Button("Import App Data") {
                    isImporting = true
                }
                if let error = importError {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            Section(header: Text("Debug/Developer Mode")) {
                Button("View Analytics") {
                    showingAnalytics = true
                }
                Button("Reset All Data", role: .destructive) {
                    showingResetAlert = true
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
        .alert("Reset All Data", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                DebugHelper.shared.resetAllData()
            }
        } message: {
            Text("This will delete all subscriptions, queue, and settings. This action cannot be undone.")
        }
        .sheet(isPresented: $showingAnalytics) {
            AnalyticsView()
        }
    }
} 