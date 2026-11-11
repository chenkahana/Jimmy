import Foundation
import Combine
import SwiftUI
import UIKit

/// ViewModel for Subscription management with optimistic delete pattern
/// Implements the exact specification for fixing the "Remove Subscription" bug
@MainActor
class SubscriptionViewModel: ObservableObject {
    static let shared = SubscriptionViewModel()
    
    // MARK: - Published Properties
    @Published var showOrder: [UUID] = []
    @Published var latestDateByShow: [UUID: Date] = [:]
    @Published var episodes: [Episode] = [] // orderedEpisodes list
    @Published var queueEpisodes: [Episode] = []
    @Published var isProcessing: Bool = false
    @Published var toastMessage: String = ""
    @Published var showToast: Bool = false
    
    // MARK: - Private Properties
    private let subscriptionRepository: SubscriptionRepositoryProtocol
    private let episodeRepository: EpisodeRepositoryProtocol
    private let audioPlayerService: AudioPlayerService
    private let queueViewModel: QueueViewModel
    // Shared integration layer for coordinated fetches and persistence.
    private let worldClassIntegration = WorldClassIntegration.shared
    private var cachedEpisodeHeap: EpisodeMergeHeap?
    private var episodesByPodcast: [UUID: [Episode]] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Undo functionality
    private var undoTimer: Timer?
    @Published var pendingDeleteShowID: UUID?
    private var pendingDeleteTask: Task<Void, Never>?
    
    // MARK: - Initialization
    private init(
        subscriptionRepository: SubscriptionRepositoryProtocol = DIContainer.shared.subscriptionRepository,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        audioPlayerService: AudioPlayerService = AudioPlayerService.shared,
        queueViewModel: QueueViewModel = QueueViewModel.shared
    ) {
        self.subscriptionRepository = subscriptionRepository
        self.episodeRepository = episodeRepository
        self.audioPlayerService = audioPlayerService
        self.queueViewModel = queueViewModel
        
        setupBindings()
        loadInitialData()
    }
    
