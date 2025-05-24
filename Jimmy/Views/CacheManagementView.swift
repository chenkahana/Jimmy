import SwiftUI

struct CacheManagementView: View {
    @ObservedObject private var episodeCacheService = EpisodeCacheService.shared
    @State private var cacheStats: (totalPodcasts: Int, freshEntries: Int, expiredEntries: Int, totalSizeKB: Double) = (0, 0, 0, 0.0)
    @State private var showingClearConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Cache Statistics") {
                    HStack {
                        Label("Total Cached Podcasts", systemImage: "folder")
                        Spacer()
                        Text("\(cacheStats.totalPodcasts)")
                            .foregroundColor(.secondary)
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
                        refreshStats()
                    }) {
                        Label("Refresh Statistics", systemImage: "arrow.clockwise")
                    }
                    
                    Button(action: {
                        showingClearConfirmation = true
                    }) {
                        Label("Clear All Cache", systemImage: "trash")
                            .foregroundColor(.red)
                    }
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
            .onAppear {
                refreshStats()
            }
            .alert("Clear Cache", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearAllCache()
                }
            } message: {
                Text("This will clear all cached episodes. They will be re-downloaded when you next visit podcast detail screens.")
            }
        }
    }
    
    private func refreshStats() {
        cacheStats = episodeCacheService.getCacheStats()
    }
    
    private func clearAllCache() {
        episodeCacheService.clearAllCache()
        refreshStats()
    }
}

#Preview {
    CacheManagementView()
} 