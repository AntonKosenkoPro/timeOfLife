import Foundation

/// Remote persistence contract for time entries.
///
/// The backend endpoint for time tracking does not exist yet, so production
/// uses `StubTimerRepository` until the API contract is added.
protocol TimerRepository: Sendable {
    func save(_ entry: TimeEntry) async throws
}

/// No-op remote repository used while the backend endpoint is pending.
struct StubTimerRepository: TimerRepository {
    func save(_ entry: TimeEntry) async throws {
        // Intentionally no-op. The entry is stored locally via `TimerStoring`.
    }
}
