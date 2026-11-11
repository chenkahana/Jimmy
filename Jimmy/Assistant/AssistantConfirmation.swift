import Foundation

/// An action a tool wants to perform but must not run until the person taps "Confirm" in the
/// chat UI. `AssistantConfirmationBroker` is the only path that turns one of these into a real
/// `AssistantActions` call — the model's tool call never does.
enum AssistantPendingAction: Sendable, Equatable {
    case clearQueue
    case unsubscribe(podcastID: UUID, podcastTitle: String)

    var confirmationPrompt: String {
        switch self {
        case .clearQueue:
            return "Clear the entire queue?"
        case .unsubscribe(_, let podcastTitle):
            return "Unsubscribe from \(podcastTitle)?"
        }
    }
}

/// Holds at most one action awaiting confirmation for one chat session. `UnsubscribeTool` and
/// `ClearQueueTool` register a `AssistantPendingAction` here instead of performing it; the chat
/// view shows a confirm button bound to `pending`, and only tapping it calls `confirm(using:)`,
/// which is what actually runs `unsubscribe`/`clearQueue` through `AssistantActions`.
@MainActor
@Observable
final class AssistantConfirmationBroker: Sendable {
    private(set) var pending: AssistantPendingAction?

    /// Called by a tool instead of performing the action. Returns the string the tool reports
    /// back to the model.
    func requestConfirmation(_ action: AssistantPendingAction) -> String {
        pending = action
        switch action {
        case .clearQueue:
            return "I'll clear the queue once you confirm — I haven't done it yet."
        case .unsubscribe(_, let podcastTitle):
            return "I'll unsubscribe from \(podcastTitle) once you confirm — I haven't done it yet."
        }
    }

    /// Runs `pending` through `actions` and clears it. Call only from the UI's confirm button.
    func confirmPending(using actions: AssistantActions) async {
        guard let action = pending else { return }
        switch action {
        case .clearQueue:
            await actions.clearQueue()
        case .unsubscribe(let podcastID, _):
            await actions.unsubscribe(podcastID)
        }
        pending = nil
    }

    func dismissPending() {
        pending = nil
    }
}
