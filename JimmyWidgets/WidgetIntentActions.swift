/// The extension's side of the playback intents. They're audio playback intents, so the system runs them in the app,
/// whose `PlaybackIntentActions` does the work; these are never called.
enum PlaybackIntentActions {
    static func playQueue() async throws {}
    static func pause() async {}
    static func skipForward() async {}
    static func skipBack() async {}
    static func playNextEpisode() async throws {}
}
