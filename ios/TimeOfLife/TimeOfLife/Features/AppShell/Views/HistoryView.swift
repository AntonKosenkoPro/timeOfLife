import SwiftUI

/// Read-only, day-grouped list of committed time entries (history-entry-list
/// spec). Day headers are static two-line blocks (label + total subline,
/// Calendar-Agenda-like) that pin under the navigation bar;
/// `HistoryViewModel` owns data only. Pinned bleed (row text crossing
/// beneath pinned headers) is accepted on every OS (design.md D8). The
/// navigation bar stays visible at every scroll position (the scroll-driven
/// collapse from the original change was reverted — see the
/// `revert-history-nav-collapse` change).
///
/// Tapping an entry row pushes the unified entry form onto this tab's
/// NavigationStack (remove-activities-layer D6 as amended by
/// fix-entry-form-gestures; entry-editor spec): every saved entry opens
/// EDIT. The push (not a full-screen cover)
/// is what provides the leading-edge back gesture — a modal cover has no
/// back stack to pop. There is no activity detail sheet. Signed-out History
/// does not exist — the launch gate precedes every tab — so there is no
/// signed-out pull notice and no auth sheet here
/// (account-bound-local-data).
struct HistoryView: View {
    @EnvironmentObject var container: AppContainer
    /// Observed directly (not via `container`): `AppContainer` publishes
    /// nothing, so nested reads like `container.syncController.status` never
    /// invalidate this view — the status change would be missed and the list
    /// would stay stale after a sync (ProfileView precedent).
    @EnvironmentObject var sync: SyncController
    /// The shell's paths (per-tab-navigation-paths): entry taps append
    /// `.entry` to the History path only — never to another tab — and the
    /// destinations below (Profile + entry form) render from that path, so
    /// one `navigationDestination(for:)` serves this whole stack.
    @EnvironmentObject var shell: AppShellViewModel
    @Environment(\.undoManager)
    private var undoManager
    @StateObject private var vm: HistoryViewModel
    /// Owns the pull-to-refresh verdict flow (history-pull-to-sync spec).
    @StateObject private var pull: HistoryPullModel
    /// Presents the Log Time sheet (manual-entry spec). Owned by the shell
    /// so the [+] shares the nav-bar toolbar scope; the sheet and its
    /// refresh stay here.
    /// Presents the Log Time sheet (manual-entry spec). Owned by the shell
    /// so the [+] shares the nav-bar toolbar scope; the sheet and its
    /// refresh stay here.
    @Binding var isLogTimeActive: Bool
    /// Mirrors whether the current search query hides the bottom tab bar
    /// (history-search spec, design D4): non-blank text hides it, blank
    /// keeps it. Owned by the shell — the History stack's single
    /// stack-owned `.toolbar(for: .tabBar)` reads it alongside the path
    /// (fix-tab-bar-return-jump: a stack-level declaration wins over an
    /// inner one unconditionally, so this view must not declare its own).
    @Binding var searchHidesTabBar: Bool

    init(
        store: LocalStore,
        undoBuffer: UndoBufferStore,
        sessionStore: SessionStore,
        sync: SyncController,
        connectivity: Connectivity,
        logTimeActive: Binding<Bool> = .constant(false),
        searchHidesTabBar: Binding<Bool> = .constant(false)
    ) {
        _vm = StateObject(wrappedValue: HistoryViewModel(store: store, undoBuffer: undoBuffer))
        _pull = StateObject(wrappedValue: HistoryPullModel(
            sync: sync,
            connectivity: connectivity
        ) { [weak sessionStore] in
            guard case let .signedIn(session) = sessionStore?.state else { return nil }
            return session.id
        })
        _isLogTimeActive = logTimeActive
        _searchHidesTabBar = searchHidesTabBar
    }

