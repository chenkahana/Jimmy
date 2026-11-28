import SwiftUI
import JimmyKit
import UniformTypeIdentifiers
import os

/// Settings as a grouped `Form`. It has no `NavigationStack` of its own, so it works as a tab root
/// and inside a sheet's `NavigationStack`.
struct SettingsView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SettingsView")
    @StateObject private var viewModel = SettingsViewModel.shared
    @State private var showingBackupShare = false
    @State private var showingBackupImport = false
    @State private var backupFileURL: URL?
    @State private var showingAssistant = false
    @State private var showingImport = false

    private static let playbackSpeeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]
    private static let skipBackIntervals: [Double] = [10, 15, 30, 45]
    private static let skipForwardIntervals: [Double] = [10, 15, 30, 45, 60]

    private static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        guard let build = info?["CFBundleVersion"] as? String, build != version else { return version }
        return "\(version) (\(build))"
    }()

    var body: some View {
        Form {
            playbackSection
            appearanceSection
            syncSection
                .fileImporter(
                    isPresented: $showingBackupImport,
                    allowedContentTypes: [.json]
                ) { result in
                    switch result {
                    case .success(let url):
                        Task {
                            do {
                                let counts = try await BackupService.shared.importBackup(from: url)
                                let message = "Restored \(counts.podcasts) podcasts and \(counts.episodes) episodes."
                                viewModel.showAlert(.jsonImport(message))
                            } catch {
                                viewModel.showAlert(.jsonImport("Import failed: \(error.localizedDescription)"))
                            }
                        }
                    case .failure(let error):
                        viewModel.showAlert(.jsonImport("Error selecting file: \(error.localizedDescription)"))
                    }
                }
            importSection
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
            assistantSection
            aboutSection
            #if DEBUG
            developerSection
            #endif
            destructiveSection
        }
        .navigationTitle("Settings")
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
        .sheet(isPresented: $showingImport) {
            OnboardingView()
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
        .sheet(isPresented: $showingBackupShare) {
            if let url = backupFileURL {
                ShareSheet(items: [url])
            }
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
            "Unfollow All Shows?",
            isPresented: $viewModel.showClearSubscriptionsConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await viewModel.clearAllSubscriptions()
                }
            }
        } message: {
            Text("This unfollows every show and clears your queue. It can't be undone.")
        }
    }

    // MARK: - Sections

    private var playbackSection: some View {
        Section {
            Picker("Playback Speed", selection: $viewModel.playbackSpeed) {
                // A speed set in Now Playing between the presets shows here too.
                let speeds = Set(Self.playbackSpeeds + [viewModel.playbackSpeed]).sorted()
                ForEach(speeds, id: \.self) { speed in
                    Text(speed.formatted(.number) + "×").tag(speed)
                }
            }
            Picker("Skip Back", selection: $viewModel.skipBackwardDuration) {
                ForEach(Self.skipBackIntervals, id: \.self) { seconds in
                    Text("\(Int(seconds)) seconds").tag(seconds)
                }
            }
            Picker("Skip Forward", selection: $viewModel.skipForwardDuration) {
                ForEach(Self.skipForwardIntervals, id: \.self) { seconds in
                    Text("\(Int(seconds)) seconds").tag(seconds)
                }
            }
            Picker("Volume Boost", selection: $viewModel.volumeBoost) {
                Text("Off").tag(VolumeBoost.off)
                Text("Normal").tag(VolumeBoost.normal)
                Text("High").tag(VolumeBoost.high)
            }
            Toggle("Voice Clarity", isOn: $viewModel.voiceClarity)
            Toggle("Skip Silence", isOn: $viewModel.skipSilence)
            Toggle("Auto-Load Last Episode", isOn: $viewModel.autoRestoreLastEpisode)
        } header: {
            Text("Playback")
        } footer: {
            Text("Volume Boost evens out quiet and loud shows. High is louder still, for noisy places. Voice Clarity trims rumble and lifts speech slightly. Skip Silence jumps over long pauses in downloaded episodes, once Jimmy has analyzed them. Auto-Load Last Episode opens your last episode when Jimmy starts.")
        }
        .pickerStyle(.menu)
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Color Scheme", selection: $viewModel.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Toggle("High Contrast Mode", isOn: $viewModel.highContrastMode)
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("iCloud Sync", isOn: $viewModel.iCloudSyncEnabled)
            Button("Export Full Backup") {
                exportFullBackup()
            }
            Button("Import Backup") {
                showingBackupImport = true
            }
        } header: {
            Text("Sync & Backup")
        } footer: {
            Text("A full backup also includes playback state and bookmarks.")
        }
    }

    private var importSection: some View {
        Section {
            Button("Import from Another App") {
                showingImport = true
            }
            Button("Add Podcast by URL") {
                viewModel.showingManualImport = true
            }
            progressButton("Import JSON File", isLoading: viewModel.isJSONImporting) {
                viewModel.isJSONImporting = true
            }
            Button("Export App Data") {
                Task {
                    await viewModel.exportAppData()
                }
            }
        } header: {
            Text("Import & Export")
        } footer: {
            Text("A JSON file lists each show with title, publisher and url fields.")
        }
    }

    private var assistantSection: some View {
        Section {
            Button("Assistant") {
                showingAssistant = true
            }
        } footer: {
            Text("Ask Jimmy to play, queue, search, follow or set a sleep timer.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.appVersion)
            Button("Send Feedback") {
                viewModel.showingFeedbackForm = true
            }
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section("Developer") {
            NavigationLink("Listening Stats") {
                ListeningStatsView()
            }
        }
    }
    #endif

    private var destructiveSection: some View {
        Section {
            Button("Unfollow All Shows", role: .destructive) {
                viewModel.showClearSubscriptionsConfirmation = true
            }
            #if DEBUG
            Button("Clear Episode Cache", role: .destructive) {
                Task {
                    await viewModel.clearEpisodeCache()
                }
            }
            Button("Reset All Data", role: .destructive) {
                viewModel.showAlert(.resetData)
            }
            #endif
        } footer: {
            Text("Unfollowing all shows removes every show and empties your queue.")
        }
    }

    // MARK: - Rows

    private func progressButton(_ title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isLoading {
                    ProgressView()
                }
            }
        }
        .disabled(isLoading)
    }

    private func exportFullBackup() {
        Task {
            do {
                backupFileURL = try await BackupService.shared.exportBackup()
                showingBackupShare = true
            } catch {
                logger.error("Backup export failed: \(error)")
            }
        }
    }

    // MARK: - Alerts

    private func alertTitle() -> String {
        switch viewModel.activeAlert {
        case .resetData:
            return "Reset All Data?"
        case .subscriptionImport:
            return "Subscription Import"
        case .jsonImport:
            return "Import"
        case .clearSubscriptions:
            return "Unfollow All Shows?"
        case .none:
            return ""
        }
    }

    @ViewBuilder
    private func alertButtons() -> some View {
        switch viewModel.activeAlert {
        case .resetData:
            Button("Cancel", role: .cancel) {
                viewModel.dismissAlert()
            }
            Button("Reset", role: .destructive) {
                Task {
                    await viewModel.resetAllData()
                }
                viewModel.dismissAlert()
            }
        case .clearSubscriptions:
            Button("Cancel", role: .cancel) {
                viewModel.dismissAlert()
            }
            Button("Clear", role: .destructive) {
                Task {
                    await viewModel.clearAllSubscriptions()
                }
                viewModel.dismissAlert()
            }
        case .subscriptionImport, .jsonImport, .none:
            Button("OK") {
                viewModel.dismissAlert()
            }
        }
    }

    private func alertMessage() -> Text {
        switch viewModel.activeAlert {
        case .resetData:
            return Text("This deletes all subscriptions, your queue and settings. It can't be undone.")
        case .subscriptionImport(let message),
             .jsonImport(let message):
            return Text(message)
        case .clearSubscriptions:
            return Text("This unfollows every show and clears your queue. It can't be undone.")
        case .none:
            return Text("")
        }
    }
}

