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

    // MARK: - Stack-owned tab-bar visibility (fix-tab-bar-return-jump)

    @Test("tab bar shows at every tab root")
    func tabBarVisibleAtRoots() {
        #expect(AppShellViewModel.isTabBarHidden(path: []) == false)
    }

    @Test("any push hides the tab bar")
    func tabBarHiddenOnPush() {
        #expect(AppShellViewModel.isTabBarHidden(path: [.profile]) == true)
        let entry = TimeEntry(id: "e1", activityText: "Gym", startedAt: Date())
        #expect(AppShellViewModel.isTabBarHidden(path: [.entry(entry)]) == true)
        #expect(AppShellViewModel.isTabBarHidden(path: [.namePicker(initialText: "Gy")]) == true)
        #expect(AppShellViewModel.isTabBarHidden(path: [.notesEditor(initialText: "n", entryName: "Gym")]) == true)
        #expect(AppShellViewModel.isTabBarHidden(path: [.profile, .entry(entry)]) == true)
    }

    @Test("visibility follows only the owning tab's path")
    func tabBarVisibilityIsPerTab() {
        let vm = makeViewModel()
        vm.selectedTab = .track
        vm.openProfile()
        #expect(AppShellViewModel.isTabBarHidden(path: vm.trackPath) == true)
        #expect(AppShellViewModel.isTabBarHidden(path: vm.historyPath) == false)
        #expect(AppShellViewModel.isTabBarHidden(path: vm.insightsPath) == false)
    }

    // MARK: - Post-stop notes route lifecycle (preserve-running-notes-on-live-stop)

    private func editorRoute() -> ShellRoute {
        .notesEditor(initialText: "dirty", entryName: "Gym")
    }

    @Test("popping the editor with no pending decision abandons typing")
    func editorPopWithoutPendingClearsEdit() {
        #expect(AppShellViewModel.notesRouteEffect(
            oldPath: [editorRoute()], newPath: [],
            hasPendingReview: false, isReviewing: false
        ) == .editorClosed)
    }

    @Test("X/back from the kept-open review surface discards")
    func editorPopWhileReviewingDiscards() {
        #expect(AppShellViewModel.notesRouteEffect(
            oldPath: [editorRoute()], newPath: [],
            hasPendingReview: true, isReviewing: true
        ) == .discardReview)
    }

    @Test("an awaiting decision survives an editor pop")
    func editorPopWhileAwaitingKeepsDecision() {
        #expect(AppShellViewModel.notesRouteEffect(
            oldPath: [editorRoute()], newPath: [],
            hasPendingReview: true, isReviewing: false
        ) == .none)
    }

    @Test("popping the pushed review page discards")
    func reviewPopDiscards() {
        #expect(AppShellViewModel.notesRouteEffect(
            oldPath: [.notesReview], newPath: [],
            hasPendingReview: true, isReviewing: true
        ) == .discardReview)
        #expect(AppShellViewModel.notesRouteEffect(
            oldPath: [.notesReview], newPath: [],
            hasPendingReview: false, isReviewing: false
        ) == .none)
    }

    @Test("pushes and unrelated pops have no session effect")
    func pushesAndUnrelatedPopsHaveNoEffect() {
        #expect(AppShellViewModel.notesRouteEffect(
            oldPath: [], newPath: [editorRoute()],
            hasPendingReview: false, isReviewing: false
        ) == .none)
        #expect(AppShellViewModel.notesRouteEffect(
            oldPath: [.profile], newPath: [],
            hasPendingReview: true, isReviewing: true
        ) == .none)
    }

    // MARK: - Helpers

    private func makeViewModel() -> AppShellViewModel {
        AppShellViewModel()
    }
}
