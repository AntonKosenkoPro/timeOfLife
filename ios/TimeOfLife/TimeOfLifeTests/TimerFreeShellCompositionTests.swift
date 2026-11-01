import Testing
import Foundation
@testable import TimeOfLife

/// Timer-free shell composition (remove-compact-timer, 3.4).
///
/// History and Insights must compose from store-level inputs alone — no
/// running-timer signal — and the shell view model must own navigation
/// state only. Mirror checks fail if compact-only plumbing (`refreshSignal`,
/// `runningTimer`, timer service) is reintroduced.
@MainActor
@Suite("Timer-free shell composition")
struct TimerFreeShellCompositionTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1")))
    }

    private func storedLabels(of view: Any) -> [String] {
        Mirror(reflecting: view).children.compactMap(\.label).map { label in
            // Property-wrapper storage reflects with leading underscores
            // (`@Binding var refreshSignal` → `_refreshSignal`; `@State`
            // synthesizes a second one → `__period`): strip all of them so
            // the guards below catch a reintroduction in any wrapped shape,
            // not just the plain stored-property shape the removal left
            // behind.
            String(label.drop { $0 == "_" })
        }
    }

    @Test("History carries no running-timer signal")
    func historyHasNoTimerSignal() throws {
        let store = try makeStore()
        let sync = SyncController(
            store: store,
            remote: MockCatalogRepository(),
            connectivity: MockConnectivity(connected: true)
        ) { "u1" }
        let view = HistoryView(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            sessionStore: SessionStore(),
            sync: sync,
            connectivity: MockConnectivity(connected: true)
        )
        let labels = storedLabels(of: view)
        // Positive probe: reflection actually sees stored properties, so
        // the absence checks below cannot pass vacuously.
        #expect(labels.contains("isLogTimeActive"))
        #expect(!labels.contains("refreshSignal"))
    }

    @Test("Insights carries no running-timer signal")
    func insightsHasNoTimerSignal() throws {
        let store = try makeStore()
        let view = InsightsView(store: store)
        let labels = storedLabels(of: view)
        // Positive probe: reflection actually sees stored properties, so
        // the absence check below cannot pass vacuously.
        #expect(labels.contains("lens"))
        #expect(!labels.contains("refreshSignal"))
    }

    @Test("shell view model owns navigation state only")
    func shellOwnsNavigationOnly() {
        let vm = AppShellViewModel()
        let labels = storedLabels(of: vm)
        // Positive probe: reflection actually sees stored properties, so
        // the absence checks below cannot pass vacuously.
        #expect(labels.contains("selectedTab"))
        #expect(!labels.contains("runningTimer"))
        #expect(!labels.contains("service"))
        #expect(vm.selectedTab == .track)
        #expect(vm.trackPath.isEmpty)
        #expect(vm.historyPath.isEmpty)
        #expect(vm.insightsPath.isEmpty)
    }
}
