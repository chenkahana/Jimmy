import SwiftUI

#if DEBUG
struct BackgroundTaskDebugView: View {
    @ObservedObject private var backgroundTaskManager = BackgroundTaskManager.shared
    @State private var showDetails = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Background Refresh Status") {
                    LabeledContent("Last Refresh") {
                        if let lastRefresh = backgroundTaskManager.lastBackgroundRefresh {
                            Text(lastRefresh.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    LabeledContent("Refresh Count") {
                        Text("\(backgroundTaskManager.backgroundRefreshCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Test Actions") {
                    Button("Schedule Background Refresh") {
                        backgroundTaskManager.scheduleBackgroundRefresh()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Simulate Background Refresh") {
                        backgroundTaskManager.simulateBackgroundRefresh()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                    
                    Button("Force Immediate Refresh") {
                        backgroundTaskManager.performImmediateRefresh()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)
                    
                    Button("Cancel Background Refresh") {
                        backgroundTaskManager.cancelBackgroundRefresh()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Section {
                    DisclosureGroup("How to Test", isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Testing BGTaskScheduler in Simulator:")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("1. Build and run the app")
                                Text("2. Put app in background (Cmd+Shift+H)")
                                Text("3. In Xcode debug bar, click 'Simulate Background App Refresh'")
                                Text("4. Or use: e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@\"com.chenkahana.Jimmy.refresh\"]")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                            
                            Divider()
                            
                            Text("Real Device Testing:")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("1. Enable 'Background App Refresh' in Settings > General")
                                Text("2. Enable it specifically for Jimmy in Settings > Jimmy")
                                Text("3. Put app in background and wait")
                                Text("4. iOS will schedule refresh based on usage patterns")
                            }
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("Testing Instructions")
                }
            }
            .navigationTitle("Background Tasks")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    BackgroundTaskDebugView()
}
#endif 