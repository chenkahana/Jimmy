import SwiftUI

/// Accessible search bar component with proper keyboard navigation and VoiceOver support
struct AccessibleSearchBar: View {
    @Binding var searchText: String
    let placeholder: String
    let onSearchCommit: (() -> Void)?
    let onCancel: (() -> Void)?
    
    @FocusState private var isSearchFocused: Bool
    @StateObject private var accessibilityService = AccessibilityService.shared
    
    init(
        searchText: Binding<String>,
        placeholder: String = "Search",
        onSearchCommit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.onSearchCommit = onSearchCommit
        self.onCancel = onCancel
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        onSearchCommit?()
                        accessibilityService.announce("Search performed")
                    }
                    .accessibilityLabel("Search field")
                    .accessibilityHint("Enter text to search for podcasts or episodes")
                    .accessibilityValue(searchText.isEmpty ? "Empty" : searchText)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        accessibilityService.announce("Search cleared")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                    .accessibilityHint("Clears the current search text")
                    .minimumTouchTarget()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            
            // Cancel button (appears when focused)
            if isSearchFocused {
                Button("Cancel") {
                    searchText = ""
                    isSearchFocused = false
                    onCancel?()
                    accessibilityService.announce("Search cancelled")
                }
                .font(.system(.body, weight: .medium))
                .foregroundColor(.accentColor)
                .accessibilityLabel("Cancel search")
                .accessibilityHint("Cancels the current search and dismisses keyboard")
                .minimumTouchTarget()
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .contain)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
}

#Preview {
    VStack(spacing: 20) {
        AccessibleSearchBar(
            searchText: .constant(""),
            placeholder: "Search podcasts"
        )
        
        AccessibleSearchBar(
            searchText: .constant("Sample search"),
            placeholder: "Search episodes"
        )
    }
    .padding()
}