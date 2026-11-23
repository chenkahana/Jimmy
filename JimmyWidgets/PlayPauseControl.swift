import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button: plays or pauses the queue.
struct PlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetShared.playPauseControlKind, provider: Provider()) { isPlaying in
            ControlWidgetToggle("Jimmy", isOn: isPlaying, action: SetQueuePlayingIntent()) { isOn in
                Label(isOn ? "Playing" : "Paused", systemImage: isOn ? "pause.fill" : "play.fill")
            }
        }
        .displayName("Play Queue")
        .description("Plays or pauses your queue.")
    }

    struct Provider: ControlValueProvider {
        let previewValue = false

        func currentValue() async throws -> Bool {
            WidgetShared.load()?.isPlaying ?? false
        }
    }
}
