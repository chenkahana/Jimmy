import FoundationModels
import Foundation

/// One short reason the model writes for a single suggested episode or show, grounded only in
/// the listening signals given in the prompt.
@Generable
struct SuggestionReason {
    @Guide(description: "One short, specific reason (10 words or fewer) this episode or show is suggested, based only on the listening signals given — never invent facts. For example: \"Because you finished 8 episodes of Hard Fork.\"")
    let reason: String
}

/// What the Suggestions screen needs from a model session: "write one short reason for this
/// candidate, given these signals." A seam over `FoundationModels.LanguageModelSession` so tests
/// can fake it — the same pattern as `Jimmy/Assistant/AssistantModelSession.swift`.
@MainActor
protocol SuggestionsModelSession: AnyObject {
    func reason(for prompt: String) async throws -> String
}

/// The real session, backed by `FoundationModels.LanguageModelSession`.
@MainActor
final class FoundationModelsSuggestionsSession: SuggestionsModelSession {
    private let session: LanguageModelSession

    init(instructions: String = SuggestionsFactory.instructions) {
        session = LanguageModelSession(instructions: instructions)
    }

    func reason(for prompt: String) async throws -> String {
        let response = try await session.respond(to: prompt, generating: SuggestionReason.self)
        return response.content.reason
    }
}

enum SuggestionsFactory {
    static let instructions = """
        You write one short, concrete reason a podcast episode or show is suggested to this \
        listener, using only the listening signals given in each prompt — never invent facts \
        not present there. Keep it under 15 words, plain and specific.
        """
}
