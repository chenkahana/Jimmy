import SwiftUI

/// Speaks outcomes that happen away from VoiceOver's focus: a download finishing or failing, and the sleep
/// timer stopping playback.
struct OutcomeAnnouncements: ViewModifier {
    @Environment(AppModel.self) private var appModel
    /// The sleep timer's last countdown value, to tell a timer that ran out from one that was cancelled.
    @State private var sleepRemaining: TimeInterval?

    func body(content: Content) -> some View {
        content
            .onChange(of: appModel.downloads?.states ?? [:]) { old, new in
                // Only downloads seen in flight, so states loaded at launch stay quiet.
                for (episodeID, state) in new
                where (state == .done || state == .failed) && (old[episodeID] == .queued || old[episodeID] == .downloading) {
                    Task {
                        let title = await appModel.episode(id: episodeID)?.title ?? "Episode"
                        AccessibilityService.shared.announce(
                            state == .done ? "Downloaded \(title)" : "Couldn't download \(title)"
                        )
                    }
                }
            }
            .onChange(of: appModel.playback?.sleepTimerRemaining) { _, remaining in
                if let remaining { sleepRemaining = remaining }
            }
            .onChange(of: appModel.playback?.sleepTimerMode) { old, new in
                guard let old, new == nil else { return }
                let ranOut = switch old {
                case .duration: (sleepRemaining ?? .infinity) <= 2
                case .endOfEpisode: !(appModel.playback?.isPlaying ?? false)
                }
                sleepRemaining = nil
                if ranOut { AccessibilityService.shared.announce("Sleep timer ended") }
            }
    }
}
