import SwiftUI

struct StorageDebugView: View {
    @State private var userDefaultsStats: (totalKeys: Int, estimatedSize: Int, largeKeys: [(String, Int)]) = (0, 0, [])
    @State private var fileStorageSize: String = "0 bytes"
    
    var body: some View {
        NavigationView {
            List {
                Section("UserDefaults") {
                    HStack {
                        Text("Total Keys")
                        Spacer()
                        Text("\(userDefaultsStats.totalKeys)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Estimated Size")
                        Spacer()
                        Text(formatBytes(userDefaultsStats.estimatedSize))
                            .foregroundColor(.secondary)
                    }
                    
                    let limit = 4 * 1024 * 1024 // 4MB
                    let percentage = Double(userDefaultsStats.estimatedSize) / Double(limit) * 100
                    
                    HStack {
                        Text("Usage (4MB limit)")
                        Spacer()
                        Text("\(Int(percentage))%")
                            .foregroundColor(percentage > 75 ? .red : percentage > 50 ? .orange : .green)
                    }
                    
                    ProgressView(value: Double(userDefaultsStats.estimatedSize), total: Double(limit))
                        .tint(percentage > 75 ? .red : percentage > 50 ? .orange : .green)
                    
                    if !userDefaultsStats.largeKeys.isEmpty {
                        Text("Large Keys (>1MB)")
                            .font(.headline)
                            .padding(.top)
                        
                        ForEach(userDefaultsStats.largeKeys, id: \.0) { key, size in
                            HStack {
                                Text(key)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(formatBytes(size))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                Section("File Storage") {
                    HStack {
                        Text("Total Size")
                        Spacer()
                        Text(fileStorageSize)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Refresh Statistics") {
                        loadStats()
                    }
                }
                
                Section("Actions") {
                    Button("Perform Cleanup") {
                        UserDefaultsCleanup.shared.performCleanup()
                        loadStats()
                    }
                    
                    Button("Print Detailed Stats") {
                        UserDefaultsCleanup.shared.printUsageStats()
                    }
                }
            }
            .navigationTitle("Storage Debug")
            .onAppear {
                loadStats()
            }
        }
    }
    
    private func loadStats() {
        userDefaultsStats = UserDefaultsCleanup.shared.getUsageStats()
        fileStorageSize = FileStorage.shared.getFormattedStorageSize()
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    StorageDebugView()
} 