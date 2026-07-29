import Foundation
@testable import TimeOfLife

/// Records calls and returns canned results / errors. Drives `TimerService`
/// and `TimerViewModel` tests without a network. Mirrors `FakeAuthRepository`.
///
/// Thread-safe via `NSLock`.
final class FakeEntriesRepository: EntriesRepository, @unchecked Sendable {

    /// Recorded call types for verification.
    enum Call: Equatable {
        case create(TimeEntry)
        case stop(id: UUID, endedAt: Date, updatedAt: Date)
        case delete(id: UUID)
        case get(id: UUID)
    }

    // MARK: - State

    private let lock = NSLock()
    private var _calls: [Call] = []

    /// All recorded calls, in order.
    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    // MARK: - Canned results

    var getResult: EntryDTO?

    // MARK: - Per-method errors

    var createError: Error?
    var stopError: Error?
    var deleteError: Error?
    var getError: Error?

    // MARK: - Recording

    private func record(_ call: Call) {
        lock.lock(); _calls.append(call); lock.unlock()
    }

    // MARK: - EntriesRepository

    func create(_ entry: TimeEntry) async throws {
        record(.create(entry))
        if let e = createError { throw e }
    }

    func stop(id: UUID, endedAt: Date, updatedAt: Date) async throws {
        record(.stop(id: id, endedAt: endedAt, updatedAt: updatedAt))
        if let e = stopError { throw e }
    }

    func delete(id: UUID) async throws {
        record(.delete(id: id))
        if let e = deleteError { throw e }
    }

    func get(id: UUID) async throws -> EntryDTO {
        record(.get(id: id))
        if let e = getError { throw e }
        if let result = getResult { return result }
        throw APIError.server(code: "not_found", message: "Not found")
    }
}
