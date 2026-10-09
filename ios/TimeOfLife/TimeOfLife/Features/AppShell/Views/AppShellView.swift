import Combine
import SwiftUI

/// The app shell (app-shell spec): Track, History, and Insights as primary
/// destinations, with Profile opened from a consistent top-trailing person
/// control. A running timer stays visible and stoppable on History and
/// Insights through the compact timer.
struct AppShellView: View {
    /// StateObject, not ObservedObject: `RootView` builds this view (and a
    /// fresh `AppShellViewModel`) on every one of its own re-renders — e.g.
    /// any `SessionStore` emission, including silent restores and sign-in
    /// flips. An ObservedObject would inject the fresh VM each time and
    /// reset `selectedTab` to `.track`, yanking the user off History or
    /// Insights without request (app-shell "Return from profile" scenario).
    /// StateObject keeps the first instance; later values are ignored.
    /// (`trackVM` below already follows this pattern.)
    @StateObject var vm: AppShellViewModel
    @EnvironmentObject var container: AppContainer
    /// Observed directly (not via `container`): `AppContainer` publishes
    /// nothing, so a nested read would never invalidate this view and the
    /// sync-exit reload below would be missed (HistoryView precedent).
    @EnvironmentObject var sync: SyncController
    @StateObject private var trackVM: TrackViewModel
    /// Presents the Log Time sheet from History (manual-entry spec). Owned
    /// here so the [+] lives in the same toolbar scope as the Profile
    /// button; the sheet itself stays in `HistoryView`, which owns the
    /// refresh.
    @State private var isHistoryLogTimeActive = false

    init(vm: AppShellViewModel, container: AppContainer) {
        _vm = StateObject(wrappedValue: vm)
        _trackVM = StateObject(wrappedValue: TrackViewModel(
            service: container.timerService,
            connectivity: container.connectivity
        ))
    }

