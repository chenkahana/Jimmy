import SwiftUI

struct FileImportNamingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fileName: String
    @State private var showName: String = ""
    @State private var selectedShowID: UUID?
    @State private var isCreatingNewShow: Bool = false
    @State private var localShows: [Podcast] = []
    private let podcastService = PodcastService.shared
    
    let audioURL: URL
    let onImport: (String, String, UUID?) -> Void // filename, showname, existing show ID
    
    init(audioURL: URL, onImport: @escaping (String, String, UUID?) -> Void) {
        self.audioURL = audioURL
        self.onImport = onImport
        self._fileName = State(initialValue: audioURL.deletingPathExtension().lastPathComponent)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Audio File Name") {
                    TextField("Enter file name", text: $fileName)
                        .textInputAutocapitalization(.words)
                }
                
                Section("Show/Folder") {
                    Toggle("Create new show", isOn: $isCreatingNewShow)
                    
                    if isCreatingNewShow {
                        TextField("New show name", text: $showName)
                            .textInputAutocapitalization(.words)
                    } else {
                        if localShows.isEmpty {
                            Text("No local shows available. Toggle to create a new one.")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            Picker("Select show", selection: $selectedShowID) {
                                Text("Select a show").tag(nil as UUID?)
                                ForEach(localShows) { show in
                                    Text(show.title).tag(show.id as UUID?)
                                }
                            }
                        }
                    }
                }
                
                Section("Episode Details") {
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
                }
            }
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadLocalShows()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        handleImport()
                    }
                    .disabled(!canImport)
                }
            }
        }
    }
    
    private var canImport: Bool {
        !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isCreatingNewShow ? !showName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selectedShowID != nil)
    }
    
    private var selectedShow: Podcast? {
        guard let showID = selectedShowID else { return nil }
        return localShows.first { $0.id == showID }
    }
    
    private func loadLocalShows() {
        localShows = podcastService.loadPodcasts().filter { $0.feedURL.scheme == "local" }
    }
    
    private func handleImport() {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShowName = showName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if isCreatingNewShow {
            onImport(trimmedFileName, trimmedShowName, nil)
        } else {
            if let showID = selectedShowID,
               let show = localShows.first(where: { $0.id == showID }) {
                onImport(trimmedFileName, show.title, showID)
            }
        }
        
        dismiss()
    }
}

struct FileImportNamingView_Previews: PreviewProvider {
    static var previews: some View {
        FileImportNamingView(audioURL: URL(string: "file:///test.mp3")!) { _, _, _ in }
    }
} 