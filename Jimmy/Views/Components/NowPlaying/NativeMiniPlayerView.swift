//
//  NativeMiniPlayerView.swift
//  Jimmy
//
//  Compact floating mini player anchored above the tab bar.
//

import SwiftUI
import os

struct NativeMiniPlayerView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "NativeMiniPlayerView")

    @Environment(AppModel.self) private var appModel
    @State private var podcast: Podcast?

    let onTap: () -> Void

    var body: some View {
        if let episode = appModel.playback?.currentEpisode?.asLegacyEpisode() {
            HStack(spacing: JimmyDesign.Spacing.md) {
                Button(action: onTap) {
                    HStack(spacing: JimmyDesign.Spacing.md) {
                        artworkView(for: episode)
                        metadataView(for: episode)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    Task { await appModel.playback?.togglePlayPause() }
                    Motion.lightHaptic()
                }) {
                    Image(systemName: (appModel.playback?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JimmyDesign.Spacing.lg)
            .padding(.vertical, JimmyDesign.Spacing.sm + 2)
            .background(backgroundCard)
            .padding(.horizontal, JimmyDesign.Spacing.sm)
            .padding(.top, JimmyDesign.Spacing.xs)
            .padding(.bottom, JimmyDesign.Spacing.xs)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: episode.id) {
                await loadPodcast(for: episode)
            }
            .popoverTip(MiniPlayerTip(), arrowEdge: .bottom)
        }
    }

    private func artworkView(for episode: Episode) -> some View {
        BulletproofAsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                .fill(Color.gray.opacity(0.22))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous))
    }

    private func metadataView(for episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(episode.title)
                .font(JimmyDesign.Typography.title.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            Text(podcast?.title ?? "Now Playing")
                .font(JimmyDesign.Typography.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backgroundCard: some View {
        RoundedRectangle(cornerRadius: JimmyDesign.Radius.lg, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: JimmyDesign.Radius.lg, style: .continuous)
                    .stroke(JimmyDesign.Palette.mutedBorder, lineWidth: 0.6)
            )
            .shadow(
                color: JimmyDesign.Shadow.cardColor,
                radius: JimmyDesign.Shadow.cardRadius,
                x: 0,
                y: JimmyDesign.Shadow.cardY
            )
    }

    private func loadPodcast(for episode: Episode) async {
        guard let podcastID = episode.podcastID else {
            return
        }

        do {
            podcast = try await DIContainer.shared.podcastRepository.fetchPodcast(id: podcastID, ignoreCache: false)
        } catch {
            logger.error("Failed to load podcast: \(error)")
        }
    }
}
