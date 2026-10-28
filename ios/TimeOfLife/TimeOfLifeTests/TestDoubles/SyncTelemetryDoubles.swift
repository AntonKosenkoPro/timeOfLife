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
