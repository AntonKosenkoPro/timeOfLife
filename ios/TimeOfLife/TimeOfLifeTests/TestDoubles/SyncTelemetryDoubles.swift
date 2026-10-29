import Foundation
import Testing
@testable import TimeOfLife

final class StubTransport: OTLPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBodies: [Data] = []
    private var storedURLs: [URL] = []
    private var storedPosts = 0
    private var storedShouldThrow = false
    private var storedPermanentStatus: Int?

    var bodies: [Data] {
        lock.withLock { storedBodies }
    }

    var urls: [URL] {
        lock.withLock { storedURLs }
    }

    var posts: Int {
        lock.withLock { storedPosts }
    }

    var shouldThrow: Bool {
        get {
            lock.withLock { storedShouldThrow }
        }
        set {
            lock.withLock { storedShouldThrow = newValue }
        }
    }

    /// Non-2xx status the next posts fail with as permanent (4xx) rejections.
    var permanentStatus: Int? {
        get {
            lock.withLock { storedPermanentStatus }
        }
        set {
            lock.withLock { storedPermanentStatus = newValue }
        }
    }

    func post(url: URL, body: Data) async throws {
        let (fail, permanent): (Bool, Int?) = lock.withLock {
            storedURLs.append(url)
            storedBodies.append(body)
            storedPosts += 1
            return (storedShouldThrow, storedPermanentStatus)
        }
        if let code = permanent, (400 ... 499).contains(code) {
            throw SyncExportError.permanent(status: code)
        }
        if fail {
            throw SyncExportError.rejected
        }
    }
}

/// Synchronous distress recorder: the test's onDistress closure calls
/// `note()` directly, so the count is observable with no task hop — unlike
/// an actor, which the spawned callback could outrun. Lock-guarded;
/// `unchecked` because the stored counter is mutable by design.
final class DistressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    var isEmpty: Bool {
        count < 1
    }

    func note() {
        lock.withLock { storedCount += 1 }
    }
}

/// Transport whose posts block until the test opens the gate, so overlapping
/// flushes can be observed deterministically: while the first flush is held
/// inside `post`, a second `recordSpan` must not start another POST.
final class GatedTransport: OTLPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPosts = 0
    private var storedOpen = false

    var posts: Int {
        lock.withLock { storedPosts }
    }

    func open() {
        lock.withLock { storedOpen = true }
    }

    private var isOpen: Bool {
        lock.withLock { storedOpen }
    }

    func post(url _: URL, body _: Data) async throws {
        lock.withLock { storedPosts += 1 }
        var spins = 0
        while !isOpen, spins < 2_000 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            spins += 1
        }
        throw SyncExportError.rejected
    }
}

// MARK: - SyncTelemetry test helpers

func makeSpan(outcome: SyncSessionOutcome, pushed: Int, pulled: Int, conflicts: Int) -> SyncSessionSpan {
    SyncSessionSpan.build(
        start: Date(), end: Date(), outcome: outcome,
        counts: SyncSessionSpanCounts(pushed: pushed, pulled: pulled, conflicts: conflicts)
    )
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
}

@MainActor
func waitForCycle(_ controller: SyncController) async {
    // Poll the cycle TAIL, not the status: status leaves `.syncing`
    // before span appends / the tail clears the single-flight handle,
    // so status-based polling lets the next syncNow join a dying cycle
    // instead of starting a new one. isCycleLive clears only in
    // finishCycleTail, after the whole body (including span recording)
    // completes. Generous deadline: CI runners are heavily loaded;
    // failure here is loud by design.
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
        if controller.isCycleLive {
            try? await Task.sleep(nanoseconds: 10_000_000)
        } else {
            return
        }
    }
    Issue.record("waitForCycle timed out waiting for the cycle to settle")
}
