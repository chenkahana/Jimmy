import Foundation
import MetricKit

/// Subscribes to MetricKit diagnostic and performance payloads so crashes/hangs
/// surface via Xcode Organizer while still giving us a lightweight local log. `nonisolated`:
/// MetricKit calls `didReceive` off the main thread.
nonisolated final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = MetricsSubscriber()

    private override init() {
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let size = payload.jsonRepresentation().count
            Log.app.info("MetricKit metric payload received: \(size, privacy: .public) bytes")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let size = payload.jsonRepresentation().count
            Log.app.info("MetricKit diagnostic payload received: \(size, privacy: .public) bytes")
        }
    }
}
