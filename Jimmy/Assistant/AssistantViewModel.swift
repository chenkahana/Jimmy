import Foundation

/// One message in the chat transcript.
struct AssistantMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
}

/// Drives the assistant chat screen: sends prompts to `session`, streams the reply into the
/// transcript, and exposes `confirmations` so the view can show a confirm button for
/// `unsubscribe`/`clearQueue`. `session` is `nil` when the model is unavailable — the view shows
/// `availability`'s reason instead of a chat in that case, so `send` is never called.
@MainActor
@Observable
final class AssistantViewModel {
    private(set) var messages: [AssistantMessage] = []
    private(set) var isResponding = false
    let availability: AssistantAvailability
    let confirmations: AssistantConfirmationBroker

    private let actions: AssistantActions
    private let session: AssistantModelSession?

    /// `confirmations` must be the same broker passed to `AssistantFactory.makeTools` when
    /// building `session`'s tools — otherwise a tool's confirmation request would land in a
    /// broker nobody is watching.
    init(
        actions: AssistantActions,
        availability: AssistantAvailability,
        session: AssistantModelSession?,
        confirmations: AssistantConfirmationBroker
    ) {
        self.actions = actions
        self.availability = availability
        self.session = session
        self.confirmations = confirmations
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding, let session else { return }

        messages.append(AssistantMessage(role: .user, text: trimmed))
        let replyIndex = messages.count
        messages.append(AssistantMessage(role: .assistant, text: ""))

        isResponding = true
        defer { isResponding = false }

        do {
            for try await partial in session.streamResponse(to: trimmed) {
                messages[replyIndex].text = partial
            }
        } catch {
            messages[replyIndex].text = "Something went wrong: \(error.localizedDescription)"
        }
    }

    func confirmPending() async {
        await confirmations.confirmPending(using: actions)
    }
}
