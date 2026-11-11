import SwiftUI

/// Episode list for a selected smart playlist
struct SmartPlaylistDetailView: View {
    @StateObject private var viewModel: SmartPlaylistViewModel

    init(playlistType: SmartPlaylistType) {
        self._viewModel = StateObject(wrappedValue: SmartPlaylistViewModel(playlistType: playlistType))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.episodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: viewModel.playlistType.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No episodes")
                        .font(.headline)
                    Text("Episodes matching this playlist's criteria will appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.episodes, id: \.episode.id) { ewps in
                    NavigationLink(destination: EpisodeDetailView(episodeWithState: ewps)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ewps.episode.title)
                                .font(.subheadline)
                                .lineLimit(2)
                            if let date = ewps.episode.publishedDate {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(viewModel.playlistType.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadEpisodes()
        }
    }
}
