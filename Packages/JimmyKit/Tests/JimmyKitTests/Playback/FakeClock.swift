import Foundation
@testable import JimmyKit

/// A controllable `Clock` so save-throttling and sleep-timer tests don't need to sleep real time.
final class FakeClock: Clock {
    private(set) var current: Date

    init(current: Date = Date(timeIntervalSince1970: 0)) {
        self.current = current
    }

    func now() -> Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