    var body: some View {
        TabView(selection: $vm.selectedTab) {
            trackStack
                .tabItem { Label(L10n.tabTrack.text, systemImage: "timer") }
                .tag(AppShellViewModel.Tab.track)
                .accessibilityIdentifier("TabTrack")

            historyStack
                .tabItem { Label(L10n.tabHistory.text, systemImage: "clock.arrow.circlepath") }
                .tag(AppShellViewModel.Tab.history)
                .accessibilityIdentifier("TabHistory")

            insightsStack
                .tabItem { Label(L10n.tabInsights.text, systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppShellViewModel.Tab.insights)
                .accessibilityIdentifier("TabInsights")
        }
        .tint(Theme.accentPrimary)
        .task { await vm.load() }
        // TabView keeps mounted tabs alive, so Track's own `.task` runs only
        // on first appear: refresh recents + categories on every return, so
        // History edits are inherited and chip icons stay current.
        // `dropFirst` skips the initial value (already covered by `.task`).
        .onReceive(vm.$selectedTab.dropFirst().filter { $0 == .track }) { _ in
            Task { await reloadTrack() }
        }
        // A sync cycle merges relay state into LocalStore behind Track: the
        // first-sync pull lands after the shell mounts, so reload on exit
        // from `.syncing` (idle or error — a failed cycle may have applied
        // partial merges before throwing). Same staleness contract as
        // HistoryView/InsightsView; the guarded reload never blanks the
        // last good snapshot.
        .onChange(of: sync.status) { _, status in
            switch status {
            case .idle, .error:
                Task { await reloadTrack() }
            case .inactive, .syncing:
                break
            }
        }
    }

    /// Serialized Track reload shared by the tab-return, Profile-exit, and
    /// sync-exit paths.
    @MainActor
    private func reloadTrack() async {
        trackVM.invalidate()
        await trackVM.loadIfNeeded()
    }

    /// Track tab: its own push state. Profile is a path value here, so
    /// opening it on Track never pre-pushes it on History or Insights.
    /// The path observer lives on the stack (not the shell body): one
    /// `onChange` per expression keeps the type-checker fast on every
    /// toolchain — a single body-wide chain timed out CI's build.
    private var trackStack: some View {
        NavigationStack(path: $vm.trackPath) {
            TrackView(vm: trackVM) {
                vm.trackPath.append(.namePicker(initialText: trackVM.nameDraft))
            } onOpenNotesEditor: {
                vm.trackPath.append(.notesEditor(
                    initialText: trackVM.state.draft?.notes ?? "",
                    entryName: trackVM.state.draft?.text ?? ""
                ))
            }
                .navigationTitle(L10n.tabTrack.text)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(ShellToolbar(
                    showsLogTime: false,
                    onLogTime: {},
                    onProfile: { vm.openProfile() }
                ))
                .navigationDestination(for: ShellRoute.self) { route in
                    switch route {
                    case .profile:
                        profileDestination
                    case .namePicker(let initialText):
                        // The shared picker for Track (dedicated-name-picker):
                        // completions resolve here from the owning tab's view
                        // model, so the route stays a value. Back cancels.
                        NamePicker(
                            initialText: initialText,
                            recents: trackVM.allNames,
                            categories: trackVM.categories,
                            placeholder: L10n.timerNamePlaceholder.text,
                            emptyHint: L10n.timerRecentsEmptyHint.text,
                            onCompleteSuggestion: { trackVM.select($0) },
                            onCompleteText: {
                                trackVM.nameDraft = $0
                                trackVM.syncReadyFromDraft()
                            }
                        )
                    case let .notesEditor(initialText, entryName):
                        // The running notes editor for Track
                        // (separate-notes-editor): ✓ writes back through the
                        // owning tab's view model; X discards. Back cancels.
                        NotesEditorPage(initialText: initialText, entryName: entryName) { notes in
                            Task { await trackVM.updateDraftNotes(notes) }
                        }
                    case .entry:
                        EmptyView()
                    }
                }
        }
        // Stack-owned tab-bar visibility (fix-tab-bar-return-jump): the bar
        // shows iff this tab sits at its root. Flipping at pop commit (not
        // after the destination disappears) settles bar + content in one
        // pass instead of two. Caller-local links (NamePicker) keep their
        // own destination modifier — no path observes them.
        .toolbar(vm.trackPath.isEmpty ? .automatic : .hidden, for: .tabBar)
        // Per-tab Profile-exit reload: popping Profile here reloads Track
        // data once (the sheet's old onDismiss contract). Pushes to
        // Categories never touch a path value, so no spurious reloads.
        .onChange(of: vm.trackPath) { old, new in
            profilePoppedReload(old: old, new: new)
        }
    }

    /// History tab: its own push state. Destinations live in `HistoryView`
    /// (it owns the entry-form reload), so this stack declares none — one
    /// `navigationDestination(for: ShellRoute.self)` per stack, never two.
    private var historyStack: some View {
        NavigationStack(path: $vm.historyPath) {
            HistoryView(
                store: container.localStore,
                undoBuffer: container.undoBuffer,
                sessionStore: container.sessionStore,
                sync: container.syncController,
                connectivity: container.connectivity,
                refreshSignal: vm.runningTimer?.activityText ?? "",
                logTimeActive: $isHistoryLogTimeActive
            )
            .environmentObject(vm)
            .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            .navigationTitle(L10n.tabHistory.text)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(ShellToolbar(
                showsLogTime: true,
                onLogTime: { isHistoryLogTimeActive = true },
                onProfile: { vm.openProfile() }
            ))
        }
        // Stack-owned tab-bar visibility (fix-tab-bar-return-jump): same
        // contract as the Track stack — the bar shows iff this tab sits at
        // its root. The pushed entry form declares nothing itself.
        .toolbar(vm.historyPath.isEmpty ? .automatic : .hidden, for: .tabBar)
        .onChange(of: vm.historyPath) { old, new in
            profilePoppedReload(old: old, new: new)
        }
    }

    /// Insights tab: its own push state, mirroring the Track tab.
    private var insightsStack: some View {
        NavigationStack(path: $vm.insightsPath) {
            InsightsView(
                store: container.localStore,
                refreshSignal: vm.runningTimer?.activityText ?? ""
            )
            .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            .navigationTitle(L10n.tabInsights.text)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(ShellToolbar(
                showsLogTime: false,
                onLogTime: {},
                onProfile: { vm.openProfile() }
            ))
            .navigationDestination(for: ShellRoute.self) { route in
                if route == .profile {
                    profileDestination
                }
            }
        }
        // Stack-owned tab-bar visibility (fix-tab-bar-return-jump): same
        // contract as the Track stack — the bar shows iff this tab sits at
        // its root.
        .toolbar(vm.insightsPath.isEmpty ? .automatic : .hidden, for: .tabBar)
        .onChange(of: vm.insightsPath) { old, new in
            profilePoppedReload(old: old, new: new)
        }
    }

    /// The Profile page (app-shell spec: pushed page, system Back, no Done).
    /// Built once here for the Track/Insights stacks; the History stack
    /// builds its own inside `HistoryView`, next to the entry destination.
    /// The tab bar hides on Profile through the owning stack's path-driven
    /// visibility above — Profile itself declares nothing.
    private var profileDestination: some View {
        ProfileView()
            .environmentObject(container)
            .environmentObject(container.sessionStore)
    }

    private func profilePoppedReload(old: [ShellRoute], new: [ShellRoute]) {
        if AppShellViewModel.profileWasPopped(old: old, new: new) {
            Task { await reloadTrack() }
        }
    }

    @ViewBuilder private var compactTimerIfNeeded: some View {
        if let running = vm.runningTimer,
           !running.activityText.isEmpty,
           let startedAt = running.startedAt {
            CompactTimer(
                entryText: running.activityText,
                startedAt: startedAt,
                openTrack: {
                    vm.selectedTab = .track
                },
                stop: {
                    Task { await vm.stopFromCompact() }
                }
            )
            .accessibilityIdentifier("CompactTimer")
        }
    }
}

/// The shell's navigation-bar scope (app-shell spec + manual-entry spec):
/// the Profile button on every tab, plus the Log Time [+] on History only.
private struct ShellToolbar: ViewModifier {
    let showsLogTime: Bool
    let onLogTime: () -> Void
    let onProfile: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if showsLogTime {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onLogTime) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.historyLogTime.text)
                    .accessibilityIdentifier("HistoryLogTimeButton")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onProfile) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 19, weight: .regular))
                }
                .accessibilityLabel(L10n.profileTitle.text)
                .accessibilityIdentifier("ProfileButton")
            }
        }
    }
}
#if DEBUG
#Preview("App Shell") {
    let container = AppContainer.production()
    AppShellView(vm: AppShellViewModel(service: container.timerService), container: container)
        .environmentObject(container)
        .environmentObject(container.syncController)
}
#endif
