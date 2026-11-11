import SwiftUI
import JimmyKit

/// Auto-scrolling transcript view with search and tap-to-seek
struct TranscriptView: View {
    @ObservedObject var viewModel: TranscriptViewModel
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcript", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredSegments.isEmpty {
                Text(viewModel.searchText.isEmpty ? "No transcript available" : "No matches")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.filteredSegments, id: \.startTime) { segment in
                                TranscriptSegmentRow(
                                    segment: segment,
                                    isCurrent: viewModel.currentSegment?.startTime == segment.startTime,
                                    isHighlighted: !viewModel.searchText.isEmpty,
                                    onTap: { onSeek(segment.startTime) }
                                )
                                .id(segment.startTime)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onChange(of: viewModel.currentSegment?.startTime) { newStart in
                        if let start = newStart, viewModel.searchText.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(start, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let isCurrent: Bool
    let isHighlighted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Text(formatTimestamp(segment.startTime))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(isCurrent ? .accentColor : .secondary)
                    .frame(width: 50, alignment: .trailing)

                Text(segment.text)
                    .font(.system(.subheadline))
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .fontWeight(isCurrent ? .medium : .regular)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
