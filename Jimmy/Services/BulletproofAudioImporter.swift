import Foundation
import AVFoundation
import UniformTypeIdentifiers
import Combine
import os.log

/// Comprehensive error types for bulletproof audio import
enum BulletproofImportError: Error, LocalizedError {
    case invalidFileFormat
    case fileTooLarge(size: Int64, maxSize: Int64)
    case insufficientStorageSpace(required: Int64, available: Int64)
    case fileCorrupted
    case networkUnavailable
    case databaseUnavailable
    case importInProgress
    case retryLimitExceeded
    case fileAccessDenied
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidFileFormat:
            return "This file format is not supported for audio import"
        case .fileTooLarge(let size, let maxSize):
            return "File is too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Maximum size is \(ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file))"
        case .insufficientStorageSpace(let required, let available):
            return "Insufficient storage space. Need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), but only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available"
        case .fileCorrupted:
            return "The audio file appears to be corrupted and cannot be imported"
        case .networkUnavailable:
            return "Network connection required but unavailable"
        case .databaseUnavailable:
            return "Database temporarily unavailable. Please try again"
        case .importInProgress:
            return "Another import is currently in progress. Please wait"
        case .retryLimitExceeded:
            return "Import failed after multiple attempts"
        case .fileAccessDenied:
            return "Cannot access the audio file. Please check permissions"
        case .unknownError(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
}

/// Import progress tracking
struct ImportProgress {
    let id: UUID
    let fileName: String
    let phase: ImportPhase
    let progress: Double // 0.0 to 1.0
    let message: String
    let startTime: Date
    var estimatedTimeRemaining: TimeInterval?
    
    enum ImportPhase: String, CaseIterable {
        case validation = "Validating file"
        case preparation = "Preparing import"
        case copying = "Copying file"
        case processing = "Processing audio"
        case database = "Saving to library"
        case completion = "Completing import"
        case cleanup = "Cleaning up"
    }
}

/// Bulletproof audio file importer with comprehensive error handling and recovery
@MainActor
class BulletproofAudioImporter: ObservableObject {
    static let shared = BulletproofAudioImporter()
    
    // MARK: - Published Properties
    @Published var pendingURL: URL?
    @Published var currentImport: ImportProgress?
    @Published var isImporting: Bool = false
    @Published var recentImports: [ImportResult] = []
    
    // MARK: - Configuration
    private let maxFileSize: Int64 = 2 * 1024 * 1024 * 1024 // 2GB
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 2.0
    private let supportedFormats: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg"]
    
