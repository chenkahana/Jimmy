import XCTest
@testable import Jimmy

@MainActor
final class AssistantViewModelTests: XCTestCase {
    func testUnavailableViewModelExposesTheReasonAndNeverResponds() async {
        let actions = FakeAssistantActions()
        let reason = "Turn on Apple Intelligence in Settings to use the assistant."
        let viewModel = AssistantViewModel(
            actions: actions,
            availability: .unavailable(reason: reason),
            session: nil,
            confirmations: AssistantConfirmationBroker()
        )

        guard case .unavailable(let shownReason) = viewModel.availability else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertEqual(shownReason, reason)

        // No session (the model's unavailable), so `send` must be a no-op rather than crash or
        // silently "respond".
        await viewModel.send("play something")
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testSendStreamsTheReplyIntoTheTranscript() async {
        let actions = FakeAssistantActions()
        let session = FakeAssistantModelSession()
        session.chunksToStream = ["Playing", "Playing \"The Daily\"."]
        let viewModel = AssistantViewModel(
            actions: actions,
            availability: .available,
            session: session,
            confirmations: AssistantConfirmationBroker()
        )

        await viewModel.send("play the daily")

        XCTAssertEqual(session.lastPrompt, "play the daily")
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(viewModel.messages.first?.text, "play the daily")
        XCTAssertEqual(viewModel.messages.last?.text, "Playing \"The Daily\".")
        XCTAssertFalse(viewModel.isResponding)
    }

    func testConfirmPendingRunsTheActionThroughTheSameBrokerTheToolsUse() async {
        let actions = FakeAssistantActions()
        let confirmations = AssistantConfirmationBroker()
        let viewModel = AssistantViewModel(
            actions: actions,
            availability: .available,
            session: nil,
            confirmations: confirmations
        )
        _ = confirmations.requestConfirmation(.clearQueue)

        await viewModel.confirmPending()

        XCTAssertEqual(actions.clearQueueCallCount, 1)
        XCTAssertNil(confirmations.pending)
    }
}
