import Foundation

/// Local persistence contract for time entries.
protocol TimerStoring: Sendable {
    func save(_ entry: TimeEntry) async throws
    func unsyncedEntries() async -> [TimeEntry]
    func markSynced(_ entry: TimeEntry) async throws
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
        return entries.filter { !$0.synced }
    }

    func markSynced(_ entry: TimeEntry) async throws {
        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entries[index].markSynced()
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
        return try JSONDecoder().decode([TimeEntry].self, from: data)
    }

    private func saveEntries(_ entries: [TimeEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url)
    }
}
