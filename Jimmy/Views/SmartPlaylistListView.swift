import SwiftUI

/// Grid of smart playlist cards with episode counts
struct SmartPlaylistListView: View {
    @State private var counts: [SmartPlaylistType: Int] = [:]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SmartPlaylistType.allCases) { playlist in
                NavigationLink(destination: SmartPlaylistDetailView(playlistType: playlist)) {
                    SmartPlaylistCard(playlist: playlist, count: counts[playlist] ?? 0)
                }
                .buttonStyle(.plain)
            }
        }
        .task { await loadCounts() }
    }

    private func loadCounts() async {
        let service = SmartPlaylistService.shared
        for type in SmartPlaylistType.allCases {
            counts[type] = (try? await service.episodeCount(for: type)) ?? 0
        }
    }
}

struct SmartPlaylistCard: View {
    let playlist: SmartPlaylistType
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: playlist.icon)
                .font(.title2)
                .foregroundColor(colorForPlaylist)

            Text(playlist.title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundColor(.primary)

            Text("\(count) episodes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var colorForPlaylist: Color {
        switch playlist.color {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "yellow": return .yellow
        default: return .accentColor
        }
    }
}
