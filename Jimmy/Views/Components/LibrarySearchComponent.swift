import SwiftUI

/// Reusable search component following the Background Data Synchronization Plan
/// Provides consistent search functionality across Library and other views
struct LibrarySearchComponent: View {
    @Binding var searchText: String
    let placeholder: String
    let isActive: Bool
    let onSearchFocusChange: (Bool) -> Void
    let onClearSearch: () -> Void
    
    @FocusState private var isSearchFocused: Bool
    
    init(
        searchText: Binding<String>,
        placeholder: String = "Search...",
        isActive: Bool = false,
        onSearchFocusChange: @escaping (Bool) -> Void = { _ in },
        onClearSearch: @escaping () -> Void = { }
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.isActive = isActive
        self.onSearchFocusChange = onSearchFocusChange
        self.onClearSearch = onClearSearch
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Search Icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
            
            // Search Text Field
            TextField(placeholder, text: $searchText)
                .focused($isSearchFocused)
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()
                .onSubmit {
                    isSearchFocused = false
                }
                .onChange(of: isSearchFocused) { focused in
                    onSearchFocusChange(focused)
                }
            
            // Clear Button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    onClearSearch()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSearchFocused ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
}

/// Advanced search component with filters and suggestions
struct AdvancedSearchComponent: View {
    @Binding var searchText: String
    @Binding var selectedFilters: Set<SearchFilter>
    let availableFilters: [SearchFilter]
    let suggestions: [String]
    let onFilterChange: (Set<SearchFilter>) -> Void
    let onSuggestionTap: (String) -> Void
    
    @State private var showingFilters = false
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Main Search Bar
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    
                    TextField("Search episodes, podcasts...", text: $searchText)
                        .focused($isSearchFocused)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocorrectionDisabled()
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSearchFocused ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                
                // Filter Button
                Button(action: {
                    showingFilters.toggle()
                }) {
                    Image(systemName: selectedFilters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(selectedFilters.isEmpty ? .secondary : .accentColor)
                        .font(.system(size: 20))
                }
            }
            
            // Active Filters
            if !selectedFilters.isEmpty {
                activeFiltersView
            }
            
            // Search Suggestions
            if isSearchFocused && !suggestions.isEmpty && searchText.isEmpty {
                searchSuggestionsView
            }
            
            // Filter Options
            if showingFilters {
                filterOptionsView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingFilters)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
    
    // MARK: - Active Filters View
    
    private var activeFiltersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedFilters), id: \.self) { filter in
                    FilterChip(
                        filter: filter,
                        isSelected: true,
                        onTap: {
                            var newFilters = selectedFilters
                            newFilters.remove(filter)
                            selectedFilters = newFilters
                            onFilterChange(newFilters)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Search Suggestions View
    
    private var searchSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Searches")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            
            LazyVStack(spacing: 4) {
                ForEach(suggestions, id: \.self) { suggestion in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                        
                        Text(suggestion)
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSuggestionTap(suggestion)
                        isSearchFocused = false
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Filter Options View
    
    private var filterOptionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter by")
                .font(.headline)
                .padding(.horizontal, 16)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120), spacing: 8)
            ], spacing: 8) {
                ForEach(availableFilters, id: \.self) { filter in
                    FilterChip(
                        filter: filter,
                        isSelected: selectedFilters.contains(filter),
                        onTap: {
                            var newFilters = selectedFilters
                            if newFilters.contains(filter) {
                                newFilters.remove(filter)
                            } else {
                                newFilters.insert(filter)
                            }
                            selectedFilters = newFilters
                            onFilterChange(newFilters)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Filter Chip Component

struct FilterChip: View {
    let filter: SearchFilter
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(filter.displayName)
                .font(.caption)
                .fontWeight(.medium)
            
            if isSelected {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.accentColor : Color(.systemGray5))
        )
        .foregroundColor(isSelected ? .white : .primary)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Search Filter Enum

enum SearchFilter: String, CaseIterable, Hashable {
    case episodes = "episodes"
    case podcasts = "podcasts"
    case played = "played"
    case unplayed = "unplayed"
    case downloaded = "downloaded"
    case recent = "recent"
    
    var displayName: String {
        switch self {
        case .episodes: return "Episodes"
        case .podcasts: return "Podcasts"
        case .played: return "Played"
        case .unplayed: return "Unplayed"
        case .downloaded: return "Downloaded"
        case .recent: return "Recent"
        }
    }
    
    var icon: String {
        switch self {
        case .episodes: return "waveform.circle"
        case .podcasts: return "mic.circle"
        case .played: return "checkmark.circle"
        case .unplayed: return "circle"
        case .downloaded: return "arrow.down.circle"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Preview

struct LibrarySearchComponent_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LibrarySearchComponent(
                searchText: .constant(""),
                placeholder: "Search library..."
            )
            
            AdvancedSearchComponent(
                searchText: .constant(""),
                selectedFilters: .constant([]),
                availableFilters: SearchFilter.allCases,
                suggestions: ["Recent search 1", "Recent search 2"],
                onFilterChange: { _ in },
                onSuggestionTap: { _ in }
            )
        }
        .padding()
    }
} 