#if DEBUG
import Foundation
import MetricKit
import OSLog

/// Debug-only MetricKit spike harness (observability Stage 1, task 7.1).
///
/// Subscribes to `MXMetricManager` and logs each delivered payload's class,
/// encoded size, and timestamp window — the data the owner needs for the
/// Collector-vs-Sentry endpoint decision (task 7.2). It NEVER uploads:
/// there is no Collector, Sentry, or network call anywhere in this file.
///
/// Lifetime: `start()` once at launch (see `AppContainer`); the manager
/// holds the subscriber weakly, so the shared instance must stay alive
/// (it does — it is a singleton).
///
/// `unchecked Sendable`: `start()` runs once on the main thread at launch;
/// delivery callbacks only read.
final class MetricKitHarness: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitHarness()

    private let logger = Logger(
        subsystem: "com.antonkosenko.timeoflifeapp",
        category: "MetricKitHarness"
    )
    // Lock-guarded (not main-actor-bound): AppContainer is built from the
    // app entry and from SwiftUI previews with no isolation guarantee, so
    // two concurrent starts must not double-subscribe or race the flag.
    private let lock = NSLock()
    private var didStart = false

    func start() {
        let first = lock.withLock { () -> Bool in
            defer { didStart = true }
            return !didStart
        }
        guard first else { return }
        MXMetricManager.shared.add(self)
        logger.info("metrickit harness started (debug only, no upload)")
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let bytes = payload.jsonRepresentation().count
            let begin = payload.timeStampBegin.description
            let end = payload.timeStampEnd.description
            logger.info(
                "metrickit metrics \(String(describing: type(of: payload)), privacy: .public) bytes=\(bytes, privacy: .public) window=\(begin, privacy: .public)/\(end, privacy: .public)"
            )
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let bytes = payload.jsonRepresentation().count
            let begin = payload.timeStampBegin.description
            let end = payload.timeStampEnd.description
            logger.info(
                "metrickit diagnostic \(String(describing: type(of: payload)), privacy: .public) bytes=\(bytes, privacy: .public) window=\(begin, privacy: .public)/\(end, privacy: .public)"
            )
        }
    }
}
#else
import Foundation

/// Release stub: the harness compiles out entirely (no MetricKit, no logs).
final class MetricKitHarness: Sendable {
    static let shared = MetricKitHarness()

    func start() {}
}
#endif
