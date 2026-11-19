import AppIntents
import Foundation

/// What the playback intents do, in the app. Everything goes through `AppModel`, the same path as the Play and Skip
/// buttons, so the queue, saved positions and Now Playing stay in step.
enum PlaybackIntentActions {
    static func playQueue() async throws {
        guard let model = AppModel.current, let playback = model.playback, let store = model.readyStore else { return }
        let queue = (try? await store.queue()) ?? []
        guard let first = queue.first else { throw PlaybackIntentError.queueEmpty }
        if playback.currentEpisode?.id == first.id {
            playback.play()
        } else {
            await model.play(first)
        }
    }

    static func pause() async {
        await AppModel.current?.playback?.pause()
    }

    static func skipForward() async {
        await AppModel.current?.playback?.skipForward()
    }

    static func skipBack() async {
        await AppModel.current?.playback?.skipBackward()
    }

    static func playNextEpisode() async throws {
        guard let model = AppModel.current, let playback = model.playback else { return }
        guard playback.currentEpisode != nil else { return try await playQueue() }
        let before = playback.currentEpisode?.id
        await model.skipToNextInQueue()
        guard playback.currentEpisode?.id != before else { throw PlaybackIntentError.nothingAfterThis }
        playback.play()
    }
}

/// Siri and Shortcuts phrases. App-only: the widget extension doesn't declare shortcuts.
struct JimmyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayQueueIntent(),
            phrases: ["Play my queue in \(.applicationName)", "Play \(.applicationName)", "Resume \(.applicationName)"],
            shortTitle: "Play Queue",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PlayNextEpisodeIntent(),
            phrases: ["Play the next episode in \(.applicationName)", "Next episode in \(.applicationName)"],
            shortTitle: "Next Episode",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: SkipForwardIntent(),
            phrases: ["Skip forward in \(.applicationName)"],
            shortTitle: "Skip Forward",
            systemImageName: "goforward"
        )
        AppShortcut(
            intent: SkipBackIntent(),
            phrases: ["Skip back in \(.applicationName)"],
            shortTitle: "Skip Back",
            systemImageName: "gobackward"
        )
    }
}
