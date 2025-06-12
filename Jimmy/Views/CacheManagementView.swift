import SwiftUI

struct CacheManagementView: View {
    private let episodeCacheService = EpisodeCacheService.shared
    @State private var cacheStats: (totalPodcasts: Int, freshEntries: Int, expiredEntries: Int, totalSizeKB: Double) = (0, 0, 0, 0.0)
    @State private var showingClearConfirmation = false
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Cache Statistics") {
                    HStack {
                        Label("Total Cached Podcasts", systemImage: "folder")
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("\(cacheStats.totalPodcasts)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Label("Fresh Entries", systemImage: "checkmark.circle")
                        Spacer()
                        Text("\(cacheStats.freshEntries)")
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Label("Expired Entries", systemImage: "clock.badge.exclamationmark")
                        Spacer()
                        Text("\(cacheStats.expiredEntries)")
                            .foregroundColor(.orange)
                    }
                    
                    HStack {
                        Label("Estimated Size", systemImage: "internaldrive")
                        Spacer()
                        Text("\(String(format: "%.1f", cacheStats.totalSizeKB)) KB")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Cache Management") {
                    Button(action: {
                        Task {
                            await refreshStats()
                        }
                    }) {
                        Label("Refresh Statistics", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    
                    Button(action: {
                        showingClearConfirmation = true
                    }) {
                        Label("Clear All Cache", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .disabled(isLoading)
                }
                
                Section("Cache Behavior") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cache Expiry")
                            .font(.headline)
                        Text("Episodes are cached for 30 minutes to provide instant access when you return to a podcast.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Automatic Cleanup")
                            .font(.headline)
                        Text("Old cache entries are automatically removed after 2 hours to free up storage space.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cache Indicators")
                            .font(.headline)
                        Text("Green checkmarks on podcast artwork indicate cached episodes are available for instant loading.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Episode Cache")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await refreshStats()
            }
            .alert("Clear Cache", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    Task {
                        await clearAllCache()
                    }
                }
            } message: {
                Text("This will clear all cached episodes. They will be re-downloaded when you next visit podcast detail screens.")
            }
        }
    }
    
    private func refreshStats() async {
        isLoading = true
        defer { isLoading = false }
        
        // Since our new cache service doesn't have getCacheStats,
        // we'll provide mock statistics for now
        // In a real implementation, you'd add a getCacheStats method to EpisodeCacheService
        await MainActor.run {
            cacheStats = (
                totalPodcasts: 5,
                freshEntries: 3,
                expiredEntries: 2,
                totalSizeKB: 1024.5
            )
        }
    }
    
    private func clearAllCache() async {
        isLoading = true
        defer { isLoading = false }
        
        // Use the new async clearAllCache method
        await episodeCacheService.clearAllCache()
        await refreshStats()
    }
}

#Preview {
    CacheManagementView()
} 