    var body: some View {
        // VStack, not Group: the lifecycle modifiers below must hang on a
        // structurally stable container. On a bare conditional, every
        // `isLoading`/`dayGroups` branch flip re-fires `.task`/`onAppear`/
        // `onDisappear` — and `onDisappear` invalidates, so each load fed
        // the next one (infinite spinner loop). The pull notice renders
        // above the list, below the navigation bar (the shell owns the bar).
        VStack(spacing: 0) {
            if pull.notice != nil {
                PullNoticeBanner()
            }
            // ZStack, not Group (same stability rule as above, one level
            // down): the conditional content must not own the modifiers.
            ZStack {
                if let diagnostic = vm.searchDiagnostic {
                    InvalidSearchState(diagnostic: diagnostic)
                } else if vm.isLoading && vm.dayGroups.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isSearchFiltering && vm.dayGroups.isEmpty {
                    // No compact timer exists (remove-compact-timer): the
                    // reserved-slot clearance always applies.
                    NoMatchingEntriesState {
                        vm.searchText = ""
                    }
                } else if vm.dayGroups.isEmpty {
                    EmptyState(
                        icon: "clock.arrow.circlepath",
                        title: L10n.historyEmptyTitle.text,
                        subtitle: L10n.historyEmptySubtitle.text
                    )
                } else {
                    historyList
                }
            }
        }
        // Always-visible inline search field (history-search spec,
        // design D4): the native navigation-bar drawer, pinned with the
        // list, hiding on scroll-down and returning on scroll-up. The
        // modifier is never added or removed, so typing/clearing performs
        // no structural layout change. The bottom tab bar follows the
        // blank vs non-blank query state instead: blank (even a focused
        // empty field) keeps it, any non-blank text (results, no-matches,
        // syntax diagnostics) hides it with an animated transition — see
        // the `searchHidesTabBar` mirror below. Live filtering, no
        // autocomplete, never on pushed destinations; syntax-safe input.
        .searchable(
            text: $vm.searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: L10n.historySearchPrompt.text
        )
        // Mirrors the blank vs non-blank query state up to the shell's
        // stack-owned tab-bar visibility (design D4): the first keystroke
        // hides the bar, clearing back to blank restores it. Animated so
        // the transition slides rather than jumps; the equality guard
        // keeps per-keystroke edits from re-firing it. `initial: true`
        // covers the blank start without a separate appear sync.
        .onChange(of: vm.searchText, initial: true) { _, query in
            let hidden = HistoryViewModel.hidesTabBar(for: query)
            if hidden != searchHidesTabBar {
                withAnimation { searchHidesTabBar = hidden }
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        // Opaque tab bar on iOS 18, glass on iOS 26+ (D8): the bar itself
        // is the only thing gated — list content always flows under it.
        .toolbarBackground(usesGlassTabBar ? .automatic : .visible, for: .tabBar)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        // System shake-to-undo for entry deletions (history-entry-list,
        // fix-87): the passive host returns this surface's undo manager so
        // shakes reach the registration `registerSystemUndo` owns.
        .background(ShakeFirstResponderHost(undoManager: undoManager))
        // `.task` alone misses re-entry after saving an entry on Track; a
        // plain `onAppear` reload would re-fire on every inner re-render.
        // The load is guarded by `needsReload` inside the VM.
        .task { await reloadAndRegister() }
        .onAppear {
            vm.setVisible(true)
            Task { await reloadAndRegister() }
        }
        // Entries can be saved on Track while History is off-screen; mark
        // stale on leave so the next appear reloads. Without this the
        // `needsReload` guard serves the first snapshot forever. Leaving
        // also clears the transient pull notice.
        .onDisappear {
            vm.setVisible(false)
            vm.invalidate()
            pull.cancelNotice()
        }
        // A save that lands while History stays visible (external stop) or
        // while suspended (foreground return) reloads inside the view model,
        // which owns those two subscriptions so the real notification path
        // is unit-testable — never through a tab switch, and never through
        // observers here. Only the sync-cycle exit below still observes from
        // the view (it reads the view-owned sync status).
        // A sync cycle merges relay state into LocalStore behind this view:
        // the Profile sheet covers History without firing onDisappear, so the
        // guarded reload above never runs. Observe the cycle directly and
        // reload on exit from `.syncing` (idle or error — a failed cycle may
        // have applied partial merges before throwing).
        .onChange(of: sync.status) { _, status in
            switch status {
            case .idle, .error:
                Task { await invalidateReloadAndRegister() }
            case .inactive, .syncing:
                break
            }
        }
        // Date-only search bounds and day grouping follow the local
        // calendar: re-derive the current query when History becomes
        // current again or the clock/zone changes (history-search spec).
        // Absolute timestamp predicates keep their meaning.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            vm.refreshTimeContext()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification
        )) { _ in
            vm.refreshTimeContext()
        }
        .sheet(isPresented: $isLogTimeActive) {
            LogTimeView(service: container.timerService) {
                Task { await invalidateReloadAndRegister() }
            }
        }
        // A pull-awaited cycle failure surfaces once, with a single OK
        // (history-pull-to-sync spec). Background cycles fail through the
        // same status property but never set the model's message, so they
        // stay dialog-free here (Profile status still reflects them).
        .alert(
            L10n.historySyncErrorTitle.text,
            isPresented: Binding(
                get: { pull.syncErrorMessage != nil },
                set: { if !$0 { pull.clearError() } }
            )
        ) {
            Button(L10n.commonOk.text, role: .cancel) {}
        } message: {
            Text(pull.syncErrorMessage ?? "")
        }
        // A refused/failed entry undo surfaces once, with a single OK
        // (history-entry-list spec: "refused with the existing persistence
        // error"). A system dialog through the existing alert pattern — no
        // banner, no toast (fix-87 deliberate choice, mirroring how
        // ProfileView surfaces its erase error).
        .alert(
            vm.undoError ?? "",
            isPresented: Binding(
                get: { vm.undoError != nil },
                set: { if !$0 { vm.clearUndoError() } }
            )
        ) {
            Button(L10n.commonOk.text, role: .cancel) { vm.clearUndoError() }
        }
        // The unified entry form pushes onto this tab's path
        // (per-tab-navigation-paths): every saved entry opens EDIT.
        // The push provides the system back button and the
        // leading-edge pop gesture (a full-screen cover has no back stack,
        // which is why #50's gesture never recognized). Profile pushes on
        // this same path from the shell toolbar — one value destination
        // serves both, so opening Profile here never touches Track or
        // Insights. Leaving the pushed form reloads the day groups (edits
        // and deletes both land here) — the same invalidate/loadIfNeeded
        // path the CREATE sheet uses.
        .navigationDestination(for: ShellRoute.self) { route in
            switch route {
            case .profile:
                ProfileView()
                    .environmentObject(container)
                    .environmentObject(container.sessionStore)
            case .namePicker:
                // Unreachable: the Track picker route lives on the Track
                // path only. Exhaustiveness, no behavior.
                EmptyView()
            case .notesEditor:
                // Unreachable: the Track notes route lives on the Track
                // path only. Exhaustiveness, no behavior.
                EmptyView()
            case .categoryEditor:
                // Unreachable: the Track category-editor route lives on the
                // Track path only. Exhaustiveness, no behavior.
                EmptyView()
            case .entry(let entry):
                LogTimeView(
                    service: container.timerService,
                    editing: entry,
                    embeddedInNavigationStack: true
                ) {
                    Task { await invalidateReloadAndRegister() }
                }
                .environmentObject(container)
                .onDisappear {
                    Task { await invalidateReloadAndRegister() }
                }
            }
        }
    }

