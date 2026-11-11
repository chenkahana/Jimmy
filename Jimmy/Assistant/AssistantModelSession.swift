import FoundationModels
import Foundation

/// What the assistant's view model needs from a model session: "respond to a prompt, using these
/// tools, streamed as it's generated." A seam over `FoundationModels.LanguageModelSession` so
/// tests can fake responses without ever touching the real on-device model.
@MainActor
protocol AssistantModelSession: AnyObject {
    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error>
}

/// The real session, backed by `FoundationModels.LanguageModelSession`. Each snapshot's `content`
/// is the cumulative response text so far, which is exactly what the chat view wants to show.
@MainActor
final class FoundationModelsAssistantSession: AssistantModelSession {
    private let session: LanguageModelSession

    init(tools: [any FoundationModels.Tool], instructions: String) {
        session = LanguageModelSession(tools: tools, instructions: instructions)
    }

    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        let stream = session.streamResponse(to: prompt)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Builds the assistant's tools and instructions — one place both `AssistantView` (the real
/// session) and tests (a fake session, but the same tools) can share.
enum AssistantFactory {
    static func makeTools(actions: AssistantActions, confirmations: AssistantConfirmationBroker) -> [any FoundationModels.Tool] {
        [
            PlayEpisodeTool(actions: actions),
            QueueEpisodeTool(actions: actions),
            SearchPodcastsTool(actions: actions),
            SubscribeTool(actions: actions),
            UnsubscribeTool(actions: actions, confirmations: confirmations),
            SleepTimerTool(actions: actions),
            WhatsPlayingTool(actions: actions),
            ClearQueueTool(confirmations: confirmations),
        ]
    }

    static let instructions = """
        You are Jimmy's podcast assistant. Use the tools to play, queue, search, subscribe to \
        shows, set a sleep timer, or report what's playing. Unsubscribing from a show or clearing \
        the queue needs the person's confirmation first: call those tools, then tell the person \
        you're waiting for them to confirm — never say you've done it until they have.
        """
}
