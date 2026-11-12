import SwiftUI

enum LibraryNavigationDestination: Identifiable, Equatable, Hashable {
    case podcast(id: UUID, cachedPodcast: Podcast?, sourceID: String)
    case episode(id: UUID, cachedEpisode: EpisodeWithPlaybackState?, sourceID: String)

    var id: String {
        switch self {
        case .podcast(let podcastID, _, _):
            return "podcast-\(podcastID.uuidString)"
        case .episode(let episodeID, _, _):
            return "episode-\(episodeID.uuidString)"
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .podcast(let podcastID, _, _):
            hasher.combine(0)
            hasher.combine(podcastID)
        case .episode(let episodeID, _, _):
            hasher.combine(1)
            hasher.combine(episodeID)
        }
    }

    static func == (lhs: LibraryNavigationDestination, rhs: LibraryNavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.podcast(let lhsID, _, _), .podcast(let rhsID, _, _)):
            return lhsID == rhsID
        case (.episode(let lhsID, _, _), .episode(let rhsID, _, _)):
            return lhsID == rhsID
        default:
            return false
        }
    }
}

struct ResolvedPodcastDetailView: View {
    let podcastID: UUID
    let cachedPodcast: Podcast?
    let sourceID: String
    let namespace: Namespace.ID

    @State private var resolvedPodcast: Podcast?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let podcast = resolvedPodcast {
                PodcastDetailView(podcast: podcast)
                    .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
            } else if isLoading {
                LibraryRouteLoadingView(
                    title: "Opening Podcast",
                    subtitle: "Loading the show details from your library."
                )
            } else {
                LibraryRouteUnavailableView(
                    title: "Podcast Unavailable",
                    subtitle: errorMessage ?? "This show could not be opened right now.",
                    buttonTitle: "Try Again",
                    action: loadPodcast
                )
            }
        }
        .task(id: podcastID) {
            if resolvedPodcast == nil {
                loadPodcast()
            }
        }
    }

    private func loadPodcast() {
        isLoading = true
        errorMessage = nil
        resolvedPodcast = nil

        Task {
            if let cachedPodcast {
                await MainActor.run {
                    resolvedPodcast = cachedPodcast
                    isLoading = false
                }
                return
            }

            if let livePodcast = AppModel.current?.podcasts.first(where: { $0.id == podcastID })?.asLegacyPodcast() {
                await MainActor.run {
                    resolvedPodcast = livePodcast
                    isLoading = false
                }
                return
            }

            await MainActor.run {
                errorMessage = "This show is no longer available in your library."
                isLoading = false
            }
        }
    }
}

struct ResolvedEpisodeDetailView: View {
    let episodeID: UUID
    let cachedEpisode: EpisodeWithPlaybackState?
    let sourceID: String
    let namespace: Namespace.ID
    @Environment(AppModel.self) private var appModel

    @State private var resolvedEpisode: EpisodeWithPlaybackState?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let episode = resolvedEpisode {
                EpisodeDetailView(episodeWithState: episode)
                    .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
            } else if isLoading {
                LibraryRouteLoadingView(
                    title: "Opening Episode",
                    subtitle: "Loading playback details for this episode."
                )
            } else {
                LibraryRouteUnavailableView(
                    title: "Episode Unavailable",
                    subtitle: errorMessage ?? "This episode could not be opened right now.",
                    buttonTitle: "Try Again",
                    action: loadEpisode
                )
            }
        }
        .task(id: episodeID) {
            if resolvedEpisode == nil {
                loadEpisode()
            }
        }
    }

    private func loadEpisode() {
        isLoading = true
        errorMessage = nil
        resolvedEpisode = nil

        Task {
            if let cachedEpisode {
                await MainActor.run {
                    resolvedEpisode = cachedEpisode
                    isLoading = false
                }
                return
            }

            guard let episode = await appModel.episode(id: episodeID) else {
                await MainActor.run {
                    errorMessage = "This episode is no longer available in your library."
                    isLoading = false
                }
                return
            }

            let progress = await appModel.progress(for: episodeID)
            let episodeWithState = EpisodeWithPlaybackState(
                episode: episode.asLegacyEpisode(),
                playbackState: PlaybackState(
                    episodeID: episodeID,
                    position: progress?.position ?? 0,
                    finished: progress?.isFinished ?? false
                )
            )
            await MainActor.run {
                resolvedEpisode = episodeWithState
                isLoading = false
            }
        }
    }
}

struct LibraryRouteLoadingView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            JimmyScreenBackground()

            VStack(spacing: JimmyDesign.Spacing.sm) {
                ProgressView()
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
    }
}

struct LibraryRouteUnavailableView: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ZStack {
            JimmyScreenBackground()

            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: title,
                subtitle: subtitle,
                primaryAction: .init(label: buttonTitle, systemImage: "arrow.clockwise", action: action)
            )
        }
    }
}

struct OptimizedPodcastCard: View {
    let podcast: Podcast
    let isEditMode: Bool
    let onUnsubscribe: () -> Void

    var body: some View {
        JimmyCard(padding: JimmyDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
                BulletproofAsyncImage(url: podcast.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(1.0, contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(1.0, contentMode: .fit)
                        .overlay(
                            Image(systemName: "waveform.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .aspectRatio(1.0, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Material.glassCompatible)
                        .opacity(0.15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(podcast.author)
                        .font(JimmyDesign.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }
        }
        .drawingGroup()
    }
}
