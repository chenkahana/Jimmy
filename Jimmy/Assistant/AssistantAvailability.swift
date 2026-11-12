import FoundationModels

/// A plain, testable mirror of `SystemLanguageModel.Availability` — so view-model/view logic and
/// tests don't need to construct a real `SystemLanguageModel` to exercise the unavailable state.
nonisolated enum AssistantAvailability: Equatable {
    case available
    case unavailable(reason: String)

    @MainActor
    static func current() -> AssistantAvailability {
        AssistantAvailability(SystemLanguageModel.default.availability)
    }

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .available
        case .unavailable(let reason):
            self = .unavailable(reason: reason.assistantDescription)
        }
    }
}

private nonisolated extension SystemLanguageModel.Availability.UnavailableReason {
    var assistantDescription: String {
        switch self {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use the assistant."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again in a bit."
        @unknown default:
            return "The assistant isn't available right now."
        }
    }
}
