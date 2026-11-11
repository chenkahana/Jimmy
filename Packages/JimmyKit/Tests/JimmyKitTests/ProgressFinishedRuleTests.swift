import Foundation
import Testing
@testable import JimmyKit

struct ProgressFinishedRuleTests {
    @Test func justBelowThresholdIsNotFinished() {
        #expect(Progress.isFinished(position: 949, duration: 1_000) == false)
    }

    @Test func atThresholdIsFinished() {
        #expect(Progress.isFinished(position: 950, duration: 1_000) == true)
    }

    @Test func fullyPlayedIsFinished() {
        #expect(Progress.isFinished(position: 1_000, duration: 1_000) == true)
    }

    @Test func nilDurationIsNotFinished() {
        #expect(Progress.isFinished(position: 1_000, duration: nil) == false)
    }
}