    deinit {
        undoTimer?.invalidate()
        pendingDeleteTask?.cancel()
        cancellables.removeAll()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Listen for subscription changes
        subscriptionRepository.subscriptionChangesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refreshData() }
            }
            .store(in: &cancellables)
        
        // Listen for episode updates
        NotificationCenter.default.publisher(for: .episodeStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let updatedEpisode = notification.object as? Episode else { return }
                self?.updateEpisodeStatus(updatedEpisode)
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        Task {
            await refreshData()
        }
    }
    
    private func refreshData() async {
        // The shared integration layer handles the upstream loading flow.
        
        // Load all episodes
        await loadAllEpisodes()
        
        // Load queue episodes
        await loadQueueEpisodes()
    }
    
    private func loadAllEpisodes() async {
        do {
            let podcasts = try await subscriptionRepository.fetchSubscriptions(ignoreCache: false)
            var allEpisodes: [Episode] = []
            var episodesByShow: [UUID: [Episode]] = [:]
            
            for podcast in podcasts {
                let (episodesWithState, _) = try await episodeRepository.fetchPage(
                    podcastID: podcast.id,
                    cursor: nil,
                    limit: 1000, // Load all episodes
                    ignoreCache: false
                )
                
                let podcastEpisodes = episodesWithState.map { $0.episode }
                episodesByShow[podcast.id] = podcastEpisodes
                allEpisodes.append(contentsOf: podcastEpisodes)
            }
            
            // Sort episodes by publish date (newest first)
            allEpisodes.sort { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
            
            self.episodes = allEpisodes
            self.episodesByPodcast = episodesByShow
            self.cachedEpisodeHeap = EpisodeMergeHeap(episodesByShow: episodesByShow)
            
        } catch {
            // print("❌ SubscriptionViewModel: Failed to load episodes: \(error)")
        }
    }
    
    private func loadQueueEpisodes() async {
        queueEpisodes = queueViewModel.episodes
    }
    
    private func updateEpisodeStatus(_ updatedEpisode: Episode) {
        if let index = episodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
            episodes[index] = updatedEpisode
        }
        
        if let index = queueEpisodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
            queueEpisodes[index] = updatedEpisode
        }
    }
    
    // MARK: - Optimistic Delete Implementation
    
    /// Main unsubscribe method implementing the exact specification
    func unsubscribe(showID: UUID) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        // STEP 1: Immediate UI update (MainActor)
        await performImmediateUIUpdate(showID: showID)
        
        // STEP 2: Background persistence cleanup (off main thread)
        await performBackgroundCleanup(showID: showID)
        
        isProcessing = false
    }
    
    /// STEP 1: Immediate UI update (MainActor) - exactly as specified
    private func performImmediateUIUpdate(showID: UUID) async {
        // 1. Remove showID from the in-memory showOrder array
        showOrder.removeAll { $0 == showID }
        
        // 2. Remove showID from latestDateByShow dictionary
        latestDateByShow.removeValue(forKey: showID)
        
        // 3. Remove every episode of that show from the in-memory episodes heap / orderedEpisodes list
        episodes.removeAll { $0.podcastID == showID }
        
        // 4. Remove episodes from queue
        queueEpisodes.removeAll { $0.podcastID == showID }
        
        // Update episode heap
        episodesByPodcast.removeValue(forKey: showID)
        cachedEpisodeHeap = EpisodeMergeHeap(episodesByShow: episodesByPodcast)
        
        // 5. Re-apply diffable snapshots to all affected lists
        // (This happens automatically via @Published property updates)
        
        // 6. Trigger UIImpactFeedbackGenerator(style: light) and display a toast
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        showToast(message: "Unsubscribed")
        
        // Remove all episodes from this podcast from the queue
        queueViewModel.removeEpisodesFromPodcast(podcastID: showID)
        
        // Handle edge case: if show is currently playing
        if let currentEpisode = audioPlayerService.currentEpisode,
           currentEpisode.podcastID == showID {
            audioPlayerService.stop()
            // Clear Now Playing UI will happen automatically via AudioPlayerService
        }
        
        // Cancel any active feed fetch tasks for this show
        cancelFeedFetchTask(for: showID)
    }
    
    /// STEP 2: Background persistence cleanup (off main thread) - exactly as specified
    private func performBackgroundCleanup(showID: UUID) async {
        // Cancel any existing pending delete
        pendingDeleteTask?.cancel()
        
        // Setup undo functionality
        pendingDeleteShowID = showID
        setupUndoTimer(for: showID)
        
        // Launch a detached Task on a background queue
        pendingDeleteTask = Task.detached(priority: .utility) { [weak self] in
            do {
                // Wait for undo period
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                
                // Check if task was cancelled (undo was triggered)
                try Task.checkCancellation()
                
                // Perform dbQueue.asyncWrite { DELETE FROM shows WHERE id = ? }
                // ON DELETE CASCADE will clear episodes and playback
                try await self?.subscriptionRepository.removeSubscription(id: showID)
                
                // After the delete, flush updated caches to disk
                await self?.flushCachesToDisk()
                
                // Clear pending delete
                await MainActor.run { [weak self] in
                    if self?.pendingDeleteShowID == showID {
                        self?.pendingDeleteShowID = nil
                    }
                }
                
            } catch is CancellationError {
                // Undo was triggered - restore the show
                await self?.rollback(showID: showID)
            } catch {
                // If the delete fails, send rollback
                await self?.rollback(showID: showID)
            }
        }
    }
    
    /// Flush updated caches to disk
    private func flushCachesToDisk() async {
        // WorldClass engine handles all persistence
    }
    
    /// Rollback method for failed deletes
    private func rollback(showID: UUID) async {
        await MainActor.run { [weak self] in
            // Re-insert the show in memory and re-apply snapshots
            Task {
                await self?.refreshData()
                self?.showToast(message: "Failed to unsubscribe. Please try again.")
            }
        }
    }
    
    // MARK: - Undo Functionality
    
    /// Setup undo timer for 3 seconds
    private func setupUndoTimer(for showID: UUID) {
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.pendingDeleteShowID == showID {
                    self?.pendingDeleteShowID = nil
                }
            }
        }
    }
    
    /// Allow an Undo within 3 seconds
    func undoUnsubscribe() async {
        guard let showID = pendingDeleteShowID else { return }
        
        // Cancel the pending delete task
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        
        // Cancel the timer
        undoTimer?.invalidate()
        undoTimer = nil
        
        // Clear pending delete
        pendingDeleteShowID = nil
        
        // Re-insert the show in memory
        await refreshData()
        
        showToast(message: "Unsubscribe cancelled")
    }
    
    // MARK: - Edge Cases
    
    /// Cancel feed fetch task for a show if active
    private func cancelFeedFetchTask(for showID: UUID) {
        // Cancel any active fetch operations for this podcast
        let fetchID = "podcast_\(showID.uuidString)"
        DataFetchCoordinator.shared.cancelFetch(id: fetchID)
    }
    
    // MARK: - Toast Management
    
    private func showToast(message: String) {
        toastMessage = message
        showToast = true
        
        // Auto-hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.showToast = false
        }
    }
    
    // MARK: - Debounced Snapshot Updates
    
    private var snapshotUpdateTimer: Timer?
    private let snapshotDebounceInterval: TimeInterval = 0.1 // 100ms as specified
    
    /// Debounced diffable snapshots to fire at most once every 100ms
    private func scheduleSnapshotUpdate() {
        snapshotUpdateTimer?.invalidate()
        snapshotUpdateTimer = Timer.scheduledTimer(withTimeInterval: snapshotDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
    }
} 
