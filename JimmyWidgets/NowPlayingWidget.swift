import AppIntents
import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen: what's playing, how far in, and what's next. Reads only what the app wrote to the
/// shared App Group on this device.
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.nowPlayingKind, provider: Provider()) { entry in
            NowPlayingWidgetView(data: entry.data)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing and what's next in your queue.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let data: WidgetData?
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: .now, data: nil)
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: .now, data: WidgetShared.load()))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            // The app reloads this whenever what's playing changes; no polling.
            completion(Timeline(entries: [Entry(date: .now, data: WidgetShared.load())], policy: .never))
        }
    }
}

struct NowPlayingWidgetView: View {
    let data: WidgetData?

    @Environment(\.widgetFamily) private var family

    private var title: String { data?.nowPlayingTitle ?? data?.upNext.first?.title ?? "Queue Is Empty" }
    private var show: String? { data?.nowPlayingPodcast ?? data?.upNext.first?.podcastTitle }
    private var isPlaying: Bool { data?.isPlaying ?? false }
    private var progress: Double? { data?.nowPlayingProgress }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(title, systemImage: isPlaying ? "waveform" : "play.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2)
                if let show { Text(show).font(.caption).lineLimit(1) }
                if let progress { ProgressView(value: progress) }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                nowPlaying
                if let next = data?.upNext.dropFirst(data?.nowPlayingTitle == nil ? 1 : 0).prefix(2), !next.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Up Next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(next)) { episode in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(episode.title).font(.caption).lineLimit(2)
                                Text(episode.podcastTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        default:
            nowPlaying
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).lineLimit(3)
            if let show { Text(show).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 0)
            if let progress { ProgressView(value: progress).tint(.accentColor) }
            if data?.nowPlayingTitle != nil || data?.upNext.isEmpty == false {
                Group {
                    if isPlaying {
                        Button(intent: PauseIntent()) { Label("Pause", systemImage: "pause.fill") }
                    } else {
                        Button(intent: PlayQueueIntent()) { Label("Play", systemImage: "play.fill") }
                    }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
