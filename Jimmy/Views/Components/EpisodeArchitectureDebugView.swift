import SwiftUI

#if DEBUG
/// Debug view for monitoring the enhanced episode architecture
/// Shows repository status, fetch worker queue, and performance metrics
struct EpisodeArchitectureDebugView: View {
    @ObservedObject private var repository = EpisodeRepository.shared
    @ObservedObject private var fetchWorker = EpisodeFetchWorker.shared
    @ObservedObject private var controller = EnhancedEpisodeController.shared
    
    @State private var repositoryStats: (count: Int, lastUpdate: Date?, needsRefresh: Bool) = (0, nil, true)
    @State private var queueStatus: (count: Int, processing: Bool, nextRequest: FetchEpisodesRequest?) = (0, false, nil)
    @State private var refreshTimer: Timer?
    
    var body: some View {
        NavigationView {
            List {
                // Repository Section
                Section("Episode Repository") {
                    LabeledContent("Episodes Count") {
                        Text("\(repository.episodes.count)")
                            .foregroundColor(.primary)
                    }
                    
                    LabeledContent("Loading State") {
                        HStack {
                            if repository.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading")
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Ready")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    LabeledContent("Last Update") {
                        if let lastUpdate = repository.lastUpdateTime {
                            Text(lastUpdate, style: .relative)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    LabeledContent("Cache Status") {
                        HStack {
                            Circle()
                                .fill(repositoryStats.needsRefresh ? .orange : .green)
                                .frame(width: 8, height: 8)
                            Text(repositoryStats.needsRefresh ? "Needs Refresh" : "Fresh")
                                .foregroundColor(repositoryStats.needsRefresh ? .orange : .green)
                        }
                    }
                    
                    if let errorMessage = repository.errorMessage {
                        LabeledContent("Error") {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                
                // Fetch Worker Section
                Section("Fetch Worker") {
                    LabeledContent("Queue Count") {
                        Text("\(fetchWorker.queueCount)")
                            .foregroundColor(.primary)
                    }
                    
                    LabeledContent("Processing State") {
                        HStack {
                            if fetchWorker.isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Processing")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "pause.circle.fill")
                                    .foregroundColor(.gray)
                                Text("Idle")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    LabeledContent("Last Processed") {
                        if let lastProcessed = fetchWorker.lastProcessedTime {
                            Text(lastProcessed, style: .relative)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let nextRequest = queueStatus.nextRequest {
                        LabeledContent("Next Request") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(nextRequest.requestType.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text("Priority: \(nextRequest.priority.rawValue)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Performance Stats Section
                Section("Performance Stats") {
                    LabeledContent("Total Requests") {
                        Text("\(fetchWorker.processingStats.totalRequests)")
                            .foregroundColor(.primary)
                    }
                    
                    LabeledContent("Success Rate") {
                        let successRate = fetchWorker.processingStats.successRate
                        Text("\(Int(successRate * 100))%")
                            .foregroundColor(successRate > 0.8 ? .green : successRate > 0.5 ? .orange : .red)
                    }
                    
                    LabeledContent("Avg Processing Time") {
                        Text(String(format: "%.2fs", fetchWorker.processingStats.averageProcessingTime))
                            .foregroundColor(.secondary)
                    }
                    
                    LabeledContent("Failed Requests") {
                        Text("\(fetchWorker.processingStats.failedRequests)")
                            .foregroundColor(fetchWorker.processingStats.failedRequests > 0 ? .red : .green)
                    }
                }
                
                // Enhanced Controller Section
                Section("Enhanced Controller") {
                    LabeledContent("Cache Status") {
                        HStack {
                            Circle()
                                .fill(cacheStatusColor)
                                .frame(width: 8, height: 8)
                            Text(controller.cacheStatus.displayText)
                                .foregroundColor(cacheStatusColor)
                        }
                    }
                    
                    LabeledContent("Episodes Count") {
                        Text("\(controller.episodeCount)")
                            .foregroundColor(.primary)
                    }
                    
                    LabeledContent("Loading State") {
                        HStack {
                            if controller.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading")
                                    .foregroundColor(.orange)
                            } else if controller.isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Refreshing")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Ready")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    if let errorMessage = controller.errorMessage {
                        LabeledContent("Error") {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                
                // Actions Section
                Section("Actions") {
                    Button("Refresh Episodes") {
                        Task {
                            await controller.refreshEpisodes()
                        }
                    }
                    .disabled(controller.isRefreshing)
                    
                    Button("Process Queue Immediately") {
                        Task {
                            await fetchWorker.processImmediately()
                        }
                    }
                    .disabled(fetchWorker.isProcessing)
                    
                    Button("Clear Queue") {
                        Task {
                            await fetchWorker.clearQueue()
                        }
                    }
                    .disabled(fetchWorker.queueCount == 0)
                    
                    Button("Reset Performance Stats") {
                        Task {
                            await fetchWorker.resetProcessingStats()
                        }
                    }
                    
                    Button("Clear Repository") {
                        Task {
                            try? await repository.clearAllEpisodes()
                        }
                    }
                    .foregroundColor(.red)
                }
                
                // Debug Info Section
                Section("Debug Info") {
                    DisclosureGroup("Controller Debug Info") {
                        Text(controller.getDebugInfo())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    DisclosureGroup("Queue Status Details") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Queue Count: \(queueStatus.count)")
                            Text("Processing: \(queueStatus.processing)")
                            if let nextRequest = queueStatus.nextRequest {
                                Text("Next Request Type: \(nextRequest.requestType.rawValue)")
                                Text("Next Request Priority: \(nextRequest.priority.rawValue)")
                                Text("Next Request Age: \(Int(Date().timeIntervalSince(nextRequest.timestamp)))s")
                            } else {
                                Text("No queued requests")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Episode Architecture")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                startRefreshTimer()
                updateStats()
            }
            .onDisappear {
                stopRefreshTimer()
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var cacheStatusColor: Color {
        switch controller.cacheStatus {
        case .fresh:
            return .green
        case .stale:
            return .orange
        case .error:
            return .red
        case .loading:
            return .blue
        case .loaded:
            return .green
        }
    }
    
    // MARK: - Helper Methods
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            updateStats()
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func updateStats() {
        Task {
            let stats = await repository.getCacheStats()
            let queue = fetchWorker.getQueueStatus()
            
            await MainActor.run {
                repositoryStats = (
                    count: stats.count,
                    lastUpdate: stats.lastUpdated,
                    needsRefresh: stats.needsRefresh
                )
                queueStatus = queue
            }
        }
    }
}

// MARK: - Preview

struct EpisodeArchitectureDebugView_Previews: PreviewProvider {
    static var previews: some View {
        EpisodeArchitectureDebugView()
    }
}
#endif 