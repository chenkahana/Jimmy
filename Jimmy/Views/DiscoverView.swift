import SwiftUI

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoveryViewModel.shared
    @Environment(ShellStore.self) private var shell
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var discoverNamespace
    @State private var selectedDestination: DiscoverNavigationDestination?
    @State private var detailOpenToken: InteractionLatencyTracker.Token?
    /// The last few submitted queries, newest first, one per line.
    @AppStorage("discoverRecentSearches") private var recentSearchesStorage = ""
    /// The query the last finished search ran, so "No Results" never shows for text still being typed.
    @State private var completedQuery: String?

    private var query: String {
        shell.discoverSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        content
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: Binding(
                    get: { shell.discoverSearchQuery },
                    set: { newValue in
                        shell.updateDiscoverSearch(query: newValue)
                        viewModel.searchText = newValue
                    }
                ),
                isPresented: Binding(
                    get: { shell.isDiscoverSearchFocused },
                    set: { newValue in
                        shell.setDiscoverSearchFocused(newValue)
                        isSearchFieldFocused = newValue
                    }
                ),
                prompt: "Shows"
            )
            .onSubmit(of: .search) {
                rememberSearch(query)
            }
            .focused($isSearchFieldFocused)
            .onChange(of: shell.discoverSearchQuery) { _, newQuery in
                if viewModel.searchText != newQuery {
                    viewModel.searchText = newQuery
                }
            }
            .onChange(of: viewModel.isSearching) { _, isSearching in
                if !isSearching {
                    completedQuery = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .onChange(of: shell.isDiscoverSearchFocused) { _, newValue in
                isSearchFieldFocused = newValue
            }
            .onAppear {
                if viewModel.searchText != shell.discoverSearchQuery {
                    viewModel.searchText = shell.discoverSearchQuery
                }
            }
            .task {
                await viewModel.loadDataIfNeeded()
            }
            // The checkmark confirms a subscribe; only a failure interrupts.
            .alert("Couldn’t Subscribe", isPresented: Binding(
                get: { viewModel.showingSubscriptionAlert && viewModel.subscriptionError != nil },
                set: { viewModel.showingSubscriptionAlert = $0 }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.subscriptionMessage)
            }
            .navigationDestination(item: $selectedDestination) { destination in
                switch destination {
                case .podcast(let result, let sourceID):
                    AsyncPodcastDetailView(searchResult: result)
                        .navigationTransition(.zoom(sourceID: sourceID, in: discoverNamespace))
                        .task {
                            finishDetailOpenMeasurement()
                        }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !query.isEmpty {
            searchResults
        } else if viewModel.errorMessage != nil, !viewModel.hasAnyData, !viewModel.isLoading {
            ContentUnavailableView {
                Label("Couldn’t Load Top Shows", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.refreshData() }
                }
                .buttonStyle(.glassProminent)
            }
        } else {
            landing
        }
    }

    // MARK: - Landing

    private var landing: some View {
        List {
            if !recentSearches.isEmpty {
                Section {
                    ForEach(recentSearches, id: \.self) { recent in
                        Button(recent) {
                            runSearch(recent)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        var searches = recentSearches
                        searches.remove(atOffsets: offsets)
                        recentSearchesStorage = searches.joined(separator: "\n")
                    }
                } header: {
                    HStack {
                        Text("Recent Searches")
                        Spacer()
                        Button("Clear") {
                            recentSearchesStorage = ""
                        }
                        .font(.body)
                        .accessibilityLabel("Clear Recent Searches")
                    }
                }
            }

            Section("Top Shows") {
                if viewModel.charts.isEmpty {
                    ForEach(1...8, id: \.self) { rank in
                        DiscoverTopShowRow(
                            index: rank,
                            result: .placeholder(id: rank),
                            isSubscribed: false,
                            onSubscribe: {}
                        )
                        .redacted(reason: .placeholder)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading")
                    }
                } else {
                    ForEach(Array(viewModel.charts.enumerated()), id: \.element.id) { index, result in
                        Button {
                            openPodcast(result, sourceID: "discover-charts-\(result.id)")
                        } label: {
                            DiscoverTopShowRow(
                                index: index + 1,
                                result: result,
                                isSubscribed: viewModel.isSubscribed(result),
                                onSubscribe: {
                                    Task { await viewModel.subscribe(to: result) }
                                }
                            )
                            .matchedTransitionSource(id: "discover-charts-\(result.id)", in: discoverNamespace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityActions {
                            if !viewModel.isSubscribed(result) {
                                Button("Subscribe") { Task { await viewModel.subscribe(to: result) } }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .headerProminence(.increased)
        .refreshable {
            await viewModel.refreshData()
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.searchResults.isEmpty && !viewModel.isSearching && completedQuery == query {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if viewModel.searchResults.isEmpty {
                    ForEach(1...8, id: \.self) { id in
                        DiscoverSearchResultRow(
                            result: .placeholder(id: id),
                            isSubscribed: false,
                            isProcessing: false,
                            onSubscribe: {}
                        )
                        .redacted(reason: .placeholder)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Searching")
                    }
                } else {
                    ForEach(viewModel.searchResults) { result in
                        Button {
                            rememberSearch(query)
                            openPodcast(result, sourceID: "discover-search-\(result.id)")
                        } label: {
                            DiscoverSearchResultRow(
                                result: result,
                                isSubscribed: viewModel.isSubscribed(result),
                                isProcessing: viewModel.isProcessing(result),
                                onSubscribe: {
                                    Task { await viewModel.subscribe(to: result) }
                                }
                            )
                            .matchedTransitionSource(id: "discover-search-\(result.id)", in: discoverNamespace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityActions {
                            if !viewModel.isSubscribed(result) {
                                Button("Subscribe") { Task { await viewModel.subscribe(to: result) } }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

#Preview {
    NavigationStack {
        DiscoverView()
    }
    .environment(ShellStore.shared)
}

// MARK: - Recent Searches

extension DiscoverView {
    private static let recentSearchLimit = 8

    private var recentSearches: [String] {
        recentSearchesStorage.split(separator: "\n").map(String.init)
    }

    private func rememberSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var searches = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        searches.insert(trimmed, at: 0)
        recentSearchesStorage = searches.prefix(Self.recentSearchLimit).joined(separator: "\n")
    }

    private func runSearch(_ query: String) {
        shell.updateDiscoverSearch(query: query)
        viewModel.searchText = query
        rememberSearch(query)
    }
}

// MARK: - Navigation

extension DiscoverView {
    private func openPodcast(_ result: PodcastSearchResult, sourceID: String) {
        detailOpenToken = InteractionLatencyTracker.shared.begin(.podcastDetailOpen, detail: result.title)
        selectedDestination = .podcast(result: result, sourceID: sourceID)
    }

    private func finishDetailOpenMeasurement() {
        guard let detailOpenToken else {
            return
        }

        InteractionLatencyTracker.shared.end(detailOpenToken)
        self.detailOpenToken = nil
    }
}

private enum DiscoverNavigationDestination: Identifiable, Hashable {
    case podcast(result: PodcastSearchResult, sourceID: String)

    var id: String {
        switch self {
        case .podcast(let result, let sourceID):
            return "podcast-\(result.id)-\(sourceID)"
        }
    }

    static func == (lhs: DiscoverNavigationDestination, rhs: DiscoverNavigationDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension PodcastSearchResult {
    /// Stand-in text of a realistic length for `redacted(reason: .placeholder)` rows while loading.
    static func placeholder(id: Int) -> PodcastSearchResult {
        PodcastSearchResult(
            id: -id,
            title: "Podcast title",
            author: "Author name",
            feedURL: URL(fileURLWithPath: "/"),
            artworkURL: nil,
            description: nil,
            genre: "Genre",
            trackCount: 0
        )
    }
}