// MARK: - Add by URL

struct ManualImportView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ManualImportView")
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var resultMessage = ""
    @State private var didImport = false
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL", text: $urlText, prompt: Text("https://example.com/feed.xml"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(startImport)
                        .disabled(isImporting)
                } footer: {
                    Text("Paste a podcast's RSS feed address to follow it.")
                }
            }
            .navigationTitle("Add by URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("Add", action: startImport)
                            .disabled(trimmedURL.isEmpty)
                    }
                }
            }
        }
        .alert(didImport ? "Podcast Added" : "Couldn't Add Podcast", isPresented: $showingResult) {
            Button("OK") {
                if didImport {
                    dismiss()
                }
            }
        } message: {
            Text(resultMessage)
        }
    }

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startImport() {
        guard !trimmedURL.isEmpty, !isImporting else { return }
        isImporting = true
        Task {
            await importPodcast()
        }
    }

    private func importPodcast() async {
        let trimmedURL = trimmedURL
        logger.info("Manual Import: Attempting to import URL: \(trimmedURL)")

        guard let url = URL(string: trimmedURL) else {
            logger.error("Manual Import: Invalid URL format: \(trimmedURL)")
            finish(success: false, message: "That isn't a valid URL.")
            return
        }

        isImporting = true
        logger.info("Manual Import: Starting import from URL: \(url.absoluteString)")

        do {
            guard let podcast = try await AppModel.current?.subscribe(feedURL: url) else {
                throw AppModelError.storeNotReady
            }
            let episodeCount = (try? await AppModel.current?.readyStore?.episodes(podcastID: podcast.id).count) ?? 0
            logger.info("Manual Import: Successfully imported \(podcast.title) with \(episodeCount) episodes")
            finish(success: true, message: "Following \(podcast.title), with \(episodeCount) episodes.")
        } catch {
            logger.error("Manual Import: Failed to import podcast: \(error.localizedDescription)")
            finish(success: false, message: error.localizedDescription)
        }
    }

    private func finish(success: Bool, message: String) {
        didImport = success
        resultMessage = message
        isImporting = false
        showingResult = true
    }
}
