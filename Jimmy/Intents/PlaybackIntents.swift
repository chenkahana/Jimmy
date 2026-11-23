import AppIntents

// Shared with the widget extension, so controls and widgets can run them. As audio playback intents they always run
// in the app's process, where `PlaybackIntentActions` drives the real queue; the extension's copy of that type does
// nothing.

struct PlayQueueIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play My Queue"
    static let description = IntentDescription("Plays the first episode in your queue from where you left off.")

    func perform() async throws -> some IntentResult {
        try await PlaybackIntentActions.playQueue()
        return .result()
    }
}

struct PauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause"
    static let description = IntentDescription("Pauses the episode that's playing.")

    func perform() async throws -> some IntentResult {
        await PlaybackIntentActions.pause()
        return .result()
    }
}

struct SkipForwardIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Forward"
    static let description = IntentDescription("Skips forward by your skip interval.")

    func perform() async throws -> some IntentResult {
        await PlaybackIntentActions.skipForward()
        return .result()
    }
}

struct SkipBackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Skip Back"
    static let description = IntentDescription("Skips back by your skip interval.")

    func perform() async throws -> some IntentResult {
        await PlaybackIntentActions.skipBack()
        return .result()
    }
}

struct PlayNextEpisodeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Next Episode"
    static let description = IntentDescription(
        "Plays the next episode in your queue. The one you skip keeps its place and moves to the end of the queue."
    )

    func perform() async throws -> some IntentResult {
        try await PlaybackIntentActions.playNextEpisode()
        return .result()
    }
}

/// The Control Center control's action: on plays the queue, off pauses.
struct SetQueuePlayingIntent: SetValueIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause Queue"

    @Parameter(title: "Playing")
    var value: Bool

    func perform() async throws -> some IntentResult {
        if value {
            try await PlaybackIntentActions.playQueue()
        } else {
            await PlaybackIntentActions.pause()
        }
        return .result()
    }
}

/// Why an intent couldn't play, in words Siri can say.
enum PlaybackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case queueEmpty
    case nothingAfterThis

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .queueEmpty: "Your queue is empty."
        case .nothingAfterThis: "There's nothing after this episode in your queue."
        }
    }
}