    // MARK: - Dependencies
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.jimmy.import", category: "BulletproofAudioImporter")
    private let episodeRepository: EpisodeRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    
    // MARK: - Internal State
    private var activeImportTask: Task<Void, Never>?
    private let importQueue = DispatchQueue(label: "com.jimmy.audioImport", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    private init(
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        podcastRepository: PodcastRepositoryProtocol = DIContainer.shared.podcastRepository,
        playbackStateRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository
    ) {
        self.episodeRepository = episodeRepository
        self.podcastRepository = podcastRepository
        self.playbackStateRepository = playbackStateRepository
        
        setupCleanupTimer()
    }
    
    // MARK: - Public Interface
    
    /// Trigger import UI for shared audio file
    func handleSharedFile(from url: URL) {
        logger.info("📱 Handling shared file: \(url.lastPathComponent)")
        
        // Quick validation before showing UI
        guard isValidAudioFile(url) else {
            logger.error("❌ Invalid audio file format: \(url.pathExtension)")
            return
        }
        
        pendingURL = url
    }
    
    /// Import audio file with comprehensive error handling and recovery
    func importFile(
        from url: URL,
        fileName: String,
        showName: String,
        existingShowID: UUID?
    ) async -> ImportResult {
        logger.info("🚀 Starting bulletproof import: \(fileName)")
        
        // Prevent concurrent imports
        guard !isImporting else {
            logger.warning("⚠️ Import already in progress")
            return .failure(.importInProgress)
        }
        
        isImporting = true
        
        let importID = UUID()
        let startTime = Date()
        
        // Cancel any existing import task
        activeImportTask?.cancel()
        
        // Create import task with comprehensive error handling
        activeImportTask = Task { [weak self] in
            guard let self = self else { return }
            
            let result = await self.performImportWithRetry(
                importID: importID,
                url: url,
                fileName: fileName,
                showName: showName,
                existingShowID: existingShowID,
                startTime: startTime,
                maxRetryAttempts: self.maxRetryAttempts,
                retryDelay: self.retryDelay
            )
            
            await MainActor.run {
                self.isImporting = false
                self.currentImport = nil
                self.pendingURL = nil
                self.recentImports.insert(result, at: 0)
                
                // Keep only last 10 import results
                if self.recentImports.count > 10 {
                    self.recentImports.removeLast()
                }
            }
        }
        
        // Wait for completion
        await activeImportTask?.value
        
        return recentImports.first ?? .failure(.unknownError(NSError(domain: "Import", code: -1)))
    }
    
    /// Cancel current import
    func cancelImport() {
        logger.info("🛑 Canceling current import")
        activeImportTask?.cancel()
        
        isImporting = false
        currentImport = nil
        
        // Cleanup any partial files
        Task.detached(priority: .background) { [weak self] in
            await self?.cleanupPartialImports()
        }
    }
    
    // MARK: - Core Import Logic
    
    private func performImportWithRetry(
        importID: UUID,
        url: URL,
        fileName: String,
        showName: String,
        existingShowID: UUID?,
        startTime: Date,
        maxRetryAttempts: Int,
        retryDelay: TimeInterval
    ) async -> ImportResult {
        var lastError: BulletproofImportError?
        
        for attempt in 1...maxRetryAttempts {
            logger.info("📊 Import attempt \(attempt) of \(maxRetryAttempts)")
            
            let result = await performSingleImport(
                importID: importID,
                url: url,
                fileName: fileName,
                showName: showName,
                existingShowID: existingShowID,
                startTime: startTime,
                attempt: attempt
            )
            
            switch result {
            case .success:
                logger.info("✅ Import successful on attempt \(attempt)")
                return result
            case .failure(let error):
                lastError = error
                logger.error("❌ Import attempt \(attempt) failed: \(error.localizedDescription)")
                
                // Don't retry for permanent errors
                switch error {
                case .invalidFileFormat, .fileTooLarge, .fileCorrupted, .fileAccessDenied:
                    logger.info("🚫 Not retrying due to permanent error type")
                    return .failure(error)
                default:
                    break
                }
                
                // Wait before retry (except on last attempt)
                if attempt < maxRetryAttempts {
                    logger.info("⏳ Waiting \(retryDelay)s before retry")
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }
        
        logger.error("💥 All import attempts failed")
        return .failure(lastError ?? .retryLimitExceeded)
    }
    
    private func performSingleImport(
        importID: UUID,
        url: URL,
        fileName: String,
        showName: String,
        existingShowID: UUID?,
        startTime: Date,
        attempt: Int
    ) async -> ImportResult {
        do {
            // Phase 1: Validation
            await updateProgress(importID, .validation, 0.1, "Validating audio file...", startTime)
            try await validateFile(url)
            
            // Phase 2: Preparation
            await updateProgress(importID, .preparation, 0.2, "Preparing import directories...", startTime)
            let (podcast, destinationURL) = try await prepareImport(fileName: fileName, showName: showName, existingShowID: existingShowID)
            
            // Phase 3: File Copy with Progress
            await updateProgress(importID, .copying, 0.3, "Copying audio file...", startTime)
            try await copyFileWithProgress(from: url, to: destinationURL, importID: importID, startTime: startTime)
            
            // Phase 4: Audio Processing
            await updateProgress(importID, .processing, 0.8, "Processing audio metadata...", startTime)
            let audioMetadata = try await extractAudioMetadata(from: destinationURL)
            
            // Phase 5: Database Transaction
            await updateProgress(importID, .database, 0.9, "Saving to library...", startTime)
            let episode = try await createEpisodeWithTransaction(
                fileName: fileName,
                podcast: podcast,
                destinationURL: destinationURL,
                metadata: audioMetadata
            )
            
            // Phase 6: Completion
            await updateProgress(importID, .completion, 1.0, "Import completed successfully!", startTime)
            
            logger.info("🎉 Import completed successfully: \(episode.title)")
            return .success(episode)
            
        } catch {
            logger.error("💥 Import failed in attempt \(attempt): \(error)")
            
            // Cleanup on failure
            await cleanupFailedImport(at: url, fileName: fileName)
            
            if let importError = error as? BulletproofImportError {
                return .failure(importError)
            } else {
                return .failure(.unknownError(error))
            }
        }
    }
    
    // MARK: - Validation
    
    private func validateFile(_ url: URL) async throws {
        logger.info("🔍 Validating file: \(url.lastPathComponent)")
        
        // Check file accessibility
        guard fileManager.fileExists(atPath: url.path) else {
            throw BulletproofImportError.fileAccessDenied
        }
        
        // Check file format
        guard isValidAudioFile(url) else {
            throw BulletproofImportError.invalidFileFormat
        }
        
        // Check file size
        let fileSize = try fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        guard fileSize <= maxFileSize else {
            throw BulletproofImportError.fileTooLarge(size: fileSize, maxSize: maxFileSize)
        }
        
        // Check available storage
        let availableSpace = try getAvailableStorageSpace()
        guard availableSpace >= fileSize * 2 else { // 2x for safety
            throw BulletproofImportError.insufficientStorageSpace(required: fileSize * 2, available: availableSpace)
        }
        
        // Quick audio format validation
        try await validateAudioFormat(url)
        
        logger.info("✅ File validation passed")
    }
    
    private func isValidAudioFile(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return supportedFormats.contains(fileExtension)
    }
    
    private func validateAudioFormat(_ url: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let asset = AVAsset(url: url)
            
            Task {
                do {
                    let isPlayable = try await asset.load(.isPlayable)
                    guard isPlayable else {
                        continuation.resume(throwing: BulletproofImportError.fileCorrupted)
                        return
                    }
                    
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard !tracks.isEmpty else {
                        continuation.resume(throwing: BulletproofImportError.fileCorrupted)
                        return
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: BulletproofImportError.fileCorrupted)
                }
            }
        }
    }
    
    private func getAvailableStorageSpace() throws -> Int64 {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let resourceValues = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
    }
    
    // MARK: - Import Preparation
    
    private func prepareImport(fileName: String, showName: String, existingShowID: UUID?) async throws -> (Podcast, URL) {
        logger.info("🛠 Preparing import for show: \(showName)")
        
        // Get or create podcast
        let podcast = try await getOrCreatePodcastSafely(showName: showName, existingShowID: existingShowID)
        
        // Create destination URL
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseDirectory = documentsURL.appendingPathComponent("ImportedAudio")
        let showDirectory = baseDirectory.appendingPathComponent(sanitizeFileName(podcast.title))
        let destinationURL = showDirectory.appendingPathComponent(sanitizeFileName(fileName))
        
        // Ensure directory exists
        try fileManager.createDirectory(at: showDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Handle existing files
        if fileManager.fileExists(atPath: destinationURL.path) {
            let uniqueURL = try generateUniqueFileName(destinationURL)
            logger.info("📁 File exists, using unique name: \(uniqueURL.lastPathComponent)")
            return (podcast, uniqueURL)
        }
        
        return (podcast, destinationURL)
    }
    
    private func getOrCreatePodcastSafely(showName: String, existingShowID: UUID?) async throws -> Podcast {
        // Try existing podcast first
        if let existingShowID = existingShowID {
            do {
                if let existingPodcast = try await podcastRepository.fetchPodcast(id: existingShowID, ignoreCache: false) {
                    logger.info("📚 Using existing podcast: \(existingPodcast.title)")
                    return existingPodcast
                }
            } catch {
                logger.warning("⚠️ Failed to fetch existing podcast, creating new one")
            }
        }
        
        // Create new podcast with retry
        for attempt in 1...3 {
            do {
                let newPodcast = Podcast(
                    id: UUID(),
                    title: showName,
                    author: "Local Files",
                    description: "Custom show for imported audio files",
                    feedURL: URL(string: "local://\(UUID().uuidString)")!,
                    artworkURL: nil
                )
                
                try await podcastRepository.addPodcast(newPodcast)
                
                // Verify creation
                if let savedPodcast = try await podcastRepository.fetchPodcast(id: newPodcast.id, ignoreCache: true) {
                    logger.info("✅ Created new podcast: \(savedPodcast.title)")
                    return savedPodcast
                }
                
                throw BulletproofImportError.databaseUnavailable
                
            } catch {
                if attempt == 3 {
                    throw BulletproofImportError.databaseUnavailable
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        throw BulletproofImportError.databaseUnavailable
    }
    
    // MARK: - File Operations
    
    private func copyFileWithProgress(from sourceURL: URL, to destinationURL: URL, importID: UUID, startTime: Date) async throws {
        logger.info("📋 Copying file to: \(destinationURL.lastPathComponent)")
        
        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0
        
        // For large files, use progress-aware copy
        if fileSize > 100 * 1024 * 1024 { // 100MB
            try await copyLargeFileWithProgress(from: sourceURL, to: destinationURL, importID: importID, startTime: startTime)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            await updateProgress(importID, .copying, 0.7, "File copied successfully", startTime)
        }
        
        // Verify copy
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw BulletproofImportError.fileAccessDenied
        }
        
        let copiedSize = try fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64 ?? 0
        guard copiedSize == fileSize else {
            try? fileManager.removeItem(at: destinationURL)
            throw BulletproofImportError.fileCorrupted
        }
        
        logger.info("✅ File copied and verified successfully")
    }
    
    private func copyLargeFileWithProgress(from sourceURL: URL, to destinationURL: URL, importID: UUID, startTime: Date) async throws {
        let chunkSize = 1024 * 1024 // 1MB chunks
        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0
        
        let inputStream = InputStream(url: sourceURL)
        let outputStream = OutputStream(url: destinationURL, append: false)
        
        guard let input = inputStream, let output = outputStream else {
            throw BulletproofImportError.fileAccessDenied
        }
        
        input.open()
        output.open()
        
        defer {
            input.close()
            output.close()
        }
        
        var totalBytesWritten: Int64 = 0
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }
        
        while input.hasBytesAvailable {
            let bytesRead = input.read(buffer, maxLength: chunkSize)
            if bytesRead > 0 {
                let bytesWritten = output.write(buffer, maxLength: bytesRead)
                if bytesWritten != bytesRead {
                    throw BulletproofImportError.fileAccessDenied
                }
                totalBytesWritten += Int64(bytesWritten)
                
                // Update progress
                let progress = 0.3 + (Double(totalBytesWritten) / Double(fileSize)) * 0.4 // 30% to 70%
                await updateProgress(importID, .copying, progress, "Copying... \(formatBytes(totalBytesWritten))/\(formatBytes(fileSize))", startTime)
            } else if bytesRead < 0 {
                throw BulletproofImportError.fileAccessDenied
            }
        }
    }
    
    // MARK: - Audio Processing
    
    private func extractAudioMetadata(from url: URL) async throws -> AudioMetadata {
        logger.info("🎵 Extracting audio metadata")
        
        return try await withCheckedThrowingContinuation { continuation in
            let asset = AVAsset(url: url)
            
            Task {
                do {
                    let duration = try await asset.load(.duration)
                    let durationSeconds = CMTimeGetSeconds(duration)
                    
                    let metadata = AudioMetadata(
                        duration: durationSeconds.isFinite ? durationSeconds : 0,
                        fileSize: (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    )
                    
                    continuation.resume(returning: metadata)
                } catch {
                    // Fallback to basic metadata
                    let metadata = AudioMetadata(
                        duration: 0,
                        fileSize: (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    )
                    continuation.resume(returning: metadata)
                }
            }
        }
    }
    
    // MARK: - Database Operations
    
    private func createEpisodeWithTransaction(
        fileName: String,
        podcast: Podcast,
        destinationURL: URL,
        metadata: AudioMetadata
    ) async throws -> Episode {
        logger.info("💾 Creating episode with database transaction")
        
        // Create episode with deterministic ID
        let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: podcast.feedURL,
            audioURL: destinationURL,
            title: fileName,
            publishedDate: Date()
        )
        
        let episode = Episode(
            id: deterministicID,
            title: fileName,
            podcastID: podcast.id,
            publishedDate: Date(),
            duration: metadata.duration,
            artworkURL: nil,
            description: "Imported audio file (\(formatBytes(metadata.fileSize)))",
            audioURL: destinationURL
        )
        
        let playbackState = PlaybackState(
            episodeID: episode.id,
            position: 0,
            finished: false,
            updatedAt: Date()
        )
        
        let episodeWithPlayback = EpisodeWithPlaybackState(
            episode: episode,
            playbackState: playbackState
        )
        
        // Save with retries
        for attempt in 1...3 {
            do {
                try await episodeRepository.saveEpisodes([episodeWithPlayback], for: podcast.id)
                try await playbackStateRepository.savePlaybackState(playbackState)
                
                logger.info("✅ Episode saved successfully to database")
                return episode
                
            } catch {
                logger.error("❌ Database save attempt \(attempt) failed: \(error)")
                if attempt == 3 {
                    throw BulletproofImportError.databaseUnavailable
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        throw BulletproofImportError.databaseUnavailable
    }
    
    // MARK: - Progress Tracking
    
    private func updateProgress(_ id: UUID, _ phase: ImportProgress.ImportPhase, _ progress: Double, _ message: String, _ startTime: Date) async {
        let elapsed = Date().timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let estimatedRemaining = estimatedTotal - elapsed
        
        let importProgress = ImportProgress(
            id: id,
            fileName: currentImport?.fileName ?? "Unknown",
            phase: phase,
            progress: progress,
            message: message,
            startTime: startTime,
            estimatedTimeRemaining: estimatedRemaining > 0 ? estimatedRemaining : nil
        )
        
        await MainActor.run {
            self.currentImport = importProgress
        }
        
        logger.info("📊 \(phase.rawValue): \(String(format: "%.1f", progress * 100))% - \(message)")
    }
    
    // MARK: - Cleanup and Recovery
    
    private func cleanupFailedImport(at sourceURL: URL, fileName: String) async {
        logger.info("🧹 Cleaning up failed import")
        
        // Remove any partial files
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let importDirectory = documentsURL.appendingPathComponent("ImportedAudio")
        
        // Find and remove partial files
        do {
            let contents = try fileManager.contentsOfDirectory(at: importDirectory, includingPropertiesForKeys: nil)
            for url in contents {
                if url.lastPathComponent.contains(sanitizeFileName(fileName)) {
                    try? fileManager.removeItem(at: url)
                }
            }
        } catch {
            logger.error("Failed to cleanup partial files: \(error)")
        }
    }
    
    private func cleanupPartialImports() async {
        logger.info("🧹 Cleaning up all partial imports")
        
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let importDirectory = documentsURL.appendingPathComponent("ImportedAudio")
        
        // Remove any temporary or incomplete files
        do {
            let contents = try fileManager.contentsOfDirectory(at: importDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour ago
            
            for url in contents {
                let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey])
                if let modDate = attributes.contentModificationDate, modDate < cutoffDate {
                    // Check if file is part of completed import by verifying database entry
                    let isOrphaned = await isFileOrphaned(url)
                    if isOrphaned {
                        try? fileManager.removeItem(at: url)
                        logger.info("🗑 Removed orphaned file: \(url.lastPathComponent)")
                    }
                }
            }
        } catch {
            logger.error("Failed to cleanup partial imports: \(error)")
        }
    }
    
    private func isFileOrphaned(_ url: URL) async -> Bool {
        // Check if any episode references this file
        // This is a simplified check - in a real implementation,
        // you'd query the database for episodes with this audioURL
        return false // Conservative approach - don't delete files we're unsure about
    }
    
    private func setupCleanupTimer() {
        // Periodic cleanup every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task {
                await self?.cleanupPartialImports()
            }
        }
    }
    
    // MARK: - Utility Functions
    
    private func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:*?\"<>|")
        return fileName.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    private func generateUniqueFileName(_ originalURL: URL) throws -> URL {
        let directory = originalURL.deletingLastPathComponent()
        let nameWithoutExtension = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension
        
        for i in 1...999 {
            let newName = "\(nameWithoutExtension) (\(i))"
            let newURL = directory.appendingPathComponent(newName).appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: newURL.path) {
                return newURL
            }
        }
        
        throw BulletproofImportError.fileAccessDenied
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Supporting Types

struct AudioMetadata {
    let duration: TimeInterval
    let fileSize: Int64
}

enum ImportResult {
    case success(Episode)
    case failure(BulletproofImportError)
    
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
    
    var episode: Episode? {
        switch self {
        case .success(let episode): return episode
        case .failure: return nil
        }
    }
    
    var error: BulletproofImportError? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
