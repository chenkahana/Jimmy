import Foundation
import Observation
import SwiftUI
import os

enum PerformanceMarker {
    private static let log = OSLog(subsystem: "com.chenkahana.Jimmy", category: "Performance")

    struct Interval {
        fileprivate let name: StaticString
        fileprivate let id: OSSignpostID
    }

    static func begin(_ name: StaticString) -> Interval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return Interval(name: name, id: id)
    }

    static func end(_ interval: Interval) {
        os_signpost(.end, log: log, name: interval.name, signpostID: interval.id)
    }

    static func emit(_ name: StaticString, message: String? = nil) {
        if let message, !message.isEmpty {
            os_signpost(.event, log: log, name: name, "%{public}s", message)
        } else {
            os_signpost(.event, log: log, name: name)
        }
    }
}

enum InteractionMetric {
    case shellFirstRender
    case tabSwitch
    case discoverSearch
    case queueReorder
    case podcastDetailOpen

    fileprivate var signpostName: StaticString {
        switch self {
        case .shellFirstRender:
            return "Shell First Render"
        case .tabSwitch:
            return "Tab Switch"
        case .discoverSearch:
            return "Discover Search"
        case .queueReorder:
            return "Queue Reorder"
        case .podcastDetailOpen:
            return "Podcast Detail Open"
        }
    }
}

@MainActor
@Observable
final class InteractionLatencyTracker {
    struct Token {
        fileprivate let metric: InteractionMetric
        fileprivate let interval: PerformanceMarker.Interval
        fileprivate let start: ContinuousClock.Instant
    }

    static let shared = InteractionLatencyTracker()

    var shellFirstRenderMilliseconds: Double?
    var tabSwitchMilliseconds: Double?
    var discoverSearchMilliseconds: Double?
    var queueReorderMilliseconds: Double?
    var podcastDetailOpenMilliseconds: Double?

    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var shellFirstRenderToken: Token?
    @ObservationIgnored private var tabSwitchToken: Token?

    private init() {}

    func begin(_ metric: InteractionMetric, detail: String? = nil) -> Token {
        if let detail, !detail.isEmpty {
            PerformanceMarker.emit(metric.signpostName, message: detail)
        }

        return Token(
            metric: metric,
            interval: PerformanceMarker.begin(metric.signpostName),
            start: clock.now
        )
    }

    func end(_ token: Token?) {
        guard let token else {
            return
        }

        let elapsedMilliseconds = elapsedMilliseconds(from: token.start)
        PerformanceMarker.end(token.interval)

        switch token.metric {
        case .shellFirstRender:
            shellFirstRenderMilliseconds = elapsedMilliseconds
        case .tabSwitch:
            tabSwitchMilliseconds = elapsedMilliseconds
        case .discoverSearch:
            discoverSearchMilliseconds = elapsedMilliseconds
        case .queueReorder:
            queueReorderMilliseconds = elapsedMilliseconds
        case .podcastDetailOpen:
            podcastDetailOpenMilliseconds = elapsedMilliseconds
        }
    }

    func beginShellFirstRender() {
        shellFirstRenderToken = begin(.shellFirstRender)
    }

    func endShellFirstRender() {
        end(shellFirstRenderToken)
        shellFirstRenderToken = nil
    }

    func beginTabSwitch() {
        tabSwitchToken = begin(.tabSwitch)
    }

    func endTabSwitch(tab: ShellTab) {
        if let tabSwitchToken {
            PerformanceMarker.emit(InteractionMetric.tabSwitch.signpostName, message: tab.identifier)
            end(tabSwitchToken)
            self.tabSwitchToken = nil
        }
    }

    private func elapsedMilliseconds(from start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: clock.now)
        return Double(duration.components.seconds) * 1_000 +
            Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}

#if DEBUG
struct PerformanceDebugOverlay: View {
    @Environment(InteractionLatencyTracker.self) private var tracker

    var body: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
            metricLine("Shell", tracker.shellFirstRenderMilliseconds)
            metricLine("Tab", tracker.tabSwitchMilliseconds)
            metricLine("Search", tracker.discoverSearchMilliseconds)
            metricLine("Queue", tracker.queueReorderMilliseconds)
            metricLine("Detail", tracker.podcastDetailOpenMilliseconds)
        }
        .padding(.horizontal, JimmyDesign.Spacing.md)
        .padding(.vertical, JimmyDesign.Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                .stroke(JimmyDesign.Palette.mutedBorder, lineWidth: 0.6)
        )
        .padding(.top, JimmyDesign.Spacing.xl)
        .padding(.trailing, JimmyDesign.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }

    private func metricLine(_ title: String, _ value: Double?) -> some View {
        HStack(spacing: JimmyDesign.Spacing.sm) {
            Text(title)
                .font(JimmyDesign.Typography.detail.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: JimmyDesign.Spacing.sm)

            Text(formatted(value))
                .font(JimmyDesign.Typography.detail.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return String(format: "%.0fms", value)
    }
}
#endif
