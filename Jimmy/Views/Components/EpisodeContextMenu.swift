import SwiftUI
import JimmyKit

/// A reusable context menu component for episodes that appears on long press
/// Provides consistent actions across Library, Discover, and other views
struct EpisodeContextMenu: View {
    let episode: Episode
    let episodeWithState: EpisodeWithPlaybackState?
    let downloadState: JimmyKit.DownloadState?
    let onAddToQueue: () -> Void
    let onMarkAsPlayed: () -> Void
    let onPlayNext: () -> Void
    let onShare: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDeleteDownload: () -> Void

    init(
        episode: Episode,
        episodeWithState: EpisodeWithPlaybackState? = nil,
        downloadState: JimmyKit.DownloadState? = nil,
        onAddToQueue: @escaping () -> Void,
        onMarkAsPlayed: @escaping () -> Void,
        onPlayNext: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onDownload: @escaping () -> Void = {},
        onCancelDownload: @escaping () -> Void = {},
        onDeleteDownload: @escaping () -> Void = {}
    ) {
        self.episode = episode
        self.episodeWithState = episodeWithState
        self.downloadState = downloadState
        self.onAddToQueue = onAddToQueue
        self.onMarkAsPlayed = onMarkAsPlayed
        self.onPlayNext = onPlayNext
        self.onShare = onShare
        self.onDownload = onDownload
        self.onCancelDownload = onCancelDownload
        self.onDeleteDownload = onDeleteDownload
    }

    var body: some View {
        // Context menu items
        Button(action: onAddToQueue) {
            Label("Add to Queue", systemImage: "plus.circle")
        }

        Button(action: onMarkAsPlayed) {
            Label(
                isPlayed ? "Mark as Unplayed" : "Mark as Played",
                systemImage: isPlayed ? "circle" : "checkmark.circle.fill"
            )
        }

        Button(action: onPlayNext) {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        downloadMenuItem

        Button(action: onShare) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder
    private var downloadMenuItem: some View {
        switch downloadState {
        case nil, .failed:
            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle")
            }
        case .queued, .downloading:
            Button(action: onCancelDownload) {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        case .done:
            Button(action: onDeleteDownload) {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }

    private var isPlayed: Bool {
        if let episodeWithState = episodeWithState {
            return episodeWithState.playbackState.finished
        }
        return episode.played || episode.status.contains(.played)
    }
}

/// A tooltip-style context menu that appears on long press
struct EpisodeTooltipMenu: View {
    let episode: Episode
    let episodeWithState: EpisodeWithPlaybackState?
    let onAddToQueue: () -> Void
    let onMarkAsPlayed: () -> Void
    let onPlayNext: () -> Void
    let onShare: () -> Void
    let onDismiss: () -> Void
    
    @State private var showingShareSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Action buttons
            VStack(spacing: 8) {
                tooltipButton(
                    icon: "plus.circle",
                    title: "Add to Queue",
                    action: {
                        onAddToQueue()
                        onDismiss()
                    }
                )
                
                tooltipButton(
                    icon: isPlayed ? "circle" : "checkmark.circle.fill",
                    title: isPlayed ? "Mark as Unplayed" : "Mark as Played",
                    action: {
                        onMarkAsPlayed()
                        onDismiss()
                    }
                )
                
                tooltipButton(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    title: "Play Next",
                    action: {
                        onPlayNext()
                        onDismiss()
                    }
                )
                
                tooltipButton(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    action: {
                        showingShareSheet = true
                    }
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let audioURL = episode.audioURL {
                ShareSheet(items: [audioURL])
            } else {
                ShareSheet(items: [episode.title])
            }
        }
    }
    
    private func tooltipButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var isPlayed: Bool {
        if let episodeWithState = episodeWithState {
            return episodeWithState.playbackState.finished
        }
        return episode.played || episode.status.contains(.played)
    }
}

/// A view modifier that adds long press context menu functionality to episode rows
struct EpisodeLongPressModifier: ViewModifier {
    let episode: Episode
    let episodeWithState: EpisodeWithPlaybackState?
    let downloadState: JimmyKit.DownloadState?
    let onAddToQueue: () -> Void
    let onMarkAsPlayed: () -> Void
    let onPlayNext: () -> Void
    let onShare: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDeleteDownload: () -> Void

    @State private var showingTooltip = false
    @State private var showingShareSheet = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                EpisodeContextMenu(
                    episode: episode,
                    episodeWithState: episodeWithState,
                    downloadState: downloadState,
                    onAddToQueue: onAddToQueue,
                    onMarkAsPlayed: onMarkAsPlayed,
                    onPlayNext: onPlayNext,
                    onShare: { showingShareSheet = true },
                    onDownload: onDownload,
                    onCancelDownload: onCancelDownload,
                    onDeleteDownload: onDeleteDownload
                )
            }
            .sheet(isPresented: $showingShareSheet) {
                if let audioURL = episode.audioURL {
                    ShareSheet(items: [audioURL])
                } else {
                    ShareSheet(items: [episode.title])
                }
            }
    }
}

/// Extension to easily add episode context menu to any view
extension View {
    func episodeContextMenu(
        episode: Episode,
        episodeWithState: EpisodeWithPlaybackState? = nil,
        downloadState: JimmyKit.DownloadState? = nil,
        onAddToQueue: @escaping () -> Void,
        onMarkAsPlayed: @escaping () -> Void,
        onPlayNext: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onDownload: @escaping () -> Void = {},
        onCancelDownload: @escaping () -> Void = {},
        onDeleteDownload: @escaping () -> Void = {}
    ) -> some View {
        self.modifier(
            EpisodeLongPressModifier(
                episode: episode,
                episodeWithState: episodeWithState,
                downloadState: downloadState,
                onAddToQueue: onAddToQueue,
                onMarkAsPlayed: onMarkAsPlayed,
                onPlayNext: onPlayNext,
                onShare: onShare,
                onDownload: onDownload,
                onCancelDownload: onCancelDownload,
                onDeleteDownload: onDeleteDownload
            )
        )
    }
}