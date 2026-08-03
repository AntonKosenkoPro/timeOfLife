import Foundation

/// Local persistence contract for time entries.
protocol TimerStoring: Sendable {
    func save(_ entry: TimeEntry) async throws
    func unsyncedEntries() async -> [TimeEntry]
    func entryCount(forActivityId id: UUID) async -> Int
    func latestEntry(forActivityId id: UUID) async -> TimeEntry?
    func delete(id: UUID) async throws
    func markSynced(_ entry: TimeEntry) async throws
    func markSyncFailed(_ entry: TimeEntry) async throws
    func incrementSyncAttempts(_ entry: TimeEntry) async throws
    func replaceActivityId(from oldId: UUID, to newId: UUID) async throws
}

/// File-based local store that keeps unsynced entries in Application Support.
///
/// The queue survives app restarts and is replayed to the remote repository
/// when connectivity returns.
actor LocalTimerStore: TimerStoring {
    private let url: URL

    init(url: URL? = nil) {
        let base = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TimeOfLife", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TimeOfLife", isDirectory: true)
        self.url = base.appendingPathComponent("timerQueue.json")
    }

    func save(_ entry: TimeEntry) async throws {
        try ensureDirectory()
        var entries = try loadEntries()
        entries.append(entry)
        try saveEntries(entries)
    }

    func unsyncedEntries() async -> [TimeEntry] {
        guard let entries = try? loadEntries() else { return [] }
        return entries.filter { !$0.synced && !$0.syncFailed }
    }

    func entryCount(forActivityId id: UUID) async -> Int {
        (try? loadEntries().filter { $0.activityId == id }.count) ?? 0
    }

    func latestEntry(forActivityId id: UUID) async -> TimeEntry? {
        (try? loadEntries().filter { $0.activityId == id }.max { $0.startedAt < $1.startedAt }) ?? nil
    }

    func delete(id: UUID) async throws {
        var entries = try loadEntries()
        entries.removeAll { $0.id == id }
        try saveEntries(entries)
    }

    func markSynced(_ entry: TimeEntry) async throws {
        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entries[index].markSynced()
        try saveEntries(entries)
    }

    func markSyncFailed(_ entry: TimeEntry) async throws {
        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entries[index].markSyncFailed()
        try saveEntries(entries)
    }

    func incrementSyncAttempts(_ entry: TimeEntry) async throws {
        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entries[index].incrementSyncAttempts()
        try saveEntries(entries)
    }

    func replaceActivityId(from oldId: UUID, to newId: UUID) async throws {
        guard oldId != newId else { return }
        var entries = try loadEntries()
        for index in entries.indices where entries[index].activityId == oldId {
            entries[index] = entries[index].replacingActivityId(with: newId)
        }
        try saveEntries(entries)
    }

    private func ensureDirectory() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func loadEntries() throws -> [TimeEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([TimeEntry].self, from: data)
        return entries
    }

    private func saveEntries(_ entries: [TimeEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url)
    }
}