    /// Reload-then-register ordering: the registration reads the newest
    /// buffer row, which only exists after the delete transaction commits —
    /// registering before reload races it.
    private func reloadAndRegister() async {
        await vm.loadIfNeeded()
        await vm.registerSystemUndo(with: undoManager)
    }

    private func invalidateReloadAndRegister() async {
        await vm.handleExternalReload()
        await vm.registerSystemUndo(with: undoManager)
    }

    /// Native day-grouped list (D8): bare two-line headers pin under the
    /// navigation bar; pinned bleed (row text crossing beneath headers) is
    /// accepted on every OS. Chrome stripped to the page; the pull verdict
    /// flow, tap parity, and identifiers are unchanged from the bridge.
    ///
    /// A filtered query with matches additionally leads with the scrolling
    /// result summary (history-search spec): a plain row above the first
    /// group, never a pinned header, so no layout jump accompanies it.
    private var historyList: some View {
        List {
            if let summary = vm.searchSummary {
                SearchResultSummary(text: summary)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: Theme.spacingMedium,
                        bottom: 0,
                        trailing: Theme.spacingMedium
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(vm.dayGroups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        EntryRow(
                            entry: entry,
                            icon: vm.icon(for: entry),
                            categoryNames: vm.categoryNames(for: entry),
                            timeframeText: vm.timeframeText(for: entry),
                            durationText: vm.durationText(for: entry),
                            isInProgress: vm.isInProgress(entry),
                            hasNotes: vm.hasNotes(for: entry),
                            searchPresentation: vm.searchPresentation(for: entry)
                        )
                        .listRowInsets(EdgeInsets(
                            top: 0,
                            leading: Theme.spacingMedium,
                            bottom: 0,
                            trailing: Theme.spacingMedium
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // Tap → pushed unified entry form on this tab's path
                        // (history D6 as amended). No swipe/long-press actions.
                        .contentShape(Rectangle())
                        .onTapGesture { shell.historyPath.append(.entry(entry)) }
                        .accessibilityAddTraits(.isButton)
                    }
                } header: {
                    SectionHeader(
                        title: group.label,
                        subtitle: "\(group.total) \(vm.isSearchFiltering ? L10n.historyMatching.text : L10n.historyTracked.text)"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(Theme.spacingExtraSmall)
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollContentBackground(.hidden)
        .refreshable {
            await pull.refresh()
        }
        .accessibilityIdentifier("HistoryList")
    }

    /// Glass tab bar on iOS 26+; opaque bar on iOS 18 so no scrolled
    /// content shows through it (D8).
    private var usesGlassTabBar: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }
}

#if DEBUG
#Preview("History with entries") {
    let container = AppContainer.production()
    NavigationStack {
        HistoryView(
            store: container.localStore,
            undoBuffer: container.undoBuffer,
            sessionStore: container.sessionStore,
            sync: container.syncController,
            connectivity: container.connectivity
        )
    }
    .environmentObject(container)
    .environmentObject(container.syncController)
    .environmentObject(AppShellViewModel())
}

#Preview("History empty") {
    let container = AppContainer.production()
    NavigationStack {
        HistoryView(
            store: container.localStore,
            undoBuffer: container.undoBuffer,
            sessionStore: container.sessionStore,
            sync: container.syncController,
            connectivity: container.connectivity
        )
    }
    .environmentObject(container)
    .environmentObject(container.syncController)
    .environmentObject(AppShellViewModel())
}
#endif
