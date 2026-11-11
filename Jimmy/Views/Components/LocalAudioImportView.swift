import SwiftUI
import JimmyKit

/// Naming sheet for a local audio file shared to or opened by the app — the only decision left to
/// make is the episode's title; it always lands on the fixed "Imported audio" show (see
/// `LocalAudioImporter`), so there's no show picker to show.
struct LocalAudioImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = LocalAudioImporter.shared
    @State private var title: String
    @State private var showingError = false

    let audioURL: URL
    let onSuccess: (JimmyKit.Episode) -> Void
    let onCancel: () -> Void

    init(audioURL: URL, onSuccess: @escaping (JimmyKit.Episode) -> Void, onCancel: @escaping () -> Void) {
        self.audioURL = audioURL
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        self._title = State(initialValue: audioURL.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Audio File") {
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

                    TextField("Episode name", text: $title)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    HStack {
                        Text("Show")
                        Spacer()
                        Text("Imported audio")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .disabled(importer.isImporting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if importer.isImporting {
                        ProgressView()
                    } else {
                        Button("Import") { startImport() }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .alert("Import Failed", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text("Couldn't import this audio file. Please try again.")
            }
        }
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func startImport() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if let episode = await importer.importFile(from: audioURL, title: trimmedTitle) {
                await MainActor.run {
                    onSuccess(episode)
                    dismiss()
                }
            } else {
                await MainActor.run { showingError = true }
            }
        }
    }

    private func getFileSize() -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: audioURL.path))?[.size] as? Int64
    }
}
