import Foundation

/// Entry-count seam used by the catalog delete flow without coupling it to the
/// time-entry model. The history store will provide the real implementation.
protocol ActivityEntryCounting: Sendable {
    func entryCount(forActivityId id: UUID) async -> Int
    /// The most recently recorded entry for an activity, or `nil` if none.
    func latestEntry(forActivityId id: UUID) async -> TimeEntry?
}

struct TimerStoreActivityEntryCounter: ActivityEntryCounting {
    let store: TimerStoring

    func entryCount(forActivityId id: UUID) async -> Int {
        await store.entryCount(forActivityId: id)
    }

    func latestEntry(forActivityId id: UUID) async -> TimeEntry? {
        await store.latestEntry(forActivityId: id)
    }
}
