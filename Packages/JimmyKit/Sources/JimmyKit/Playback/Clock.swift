import Foundation

/// A source of "now", injected so tests can control elapsed time deterministically
/// instead of sleeping real wall-clock seconds.
public protocol Clock {
    func now() -> Date
}

/// The real clock, backed by `Date()`.
public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
