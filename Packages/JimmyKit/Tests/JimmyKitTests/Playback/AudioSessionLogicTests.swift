import Foundation
import Testing
@testable import JimmyKit

struct AudioSessionLogicTests {
    @Test func interruptionBeginningPauses() {
        #expect(AudioSessionLogic.action(for: .began) == .pause)
    }

    @Test func interruptionEndingWithShouldResumeResumes() {
        #expect(AudioSessionLogic.action(for: .ended(shouldResume: true)) == .resume)
    }

    @Test func interruptionEndingWithoutShouldResumeDoesNothing() {
        #expect(AudioSessionLogic.action(for: .ended(shouldResume: false)) == .none)
    }

    @Test func oldDeviceUnavailableRouteChangePauses() {
        #expect(AudioSessionLogic.action(for: .oldDeviceUnavailable) == .pause)
    }

    @Test func otherRouteChangesDoNothing() {
        #expect(AudioSessionLogic.action(for: .other) == .none)
    }
}
