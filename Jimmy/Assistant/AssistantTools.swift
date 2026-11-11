import FoundationModels
import Foundation
import JimmyKit

/// The assistant's tools: thin wrappers over `AssistantActions` with `@Generable` arguments the
/// model fills in. Each `call` does its own library matching (`AssistantEpisodeMatcher`) and
/// reports back what it did in plain text — the chat UI shows that text as the assistant's reply.
///
/// `UnsubscribeTool` and `ClearQueueTool` never call `AssistantActions.unsubscribe`/`clearQueue`
/// directly: they register the action with `AssistantConfirmationBroker` and return a message
/// saying it's waiting on the person to confirm.

// MARK: - Play

@Generable
struct PlayEpisodeArguments {
    @Guide(description: "The episode's title, or its show's name to play that show's latest episode.")
    let query: String
}

struct PlayEpisodeTool: FoundationModels.Tool {
    let actions: any AssistantActions
    let name = "playEpisode"
    let description = "Plays an episode from the person's library, matched by episode title or show name."

    func call(arguments: PlayEpisodeArguments) async throws -> String {
        let episodes = await actions.libraryEpisodes()
        let podcasts = await actions.libraryPodcasts()
        guard let episode = AssistantEpisodeMatcher.bestMatch(for: arguments.query, episodes: episodes, podcasts: podcasts) else {
            return "I couldn't find an episode matching \"\(arguments.query)\" in your library."
        }
        await actions.playNow(episode)
        return "Playing \"\(episode.title)\"."
    }
}

// MARK: - Queue

@Generable
struct QueueEpisodeArguments {
    @Guide(description: "The episode's title, or its show's name to queue that show's latest episode.")
    let query: String
    @Guide(description: "True to play this episode right after the current one; false to add it to the end of the queue.")
    let playNext: Bool
}

struct QueueEpisodeTool: FoundationModels.Tool {
    let actions: any AssistantActions
    let name = "queueEpisode"
    let description = "Adds an episode to the queue, either at the end or to play next."

    func call(arguments: QueueEpisodeArguments) async throws -> String {
        let episodes = await actions.libraryEpisodes()
        let podcasts = await actions.libraryPodcasts()
        guard let episode = AssistantEpisodeMatcher.bestMatch(for: arguments.query, episodes: episodes, podcasts: podcasts) else {
            return "I couldn't find an episode matching \"\(arguments.query)\" in your library."
        }
        await actions.queueEpisode(episode, playNext: arguments.playNext)
        return arguments.playNext
            ? "\"\(episode.title)\" will play next."
            : "Added \"\(episode.title)\" to the end of the queue."
    }
}

// MARK: - Search

@Generable
struct SearchPodcastsArguments {
    @Guide(description: "What to search Apple Podcasts for, e.g. a show name or topic.")
    let query: String
}

struct SearchPodcastsTool: FoundationModels.Tool {
    let actions: any AssistantActions
    let name = "searchPodcasts"
    let description = "Searches Apple Podcasts by name or topic and lists the top matches."

    func call(arguments: SearchPodcastsArguments) async throws -> String {
        let results = await actions.searchApplePodcasts(query: arguments.query)
        guard !results.isEmpty else {
            return "I didn't find any podcasts matching \"\(arguments.query)\"."
        }
        let top = results.prefix(5).map { "\($0.title) by \($0.author)" }
        return "Found: " + top.joined(separator: "; ") + "."
    }
}

// MARK: - Subscribe

@Generable
struct SubscribeArguments {
    @Guide(description: "The show's name to find on Apple Podcasts and subscribe to.")
    let show: String
}

struct SubscribeTool: FoundationModels.Tool {
    let actions: any AssistantActions
    let name = "subscribe"
    let description = "Finds a show on Apple Podcasts by name and subscribes to it."

    func call(arguments: SubscribeArguments) async throws -> String {
        guard let match = await actions.searchApplePodcasts(query: arguments.show).first else {
            return "I couldn't find \"\(arguments.show)\" on Apple Podcasts."
        }
        do {
            try await actions.subscribe(feedURL: match.feedURL)
            return "Subscribed to \(match.title)."
        } catch {
            return "I couldn't subscribe to \(match.title): \(error.localizedDescription)"
        }
    }
}

// MARK: - Unsubscribe (asks first)

@Generable
struct UnsubscribeArguments {
    @Guide(description: "The already-subscribed show's name to unsubscribe from.")
    let show: String
}

struct UnsubscribeTool: FoundationModels.Tool {
    let actions: any AssistantActions
    let confirmations: AssistantConfirmationBroker
    let name = "unsubscribe"
    let description = "Asks the person to confirm before unsubscribing from a show already in their library."

    func call(arguments: UnsubscribeArguments) async throws -> String {
        let podcasts = await actions.libraryPodcasts()
        guard let podcast = AssistantEpisodeMatcher.bestMatchingPodcast(for: arguments.show, podcasts: podcasts) else {
            return "You're not subscribed to anything matching \"\(arguments.show)\"."
        }
        return await confirmations.requestConfirmation(.unsubscribe(podcastID: podcast.id, podcastTitle: podcast.title))
    }
}

// MARK: - Sleep timer

@Generable
struct SleepTimerArguments {
    @Guide(description: "Minutes until playback stops. Omit this to stop at the end of the current episode instead.")
    let minutes: Int?
}

struct SleepTimerTool: FoundationModels.Tool {
    let actions: any AssistantActions
    let name = "sleepTimer"
    let description = "Sets a sleep timer, either for a number of minutes or for the end of the current episode."

    func call(arguments: SleepTimerArguments) async throws -> String {
        await actions.setSleepTimer(minutes: arguments.minutes)
        if let minutes = arguments.minutes {
            return "Sleep timer set for \(minutes) minutes."
        }
        return "Playback will stop at the end of this episode."
    }
}

// MARK: - What's playing

@Generable
struct WhatsPlayingArguments {}

struct WhatsPlayingTool: FoundationModels.Tool {
    let actions: any AssistantActions
    let name = "whatsPlaying"
    let description = "Reports what's currently playing, if anything."

    func call(arguments: WhatsPlayingArguments) async throws -> String {
        guard let episode = await actions.nowPlayingEpisode() else {
            return "Nothing is playing right now."
        }
        return "Now playing: \"\(episode.title)\"."
    }
}

// MARK: - Clear queue (asks first)

@Generable
struct ClearQueueArguments {}

struct ClearQueueTool: FoundationModels.Tool {
    let confirmations: AssistantConfirmationBroker
    let name = "clearQueue"
    let description = "Asks the person to confirm before removing every episode from the queue."

    func call(arguments: ClearQueueArguments) async throws -> String {
        await confirmations.requestConfirmation(.clearQueue)
    }
}
