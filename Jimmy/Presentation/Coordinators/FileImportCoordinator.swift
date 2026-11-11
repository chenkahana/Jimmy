import SwiftUI
import Combine
import os.log

/// Enhanced file import coordinator with bulletproof error handling
@MainActor 
class FileImportCoordinator: ObservableObject {
    @Published var fileURL: URL?
    @Published var importProgress: ImportProgress?
    @Published var isImporting: Bool = false
    @Published var lastImportResult: ImportResult?
    @Published var showingImportSuccess: Bool = false
    @Published var showingImportError: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.jimmy.import", category: "FileImportCoordinator")
    
    init() {
        // Listen to the bulletproof importer
        BulletproofAudioImporter.shared.$pendingURL
            .compactMap { $0 }
            .assign(to: \.fileURL, on: self)
            .store(in: &cancellables)
        
        BulletproofAudioImporter.shared.$currentImport
            .assign(to: \.importProgress, on: self)
            .store(in: &cancellables)
        
        BulletproofAudioImporter.shared.$isImporting
            .assign(to: \.isImporting, on: self)
            .store(in: &cancellables)
        
        // Also listen to legacy importer for backwards compatibility
        SharedAudioImporter.shared.$pendingURL
            .compactMap { $0 }
            .sink { [weak self] url in
                // Migrate to bulletproof importer
                self?.handleLegacyImport(url)
            }
            .store(in: &cancellables)
    }
    
    /// Handle imports from the legacy system
    private func handleLegacyImport(_ url: URL) {
        logger.info("📱 Migrating legacy import to bulletproof system: \(url.lastPathComponent)")
        BulletproofAudioImporter.shared.handleSharedFile(from: url)
    }
    
    /// Start bulletproof import process
    func startBulletproofImport(
        from url: URL,
        fileName: String,
        showName: String,
        existingShowID: UUID?
    ) {
        logger.info("🚀 Starting bulletproof import via coordinator")
        
        Task {
            let result = await BulletproofAudioImporter.shared.importFile(
                from: url,
                fileName: fileName,
                showName: showName,
                existingShowID: existingShowID
            )
            
            await MainActor.run {
                self.lastImportResult = result
                
                switch result {
                case .success(let episode):
                    self.showingImportSuccess = true
                    self.logger.info("✅ Import successful: \(episode.title)")
                    
                    // Notify other parts of the app
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AudioFileImported"),
                        object: episode
                    )
                    
                case .failure(let error):
                    self.showingImportError = true
                    self.logger.error("❌ Import failed: \(error.localizedDescription)")
                }
                
                // Clear the pending URL
                self.fileURL = nil
            }
        }
    }
    
    /// Cancel current import
    func cancelImport() {
        logger.info("🛑 Canceling import via coordinator")
        BulletproofAudioImporter.shared.cancelImport()
        fileURL = nil
    }
    
    /// Clear import state
    func clearImportState() {
        fileURL = nil
        lastImportResult = nil
        showingImportSuccess = false
        showingImportError = false
    }
    
    /// Get user-friendly progress message
    var progressMessage: String {
        guard let progress = importProgress else { return "" }
        
        let percentage = Int(progress.progress * 100)
        let timeRemaining = progress.estimatedTimeRemaining.map { 
            formatTimeRemaining($0) 
        } ?? ""
        
        if timeRemaining.isEmpty {
            return "\(progress.phase.rawValue) (\(percentage)%)"
        } else {
            return "\(progress.phase.rawValue) (\(percentage)%) - \(timeRemaining) remaining"
        }
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            let minutes = Int(seconds) / 60
            return "\(minutes)m"
        }
    }
}

// MARK: - Import Result Extensions

extension ImportResult {
    var userFriendlyMessage: String {
        switch self {
        case .success(let episode):
            return "Successfully imported '\(episode.title)'"
        case .failure(let error):
            return error.errorDescription ?? "Import failed"
        }
    }
    
    var successIcon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }
    
    var successColor: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        }
    }
} 