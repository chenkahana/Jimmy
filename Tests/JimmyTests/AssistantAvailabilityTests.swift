import XCTest
@testable import Jimmy
import FoundationModels

/// `AssistantAvailability` is what the chat screen shows instead of the chat when Apple's model
/// isn't available — each reason must come through, not just a generic "unavailable" message.
final class AssistantAvailabilityTests: XCTestCase {
    func testAvailableMapsToAvailable() {
        XCTAssertEqual(AssistantAvailability(.available), .available)
    }

    func testDeviceNotEligibleShowsItsReason() {
        guard case .unavailable(let reason) = AssistantAvailability(.unavailable(.deviceNotEligible)) else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertTrue(reason.contains("device"))
    }

    func testAppleIntelligenceNotEnabledShowsItsReason() {
        guard case .unavailable(let reason) = AssistantAvailability(.unavailable(.appleIntelligenceNotEnabled)) else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertTrue(reason.contains("Apple Intelligence"))
    }

    func testModelNotReadyShowsItsReason() {
        guard case .unavailable(let reason) = AssistantAvailability(.unavailable(.modelNotReady)) else {
            return XCTFail("expected .unavailable")
        }
        XCTAssertTrue(reason.lowercased().contains("download"))
    }
}
