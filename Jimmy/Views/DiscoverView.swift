import SwiftUI

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoveryViewModel.shared
    @Environment(ShellStore.self) private var shell
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var discoverNamespace
    @State private var selectedDestination: DiscoverNavigationDestination?
    @State private var detailOpenToken: InteractionLatencyTracker.Token?
    /// `RecentSearches.storage`: the last few submitted queries, newest first, one per line.
    @AppStorage("discoverRecentSearches") private var recentSearchesStorage = ""

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
                placement: .navigationBarDrawer(displayMode: .always),
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
                get: { viewModel.subscribeFailure != nil },
                set: { if !$0 { viewModel.subscribeFailure = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.subscribeFailure ?? "")
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
        } else if viewModel.charts.isEmpty && !viewModel.isLoading {
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
        let subscribedFeedURLs = viewModel.subscribedFeedURLs()
        return List {
            if !recentSearches.queries.isEmpty {
                Section {
                    ForEach(recentSearches.queries, id: \.self) { recent in
                        Button(recent) {
                            runSearch(recent)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        updateRecentSearches { $0.remove(atOffsets: offsets) }
                    }
                } header: {
                    recentSearchesHeader
                }
            }

            Section("Top Shows") {
                if viewModel.charts.isEmpty {
                    // Reached only while loading; an empty chart that isn't loading shows the error instead.
                    ForEach(1...8, id: \.self) { rank in
                        DiscoverTopShowRow(
                            index: rank,
                            result: .placeholder(id: rank),
                            isSubscribed: false,
                            isProcessing: false,
                            onSubscribe: {}
                        )
                        .redacted(reason: .placeholder)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading Top Shows")
                        .accessibilityHidden(rank != 1)
                    }
                } else {
                    ForEach(Array(viewModel.charts.enumerated()), id: \.element.id) { index, result in
                        let isSubscribed = subscribedFeedURLs.contains(result.feedURL)
                        Button {
                            openPodcast(result, sourceID: "discover-charts-\(result.id)")
                        } label: {
                            DiscoverTopShowRow(
                                index: index + 1,
                                result: result,
                                isSubscribed: isSubscribed,
                                isProcessing: viewModel.isProcessing(result),
                                onSubscribe: {
                                    Task { await viewModel.subscribe(to: result) }
                                }
                            )
                            .matchedTransitionSource(id: "discover-charts-\(result.id)", in: discoverNamespace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityActions {
                            if !isSubscribed {
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

    private var recentSearchesHeader: some View {
        let clear = Button("Clear") {
            updateRecentSearches { $0.clear() }
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Clear Recent Searches")

        // Side by side when it fits; at large text sizes Clear moves under the title instead of truncating it.
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text("Recent Searches")
                Spacer()
                clear
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent Searches")
                clear
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResults: some View {
        let hasFinished = !viewModel.isSearching && viewModel.lastCompletedQuery == query
        let subscribedFeedURLs = viewModel.subscribedFeedURLs()
        if hasFinished, viewModel.searchErrorMessage != nil {
            ContentUnavailableView {
                Label("Couldn’t Search", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.searchPodcasts() }
                }
                .buttonStyle(.glassProminent)
            }
        } else if hasFinished, viewModel.searchResults.isEmpty {
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
                        .accessibilityHidden(id != 1)
                    }
                } else {
                    ForEach(viewModel.searchResults) { result in
                        let isSubscribed = subscribedFeedURLs.contains(result.feedURL)
                        Button {
                            rememberSearch(query)
                            openPodcast(result, sourceID: "discover-search-\(result.id)")
                        } label: {
                            DiscoverSearchResultRow(
                                result: result,
                                isSubscribed: isSubscribed,
                                isProcessing: viewModel.isProcessing(result),
                                onSubscribe: {
                                    Task { await viewModel.subscribe(to: result) }
                                }
                            )
                            .matchedTransitionSource(id: "discover-search-\(result.id)", in: discoverNamespace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityActions {
                            if !isSubscribed {
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
    private var recentSearches: RecentSearches {
        RecentSearches(storage: recentSearchesStorage)
    }

    private func updateRecentSearches(_ change: (inout RecentSearches) -> Void) {
        var searches = recentSearches
        change(&searches)
        recentSearchesStorage = searches.storage
    }

    private func rememberSearch(_ query: String) {
        updateRecentSearches { $0.add(query) }
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
