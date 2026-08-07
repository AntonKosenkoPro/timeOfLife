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

    @Test("no running timer shows no compact state")
    func noRunningTimer() async throws {
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.runningTimer == nil)
    }

    @Test("running timer is observed after load")
    func runningTimerObserved() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let activity = Activity(id: "a1", name: "Deep work")
        try await store.createActivity(activity)
        try await store.startTimer(activityID: activity.id, activityName: activity.name, startedAt: Date())

        await vm.load()
        #expect(vm.runningTimer != nil)
        #expect(vm.runningTimer?.activityID == "a1")
    }

    @Test("compact stop saves entry and clears running state")
    func compactStopSaves() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let activity = Activity(id: "a1", name: "Reading")
        try await store.createActivity(activity)
        let startedAt = Date().addingTimeInterval(-120)
        try await store.startTimer(activityID: activity.id, activityName: activity.name, startedAt: startedAt)

        await vm.load()
        #expect(vm.runningTimer != nil)

        await vm.stopFromCompact()
        #expect(vm.runningTimer == nil)

        let entries = try await store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.activityID == "a1")
        #expect(entries.first?.durationSeconds == 120)
    }

    @Test("compact stop keeps the current destination selected")
    func compactStopKeepsDestination() async throws {
        let vm = makeViewModel()
        let store = vm.service.store
        let activity = Activity(id: "a1", name: "Work")
        try await store.createActivity(activity)
        try await store.startTimer(activityID: activity.id, activityName: activity.name, startedAt: Date())

        await vm.load()
        vm.selectedTab = .history
        await vm.stopFromCompact()
        #expect(vm.selectedTab == .history)
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
            .appendingPathComponent("timeoflife.sqlite")
    }
}
