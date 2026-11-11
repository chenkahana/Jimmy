import SwiftUI
import Combine

/// Enhanced import view with comprehensive progress tracking and error handling
struct BulletproofImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = BulletproofAudioImporter.shared
    @State private var fileName: String
    @State private var showName: String = ""
    @State private var selectedShowID: UUID?
    @State private var isCreatingNewShow: Bool = false
    @State private var localShows: [Podcast] = []
    @State private var showingError: Bool = false
    @State private var lastError: BulletproofImportError?
    
    let audioURL: URL
    let onSuccess: (Episode) -> Void
    let onCancel: () -> Void
    
    init(
        audioURL: URL,
        onSuccess: @escaping (Episode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.audioURL = audioURL
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        self._fileName = State(initialValue: audioURL.deletingPathExtension().lastPathComponent)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if importer.isImporting {
                    importProgressView
                } else {
                    importConfigurationView
                }
            }
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadLocalShows()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(importer.isImporting ? "Cancel" : "Close") {
                        if importer.isImporting {
                            importer.cancelImport()
                        }
                        onCancel()
                        dismiss()
                    }
                }
                
                if !importer.isImporting {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Import") {
                            startImport()
                        }
                        .disabled(!canImport)
                    }
                }
            }
            .alert("Import Error", isPresented: $showingError) {
                Button("OK") { showingError = false }
                if let error = lastError, error.errorDescription?.contains("retry") == true {
                    Button("Retry") {
                        showingError = false
                        startImport()
                    }
                }
            } message: {
                Text(lastError?.errorDescription ?? "Unknown error occurred")
            }
        }
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    // MARK: - Import Configuration View
    
    @ViewBuilder
    private var importConfigurationView: some View {
        Form {
            Section("Audio File") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.blue)
                        Text(audioURL.lastPathComponent)
                            .font(.headline)
                    }
                    
                    if let fileSize = getFileSize() {
                        Text("Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                TextField("Episode name", text: $fileName)
                    .textInputAutocapitalization(.words)
            }
            
            Section("Destination") {
                Toggle("Create new show", isOn: $isCreatingNewShow)
                
                if isCreatingNewShow {
                    TextField("New show name", text: $showName)
                        .textInputAutocapitalization(.words)
                } else {
                    if localShows.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No local shows available")
                                .foregroundColor(.secondary)
                            Text("Toggle above to create a new show")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Select show", selection: $selectedShowID) {
                            Text("Choose a show").tag(nil as UUID?)
                            ForEach(localShows) { show in
                                Text(show.title).tag(show.id as UUID?)
                            }
                        }
                    }
                }
            }
            
            Section("Import Details") {
                HStack {
                    Text("Artist")
                    Spacer()
                    Text(isCreatingNewShow ? "Local Files" : (selectedShow?.author ?? "Local Files"))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Date Added")
                    Spacer()
                    Text(Date().formatted(date: .abbreviated, time: .shortened))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Format")
                    Spacer()
                    Text(audioURL.pathExtension.uppercased())
                        .foregroundColor(.secondary)
                }
            }
            
            if !importer.recentImports.isEmpty {
                Section("Recent Imports") {
                    ForEach(Array(importer.recentImports.prefix(3).enumerated()), id: \.offset) { _, result in
                        recentImportRow(result)
                    }
                }
            }
        }
    }
    
    // MARK: - Import Progress View
    
    @ViewBuilder
    private var importProgressView: some View {
        VStack(spacing: 24) {
            // File Info
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text(fileName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                
                Text("Importing to \(isCreatingNewShow ? showName : selectedShow?.title ?? "Unknown Show")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Progress Indicator
            if let progress = importer.currentImport {
                VStack(spacing: 16) {
                    // Circular Progress
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 8)
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .trim(from: 0, to: progress.progress)
                            .stroke(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: progress.progress)
                        
                        VStack {
                            Text("\(Int(progress.progress * 100))%")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(progress.phase.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Status Message
                    Text(progress.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    // Estimated Time
                    if let timeRemaining = progress.estimatedTimeRemaining,
                       timeRemaining > 0 && timeRemaining < 300 { // Only show if < 5 minutes
                        Text("About \(formatTime(timeRemaining)) remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Phase Progress Bar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            ForEach(ImportProgress.ImportPhase.allCases, id: \.self) { phase in
                                phaseIndicator(for: phase, current: progress.phase, progress: progress.progress)
                            }
                        }
                        
                        Text("Current: \(progress.phase.rawValue)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - UI Components
    
    @ViewBuilder
    private func recentImportRow(_ result: ImportResult) -> some View {
        HStack {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.isSuccess ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                if let episode = result.episode {
                    Text(episode.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("Successfully imported")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = result.error {
                    Text("Import failed")
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func phaseIndicator(for phase: ImportProgress.ImportPhase, current: ImportProgress.ImportPhase, progress: Double) -> some View {
        let phaseIndex = ImportProgress.ImportPhase.allCases.firstIndex(of: phase) ?? 0
        let currentIndex = ImportProgress.ImportPhase.allCases.firstIndex(of: current) ?? 0
        
        Rectangle()
            .fill(phaseIndex <= currentIndex ? .blue : Color.secondary.opacity(0.3))
            .frame(height: 4)
            .animation(.easeInOut(duration: 0.3), value: currentIndex)
    }
    
    // MARK: - Computed Properties
    
    private var canImport: Bool {
        !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isCreatingNewShow ? !showName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selectedShowID != nil)
    }
    
    private var selectedShow: Podcast? {
        guard let showID = selectedShowID else { return nil }
        return localShows.first { $0.id == showID }
    }
    
    // MARK: - Methods
    
    private func loadLocalShows() {
        localShows = (AppModel.current?.podcasts.map { $0.asLegacyPodcast() } ?? [])
            .filter { $0.feedURL.scheme == "local" }
    }
    
    private func startImport() {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShowName = showName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            let result = await importer.importFile(
                from: audioURL,
                fileName: trimmedFileName,
                showName: isCreatingNewShow ? trimmedShowName : (selectedShow?.title ?? trimmedShowName),
                existingShowID: isCreatingNewShow ? nil : selectedShowID
            )
            
            await MainActor.run {
                switch result {
                case .success(let episode):
                    if let size = getFileSize() {
                        Log.data.info("Audio file import completed, size=\(size)")
                    } else {
                        Log.data.info("Audio file import completed")
                    }
                    onSuccess(episode)
                    dismiss()
                    
                case .failure(let error):
                    lastError = error
                    showingError = true
                }
            }
        }
    }
    
    private func getFileSize() -> Int64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Preview

struct BulletproofImportView_Previews: PreviewProvider {
    static var previews: some View {
        BulletproofImportView(
            audioURL: URL(string: "file:///sample.mp3")!,
            onSuccess: { _ in },
            onCancel: { }
        )
    }
}
