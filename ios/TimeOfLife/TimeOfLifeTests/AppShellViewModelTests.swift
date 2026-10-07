import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("AppShellViewModel")
struct AppShellViewModelTests {

    @Test("launches into Track by default")
    func launchesIntoTrack() {
        let vm = makeViewModel()
        #expect(vm.selectedTab == .track)
    }

    @Test("switching destinations preserves selection")
    func switchingPreservesSelection() {
        let vm = makeViewModel()
        vm.selectedTab = .history
        #expect(vm.selectedTab == .history)
        vm.selectedTab = .insights
        #expect(vm.selectedTab == .insights)
        vm.selectedTab = .track
        #expect(vm.selectedTab == .track)
    }

    @Test("no running draft shows no compact state")
    func noRunningTimer() async throws {
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.runningTimer == nil)
    }

    @Test("running draft is observed after load")
    func runningTimerObserved() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.saveTimerDraft(activityText: "Deep work", categoryIDs: ["c1"], startedAt: Date())

        await vm.load()
        #expect(vm.runningTimer != nil)
        #expect(vm.runningTimer?.activityText == "Deep work")
    }

    @Test("compact stop saves entry with the draft's final categories and clears the draft")
    func compactStopSaves() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.createCategory(Category(id: "c1", name: "Work", icon: CatalogIcon.briefcase.rawValue))
        try await store.createCategory(Category(id: "c2", name: "Health", icon: CatalogIcon.briefcase.rawValue))
        let startedAt = Date().addingTimeInterval(-120)
        try await store.saveTimerDraft(
            activityText: "Reading",
            categoryIDs: ["c1", "c2"],
            startedAt: startedAt,
            notes: "compact thought"
        )

        await vm.load()
        #expect(vm.runningTimer != nil)

        await vm.stopFromCompact()
        #expect(vm.runningTimer == nil)

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.activityText == "Reading")
        #expect(entries.first?.categoryIDs == ["c1", "c2"])
        #expect(entries.first?.notes == "compact thought")
        #expect(entries.first?.durationSeconds == 120)
    }

    @Test("compact stop keeps the current destination selected")
    func compactStopKeepsDestination() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        try await store.saveTimerDraft(activityText: "Work", categoryIDs: [], startedAt: Date())

        await vm.load()
        vm.selectedTab = .history
        await vm.stopFromCompact()
        #expect(vm.selectedTab == .history)
    }

    // MARK: - Per-tab navigation paths (per-tab-navigation-paths)

    @Test("paths start empty on every tab")
    func pathsStartEmpty() {
        let vm = makeViewModel()
        #expect(vm.trackPath.isEmpty)
        #expect(vm.historyPath.isEmpty)
        #expect(vm.insightsPath.isEmpty)
    }

    @Test("openProfile pushes only on the selected tab")
    func openProfilePushesSelectedTabOnly() {
        let vm = makeViewModel()
        vm.selectedTab = .track
        vm.openProfile()
        #expect(vm.trackPath == [.profile])
        #expect(vm.historyPath.isEmpty)
        #expect(vm.insightsPath.isEmpty)
    }

    @Test("profile paths stay independent across tabs")
    func profilePathsAreIndependent() {
        let vm = makeViewModel()
        vm.selectedTab = .track
        vm.openProfile()
        vm.selectedTab = .history
        // History shows its own root — Profile was never pre-pushed here.
        #expect(vm.historyPath.isEmpty)
        vm.openProfile()
        #expect(vm.trackPath == [.profile])
        #expect(vm.historyPath == [.profile])
        #expect(vm.insightsPath.isEmpty)
    }

    @Test("openProfile never changes the selected tab")
    func openProfileKeepsSelectedTab() {
        let vm = makeViewModel()
        vm.selectedTab = .insights
        vm.openProfile()
        #expect(vm.selectedTab == .insights)
        #expect(vm.insightsPath == [.profile])
    }

    @Test("openProfile is idempotent on the same tab")
    func openProfileDoesNotDuplicate() {
        let vm = makeViewModel()
        vm.selectedTab = .track
        vm.openProfile()
        vm.openProfile()
        #expect(vm.trackPath == [.profile])
    }

    @Test("entry pushes stay on the history path only")
    func entryPushStaysOnHistory() {
        let vm = makeViewModel()
        let entry = TimeEntry(id: "e1", activityText: "Gym", startedAt: Date())
        vm.historyPath.append(.entry(entry))
        #expect(vm.historyPath == [.entry(entry)])
        #expect(vm.trackPath.isEmpty)
        #expect(vm.insightsPath.isEmpty)
    }

    @Test("profileWasPopped fires only on the profile exit transition")
    func profileWasPoppedTransition() {
        #expect(AppShellViewModel.profileWasPopped(old: [.profile], new: []) == true)
        #expect(AppShellViewModel.profileWasPopped(old: [], new: []) == false)
        #expect(AppShellViewModel.profileWasPopped(old: [], new: [.profile]) == false)
        #expect(AppShellViewModel.profileWasPopped(old: [.profile], new: [.profile]) == false)
    }

    // MARK: - Helpers

    private func makeViewModel() -> AppShellViewModel {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        return AppShellViewModel(service: TimerService(store: store))
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }
}
