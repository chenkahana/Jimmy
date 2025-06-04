import WidgetKit
import SwiftUI

struct JimmyWidgetExtension: Widget {
    let kind: String = "JimmyWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            JimmyWidgetExtensionEntryView(entry: entry)
        }
        .configurationDisplayName("Jimmy Player")
        .description("Control your podcast playback from the lock screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), currentEpisode: nil, isPlaying: false, playbackPosition: 0, duration: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), currentEpisode: nil, isPlaying: false, playbackPosition: 0, duration: 0)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let widgetData = WidgetDataService.shared
        let currentDate = Date()
        
        let currentEpisode = widgetData.getCurrentEpisode()
        let playbackState = widgetData.getPlaybackState()
        
        let entry = SimpleEntry(
            date: currentDate,
            currentEpisode: currentEpisode,
            isPlaying: playbackState.isPlaying,
            playbackPosition: playbackState.position,
            duration: playbackState.duration
        )
        
        // Update every 30 seconds when playing, every 5 minutes when paused
        let nextUpdate = playbackState.isPlaying ? 
            currentDate.addingTimeInterval(30) : 
            currentDate.addingTimeInterval(300)
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let currentEpisode: Episode?
    let isPlaying: Bool
    let playbackPosition: TimeInterval
    let duration: TimeInterval
}

struct JimmyWidgetExtensionEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        HStack(spacing: 8) {
            // Episode artwork
            AsyncImage(url: entry.currentEpisode?.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 4) {
                // Episode name
                Text(entry.currentEpisode?.title ?? "No Episode")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                // Timeline (progress bar)
                ProgressView(value: entry.duration > 0 ? entry.playbackPosition / entry.duration : 0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .scaleEffect(y: 0.8)
                
                // Controls (backward, play/pause, forward)
                HStack(spacing: 12) {
                    Button(intent: SeekBackwardIntent()) {
                        Image(systemName: "gobackward.15")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(intent: PlayPauseIntent()) {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(intent: SeekForwardIntent()) {
                        Image(systemName: "goforward.15")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding(8)
    }
}

#if canImport(SwiftUI) && DEBUG
#Preview {
    JimmyWidgetExtensionEntryView(entry: SimpleEntry(
        date: Date(),
        currentEpisode: Episode(
            id: UUID(),
            title: "Sample Episode Title",
            artworkURL: nil,
            audioURL: nil,
            description: "Sample description"
        ),
        isPlaying: true,
        playbackPosition: 120,
        duration: 300
    ))
    .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
} 
#endif
