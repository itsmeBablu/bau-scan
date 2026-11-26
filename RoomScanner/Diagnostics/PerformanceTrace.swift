import Foundation
import os

/// Static operation names only: never include projects, paths, notes or geometry.
/// Instruments owns collection; this helper does not write files or retain content.
enum PerformanceTrace {
    private static let signposter = OSSignposter(subsystem: "io.github.itsmebablu.dwalkscan", category: "Performance")

    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        func end() { PerformanceTrace.signposter.endInterval(name, state) }
    }

    static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()))
    }

    static func event(_ name: StaticString) { signposter.emitEvent(name) }
}

/// Startup to first root appearance, not proof of first rendered camera frame.
@MainActor enum AppLaunchTrace {
    private static var interval: PerformanceTrace.Interval?
    private static var finished = false
    static func start() {
        guard !finished, interval == nil else { return }
        interval = PerformanceTrace.begin("LaunchToRootAppearance")
    }
    static func firstRootAppeared() {
        guard !finished else { return }
        interval?.end(); interval = nil; finished = true
    }
}

#if os(iOS)
import MetricKit

/// Retained for app lifetime. Payloads stay in Apple's diagnostics pipeline;
/// no payload JSON, stack traces or user content is persisted or uploaded here.
final class PerformanceMetrics: NSObject, MXMetricManagerSubscriber {
    static let shared = PerformanceMetrics()
    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }
    func didReceive(_ payloads: [MXMetricPayload]) {
        PerformanceTrace.event("MetricKitMetricsReceived")
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        PerformanceTrace.event("MetricKitDiagnosticsReceived")
    }
}
#endif
