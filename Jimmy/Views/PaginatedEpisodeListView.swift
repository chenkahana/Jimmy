import SwiftUI

/// A view that displays a paginated list of episodes for a given podcast.
///
/// This view uses the `ShowEpisodesViewModel` to fetch and manage the episode data.
/// It displays a list of episodes and provides UI for loading, searching, sorting,
/// and filtering. It also handles pagination automatically as the user scrolls.
struct PaginatedEpisodeListView: View {
    
    @StateObject private var viewModel: ShowEpisodesViewModel
    
    init(podcast: Podcast) {
        _viewModel = StateObject(wrappedValue: ShowEpisodesViewModel(podcast: podcast))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            CompactEpisodeHeaderView(viewModel: viewModel)
            ZStack {
                if viewModel.isLoading && viewModel.displayedEpisodes.isEmpty {
                    skeletonList
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(message: errorMessage) {
                        Task { await viewModel.loadFirstPage() }
                    }
                } else if viewModel.displayedEpisodes.isEmpty {
                    EmptyStateView(message: "No episodes found for the selected filters.")
                } else {
                    episodeList
                }
            }
        }
        .navigationTitle(viewModel.podcast.title)
        .task {
            if viewModel.displayedEpisodes.isEmpty {
                await viewModel.loadFirstPage()
            }
        }
    }
    
    private var episodeList: some View {
        List {
            ForEach(viewModel.displayedEpisodes) { episode in
                NavigationLink(destination: EpisodeDetailView(
                    episode: episode,
                    podcast: viewModel.podcast
                )) {
                    EpisodeRowView(episode: episode, podcast: viewModel.podcast)
                }
                .onAppear { viewModel.checkForLoadMore(episode: episode) }
            }
            if viewModel.isLoading && !viewModel.displayedEpisodes.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
    
    private var skeletonList: some View {
        List {
            ForEach(0..<10) { _ in
                EpisodeRowView(episode: Episode(
                    id: UUID(),
                    title: "Loading Episode...",
                    artworkURL: nil,
                    audioURL: nil,
                    description: "Loading episode description...",
                    played: false,
                    podcastID: UUID(),
                    publishedDate: Date(),
                    localFileURL: nil,
                    playbackPosition: 0,
                    duration: 0
                ), podcast: viewModel.podcast).redacted(reason: .placeholder)
            }
        }
        .listStyle(.plain)
        .disabled(true)
    }
}

// MARK: - Header View for Controls
private struct CompactEpisodeHeaderView: View {
    @ObservedObject var viewModel: ShowEpisodesViewModel
    @State private var showingFilters = false
    
    var body: some View {
        HStack {
            // Episode count and status
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.displayedEpisodes.count) episodes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !viewModel.searchText.isEmpty || viewModel.filterType != .all || viewModel.sortOrder != .newestFirst {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                        Text("Filtered")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            Spacer()
            
            // Menu button
            Menu {
                Section("Search") {
                    Button(action: { showingFilters = true }) {
                        Label("Search & Filter", systemImage: "magnifyingglass")
                    }
                }
                
                Section("Quick Filters") {
                    ForEach(ShowEpisodesViewModel.EpisodeFilter.allCases) { filter in
                        Button(action: { viewModel.filterType = filter }) {
                            HStack {
                                Text(filter.rawValue)
                                if viewModel.filterType == filter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Section("Sort Order") {
                    ForEach(ShowEpisodesViewModel.EpisodeSortOrder.allCases) { sortOrder in
                        Button(action: { viewModel.sortOrder = sortOrder }) {
                            HStack {
                                Text(sortOrder.rawValue)
                                if viewModel.sortOrder == sortOrder {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button("Clear All Filters", role: .destructive) {
                        viewModel.searchText = ""
                        viewModel.filterType = .all
                        viewModel.sortOrder = .newestFirst
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingFilters) {
            EpisodeFilterSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Filter Sheet
private struct EpisodeFilterSheet: View {
    @ObservedObject var viewModel: ShowEpisodesViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Search Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search episodes...", text: $viewModel.searchText)
                        if !viewModel.searchText.isEmpty {
                            Button(action: { viewModel.searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                // Filter Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filter")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Picker("Filter", selection: $viewModel.filterType) {
                        ForEach(ShowEpisodesViewModel.EpisodeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Sort Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sort Order")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Picker("Sort", selection: $viewModel.sortOrder) {
                        ForEach(ShowEpisodesViewModel.EpisodeSortOrder.allCases) { sortOrder in
                            Text(sortOrder.rawValue).tag(sortOrder)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Spacer()
                
                // Clear All Button
                Button("Clear All Filters") {
                    viewModel.searchText = ""
                    viewModel.filterType = .all
                    viewModel.sortOrder = .newestFirst
                }
                .foregroundColor(.red)
                .padding()
            }
            .padding()
            .navigationTitle("Search & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Reusable UI Components
private struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.red)
            Text(message).multilineTextAlignment(.center)
            Button("Retry", action: retryAction)
        }
        .padding()
    }
}

private struct EmptyStateView: View {
    let message: String
    var body: some View { Text(message).foregroundColor(.secondary) }
}

struct PaginatedEpisodeListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PaginatedEpisodeListView(podcast: .mock)
        }
    }
}

extension Podcast {
    static var mock: Podcast {
        Podcast(
            id: UUID(),
            title: "The Daily",
            author: "The New York Times",
            description: "This is what the news should sound like. The biggest stories of our time, told by the best journalists in the world. Hosted by Michael Barbaro and Sabrina Tavernise. Twenty minutes a day, five days a week, ready by 6 a.m.",
            feedURL: URL(string: "https://feeds.simplecast.com/54nAGcIl")!,
            artworkURL: URL(string: "https://source.unsplash.com/random/200x200?newspaper")
        )
    }
}

