// swiftlint:disable file_length
// (hosts the alert, both notes destinations, and the route-lifecycle
// observers; splitting the shell view is future work, not this change.)
import Combine
import SwiftUI

/// The app shell (app-shell spec): Track, History, and Insights as primary
/// destinations, with Profile opened from a consistent top-trailing person
/// control. History and Insights render no in-app running-timer surface;
/// Track is the timer surface.
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
    @EnvironmentObject var navigation: AppNavigationStack
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
    /// Whether the History search query currently hides the bottom tab
    /// bar (history-search spec, design D4): mirrored up from
    /// `HistoryView` as the blank vs non-blank query state changes.
    /// Read only by the History stack's stack-owned tab-bar visibility
    /// below; no other tab reads it.
    @State private var historySearchHidesTabBar = false
    /// App-owned clock (screenshot-capture seam; production `.live`).
    private let clock: AppClock

    init(vm: AppShellViewModel, container: AppContainer, trackSnapshot: TrackSnapshot? = nil, clock: AppClock = .live) {
        _vm = StateObject(wrappedValue: vm)
        self.clock = clock
        _trackVM = StateObject(wrappedValue: {
            let trackVM = TrackViewModel(
                service: container.timerService,
                connectivity: container.connectivity,
                now: clock.now,
                calendar: clock.calendar
            )
            // A gate-preloaded snapshot paints complete on the first commit
            // instead of re-querying (steady-track-launch). Previews and
            // hosts without one load on appear as before.
            if let trackSnapshot {
                trackVM.adopt(trackSnapshot)
            }
            return trackVM
        }())
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
        // Post-stop notes decision (preserve-running-notes-on-live-stop):
        // retained unconfirmed running-notes text offers Review Notes
        // (non-destructive) or Discard Changes (destructive, system red).
        // The prompt never saves; Review opens the retained editable text
        // bound to the exact completed entry, Discard abandons only the
        // unconfirmed edits. Attached at the shell level so it presents over
        // pushed pages (existing alert modality also keeps Start
        // inaccessible while the flow is presented — no Start lock is
        // added). Placement and adaptive layout follow HIG/native alert
        // conventions with no fixed position. Presentation derives from the
        // retained session, not a transient flag: an implicit dismissal is
        // not discard — the decision stays resumable.
        .alert(
            "\(L10n.notesStopDecisionTitle.text)",
            isPresented: notesDecisionBinding,
            presenting: trackVM.pendingReview
        ) { _ in
            Button(L10n.notesStopDecisionReview.text) {
                trackVM.beginReview()
                let editorOpen = vm.trackPath.contains { $0.isNotesEditor }
                if !editorOpen {
                    vm.trackPath.append(.notesReview)
                }
            }
            .accessibilityIdentifier("NotesDecisionReviewButton")
            Button(L10n.notesStopDecisionDiscard.text, role: .destructive) {
                trackVM.discardPendingReview()
            }
            .accessibilityIdentifier("NotesDecisionDiscardButton")
        } message: { _ in
            Text(L10n.notesStopDecisionMessage.text)
        }
        // TabView keeps mounted tabs alive, so Track's own `.task` runs only
        // on first appear: refresh recents + categories on every return, so
        // History edits are inherited and chip icons stay current.
        // `dropFirst` skips the initial value (already covered by `.task`).
        .onReceive(vm.$selectedTab.dropFirst().filter { $0 == .track }) { _ in
            Task { await reloadTrack() }
        }
        // Foreground return never re-appears the visible tab: reconcile
        // here too, or a background save leaves the Track timer ticking
        // until the next tab switch (device finding — draft gone,
        // in-memory run stale). Single foreground path
        // (fix-database-suspension-kill): `DatabaseSuspension` posts
        // `didResumeNotification` synchronously from its own
        // `willEnterForeground` observer, so a foreground subscription here
        // would double every return (two invalidates → two full
        // `loadSnapshot` queries — the duplication the History/Insights
        // change removed). The resume signal implies a foreground return
        // and carries resumable access (a read that raced ahead of the
        // queue resume fails silent with the stale flag preserved and
        // retries here), so it owns the reload alone. Serialized reload,
        // same as the tab-return path.
        .onReceive(NotificationCenter.default.publisher(for: DatabaseSuspension.didResumeNotification)) { _ in
            Task { await reloadTrack() }
        }
        // Live Activity tap: a bumped counter selects Track without
        // disturbing per-tab push state. `filter { $0 > 0 }` (not
        // `dropFirst`): on a terminated cold open `onOpenURL` bumps the
        // counter BEFORE the shell subscribes, and `$trackRequestID`
        // replays its current value on subscribe — `dropFirst` would drop
        // that replay and lose the tap. Filtering out only the resting 0
        // keeps normal launches quiet while cold opens still fire.
        .onReceive(navigation.$trackRequestID.filter { $0 > 0 }) { _ in
            vm.selectedTab = .track
        }
        // Island-Stop link (fix-terminated-stop-saved-face Spike D): the
        // widget cannot stop anything with the app dead, so opening the app
        // IS the stop — select Track, reload (orders the cold-open case:
        // the draft lands before the stop reads it), then stop through the
        // exact in-app path. No running draft → `stop()` no-ops gracefully.
        // `filter { $0 > 0 }` (not `dropFirst`): see the track observer
        // above — `dropFirst` loses a terminated cold open because the bump
        // happens before this subscription exists (device finding: first
        // Island tap only opened the app, second tap stopped).
        //
        // The stop is fenced to runs that predate the request
        // (preserve-running-notes-on-live-stop): a stale duplicate link
        // landing after a replacement run started must not stop the new run
        // while the prior resolution is pending.
        .onReceive(navigation.$islandStopRequestID.filter { $0 > 0 }) { _ in
            vm.selectedTab = .track
            Task {
                let requestTime = Date()
                await reloadTrack()
                await trackVM.stop(onlyIfStartedAtBefore: requestTime)
                // The stop committed behind possibly-visible tabs: tell
                // History/Insights to reload (same event the retired intent
                // flow posted; the link flow is the only external stop now).
                NotificationCenter.default.post(name: .timerStoppedExternally, object: nil)
            }
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

    /// Presents the post-stop notes decision while the retained session
    /// needs one. The setter ignores dismissal: an implicit dismissal is
    /// not discard — the session persists and the decision re-presents
    /// (preserve-running-notes-on-live-stop). Action taps resolve the
    /// session, which flips the getter and dismisses for real.
    private var notesDecisionBinding: Binding<Bool> {
        Binding(
            get: { trackVM.pendingReview?.needsDecision ?? false },
            set: { _ in }
        )
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
                // Capture the confirmed baseline before pushing: the page
                // reports every keystroke back, so the stop path can tell an
                // unconfirmed change (including a clear) from a revert.
                trackVM.openRunningNotesEditor()
                vm.trackPath.append(.notesEditor(
                    initialText: trackVM.state.draft?.notes ?? "",
                    entryName: trackVM.state.draft?.text ?? ""
                ))
            } onOpenCategoryEditor: {
                vm.trackPath.append(.categoryEditor)
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
                        // (separate-notes-editor): pre-stop, ✓ writes back
                        // through the owning tab's view model (dirty-tracked
                        // for the post-stop decision); X discards. Post-stop
                        // the same surface becomes the review editor: ✓
                        // confirms to the exact completed entry and pops only
                        // on success, so a failed write keeps the text open
                        // for correction/retry. Input/✓ freeze while a stop
                        // or a review write is in flight. Back cancels.
                        NotesEditorPage(
                            initialText: initialText,
                            entryName: entryName,
                            onTextChange: { trackVM.updateRunningNotesCurrent($0) },
                            confirmReview: { notes in
                                await trackVM.confirmNotesFromEditor(notes)
                            },
                            isInputDisabled: trackVM.runningNotesEdit?.frozen == true
                                || trackVM.pendingReview?.phase == .savingReview
                        )
                    case .notesReview:
                        // The pushed post-stop review surface
                        // (preserve-running-notes-on-live-stop): shown only
                        // when the running editor is no longer open (the open
                        // editor page itself is the review surface otherwise).
                        // Seeded with the retained text bound to the exact
                        // completed entry; opening validates/writes nothing.
                        // X/back discards the unconfirmed edits (the entry
                        // keeps its confirmed notes).
                        if let review = trackVM.pendingReview {
                            NotesEditorPage(
                                initialText: review.retainedText,
                                entryName: review.entryName,
                                onTextChange: nil,
                                confirmReview: { notes in
                                    await trackVM.confirmReviewedNotes(notes)
                                },
                                isInputDisabled: review.phase == .savingReview
                            )
                        } else {
                            EmptyView()
                        }
                    case .entry:
                        EmptyView()
                    case .categoryEditor:
                        // Inline category creation from the running-tag row
                        // (inline-category-creation): create mode only.
                        // Completions resolve here from the owning tab's view
                        // model, so the route stays a value (namePicker
                        // precedent). Saving attaches the new category to
                        // the held draft (running or recoverable error) or
                        // freshens the pool outside a draft; duplicates keep
                        // the editor open with the banner via the shared
                        // view model. No toolbar X —
                        // the system Back button cancels.
                        CategoryEditorForm(
                            store: container.localStore,
                            category: nil,
                            onSaved: { trackVM.attachCreatedCategory($0) },
                            onDuplicate: { _ in },
                            showsDismiss: false
                        )
                    }
                }
        }
        // Stack-owned tab-bar visibility (fix-tab-bar-return-jump): the bar
        // shows iff this tab sits at its root. Flipping at pop commit (not
        // after the destination disappears) settles bar + content in one
        // pass instead of two. Every push past a tab root is path-observed;
        // remaining caller-local links sit under non-empty paths or sheets.
        .toolbar(AppShellViewModel.isTabBarHidden(path: vm.trackPath) ? .hidden : .automatic, for: .tabBar)
        // Per-tab Profile-exit reload: popping Profile here reloads Track
        // data once (the sheet's old onDismiss contract). Pushes to
        // Categories never touch a path value, so no spurious reloads.
        .onChange(of: vm.trackPath) { old, new in
            profilePoppedReload(old: old, new: new)
            trackNotesRoutesChanged(old: old, new: new)
        }
        // A resolved/invalidated post-stop decision owns no surface: remove
        // any stale running/review editor routes (a confirm success or a
        // discard lands back on Track). Removals with no pending session
        // are no-ops in the path observer above — no ping-pong.
        .onChange(of: trackVM.pendingReview) { _, new in
            if new == nil {
                vm.trackPath.removeAll { $0.isNotesEditor || $0 == .notesReview }
            }
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
                logTimeActive: $isHistoryLogTimeActive,
                searchHidesTabBar: $historySearchHidesTabBar,
                clock: clock
            )
            .environmentObject(vm)
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
        // its root — plus History search (history-search spec, design D4):
        // a non-blank query hides the bar with an animated transition and
        // clearing back to blank restores it. A blank query (including a
        // focused empty field) never hides it. The pushed entry form
        // declares nothing itself.
        .toolbar(
            (AppShellViewModel.isTabBarHidden(path: vm.historyPath) || historySearchHidesTabBar)
                ? .hidden : .automatic,
            for: .tabBar
        )
        .onChange(of: vm.historyPath) { old, new in
            profilePoppedReload(old: old, new: new)
        }
    }

    /// Insights tab: its own push state, mirroring the Track tab.
    private var insightsStack: some View {
        NavigationStack(path: $vm.insightsPath) {
            InsightsView(
                store: container.localStore,
                clock: clock
            )
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
        .toolbar(AppShellViewModel.isTabBarHidden(path: vm.insightsPath) ? .hidden : .automatic, for: .tabBar)
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

    /// Running/review editor route lifecycle (preserve-running-notes-on-live-stop):
    /// - The running editor popping with no pending decision abandons the
    ///   tracked typing (ordinary running-editor cancel semantics).
    /// - X/back from a review surface (the kept-open editor bound to review,
    ///   or the pushed review page) discards the unconfirmed edits — the
    ///   completed entry keeps its confirmed notes.
    /// - A still-awaiting decision survives an editor pop (e.g. an implicit
    ///   prompt dismissal gap): Review re-pushes the review page when the
    ///   editor is gone.
    private func trackNotesRoutesChanged(old: [ShellRoute], new: [ShellRoute]) {
        switch AppShellViewModel.notesRouteEffect(
            oldPath: old,
            newPath: new,
            hasPendingReview: trackVM.pendingReview != nil,
            isReviewing: trackVM.pendingReview?.phase == .reviewing
        ) {
        case .editorClosed:
            trackVM.runningNotesEditorClosed()
        case .discardReview:
            trackVM.discardPendingReview()
        case .none:
            break
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
    AppShellView(vm: AppShellViewModel(), container: container)
        .environmentObject(container)
        .environmentObject(AppNavigationStack())
        .environmentObject(container.syncController)
}
#endif
