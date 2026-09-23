import SwiftUI

/// Read-only, day-grouped list of committed time entries (history-entry-list
/// spec). Owns the elevation-gated day-header total (D8); `HistoryViewModel`
/// owns data only. The navigation bar stays visible at every scroll position
/// (the scroll-driven collapse from the original change was reverted — see
/// the `revert-history-nav-collapse` change).
///
/// Uses `ScrollView` + `LazyVStack(pinnedViews:)` rather than `List`:
/// pinned section headers in a SwiftUI `List` are re-hosted in a separate
/// UIKit layer, so GeometryReader preferences attached to them never reach
/// the scroll-tracking modifiers — the elevation-gated total depends on that
/// scroll tracking. The list is read-only (no swipe actions), so `List`'s
/// editing machinery is not needed.
///
/// Tapping an entry row opens the unified entry form directly as a
/// full-screen cover (remove-activities-layer D6; entry-editor spec):
/// editable for `manual` entries, read-only for imported ones. There is no
/// activity detail sheet.
struct HistoryView: View {
    @EnvironmentObject var container: AppContainer
    /// Observed directly (not via `container`): `AppContainer` publishes
    /// nothing, so nested reads like `container.syncController.status` never
    /// invalidate this view — the status change would be missed and the list
    /// would stay stale after a sync (ProfileView precedent).
    @EnvironmentObject var sync: SyncController
    /// Observed for the pull-notice early-dismiss on sign-in flip (the pull
    /// model shares this instance; see `init`).
    @ObservedObject var session: SessionStore
    @StateObject private var vm: HistoryViewModel
    /// Owns the banner sign-in link (restore-then-sheet, shared with
    /// ProfileView's row — exactly one auth entry flow).
    @StateObject private var enableSync: EnableSyncPresenter
    /// Owns the pull-to-refresh verdict flow (history-pull-to-sync spec).
    @StateObject private var pull: HistoryPullModel
    @State private var elevatedGroupID: String?
    /// The entry opened in the unified entry form (nil = none). EDIT mode
    /// for `manual` entries, LOCKED mode for imported ones (entry-editor
    /// spec, history D6).
    @State private var editingEntry: TimeEntry?
    /// Presents the Log Time sheet (manual-entry spec). Owned by the shell
    /// so the [+] shares the nav-bar toolbar scope (iOS 15 renders a single
    /// scope reliably); the sheet and its refresh stay here.
    @Binding var isLogTimeActive: Bool
    /// Changes whenever the shell's running timer starts or stops (nil on
    /// stop). Lets History reload an entry saved from the compact timer
    /// without leaving the tab.
    private let refreshSignal: String

    init(
        store: LocalStore,
        authService: AuthService,
        sessionStore: SessionStore,
        sync: SyncController,
        connectivity: Connectivity,
        refreshSignal: String = "",
        logTimeActive: Binding<Bool> = .constant(false)
    ) {
        _vm = StateObject(wrappedValue: HistoryViewModel(store: store))
        _enableSync = StateObject(wrappedValue: EnableSyncPresenter(
            authService: authService, sessionStore: sessionStore
        ))
        _pull = StateObject(wrappedValue: HistoryPullModel(
            sync: sync, session: sessionStore, connectivity: connectivity
        ))
        self.session = sessionStore
        self.refreshSignal = refreshSignal
        _isLogTimeActive = logTimeActive
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
                PullNoticeBanner(notice: pull.notice) {
                    Task { await enableSync.enableSync() }
                }
            }
            // ZStack, not Group (same stability rule as above, one level
            // down): the conditional content must not own the modifiers.
            ZStack {
                if vm.isLoading && vm.dayGroups.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        // `.task` alone misses re-entry after saving an entry on Track; a
        // plain `onAppear` reload would re-fire on every inner re-render.
        // The load is guarded by `needsReload` inside the VM.
        .task { await vm.loadIfNeeded() }
        .onAppear { Task { await vm.loadIfNeeded() } }
        // Entries can be saved on Track (or from the compact timer) while
        // History is off-screen; mark stale on leave so the next appear
        // reloads. Without this the `needsReload` guard serves the first
        // snapshot forever. Leaving also clears the transient pull notice.
        .onDisappear {
            vm.invalidate()
            pull.cancelNotice()
        }
        .onChange(of: refreshSignal) { _ in
            vm.invalidate()
            Task { await vm.loadIfNeeded() }
        }
        // A sync cycle merges relay state into LocalStore behind this view:
        // the Profile sheet covers History without firing onDisappear, so the
        // guarded reload above never runs. Observe the cycle directly and
        // reload on exit from `.syncing` (idle or error — a failed cycle may
        // have applied partial merges before throwing).
        .onChange(of: sync.status) { status in
            switch status {
            case .idle, .error:
                vm.invalidate()
                Task { await vm.loadIfNeeded() }
            case .inactive, .syncing:
                break
            }
        }
        .sheet(isPresented: $isLogTimeActive) {
            LogTimeView(service: container.timerService) {
                vm.invalidate()
                Task { await vm.loadIfNeeded() }
            }
        }
        // A successful sign-in dismisses the signed-out pull notice early:
        // first-sync takes over from here.
        .onChange(of: session.state) { state in
            if case .signedIn = state {
                pull.cancelNotice()
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
        // Enable Sync sheet (app-shell spec, shared with ProfileView): the
        // auth flow, presented only when the silent restore left the session
        // signed out. The custom binding routes system dismissal through
        // the presenter; sign-in flips clear the flag from the presenter.
        .sheet(isPresented: Binding(
            get: { enableSync.isSheetPresented },
            set: { if !$0 { enableSync.dismiss() } }
        )) {
            EnableSyncSheet()
                .environmentObject(container)
        }
        // The unified entry form presents as a full-screen cover (D6):
        // EDIT for manual entries, LOCKED for imported ones. Dismissal
        // reloads the day groups (edits and deletes both land here).
        .fullScreenCover(
            item: $editingEntry,
            onDismiss: {
                vm.invalidate()
                Task { await vm.loadIfNeeded() }
            },
            content: { entry in
                LogTimeView(service: container.timerService, editing: entry)
                    .environmentObject(container)
            }
        )
    }

    /// Pull-to-refresh lives on the populated list branch only: the empty
    /// state offers no pull gesture (history-pull-to-sync spec). The closure
    /// runs the sync verdict flow only — never an explicit local reload
    /// (the `sync.status` cycle-exit observer above stays the sole reload
    /// path). The native spinner ticks exactly as long as the awaited
    /// cycle (fresh or joined) lasts.
    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
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
                                viaText: vm.viaText(for: entry)
                            )
                            .padding(.horizontal, Theme.spacingMedium)
                            // Tap → unified entry form cover (history
                            // D6). No swipe/long-press actions.
                            .contentShape(Rectangle())
                            .onTapGesture { editingEntry = entry }
                            .accessibilityAddTraits(.isButton)
                        }
                    } header: {
                        dayGroupHeader(group)
                    }
                }
            }
        }
        .refreshable {
            await pull.refresh()
        }
        .coordinateSpace(name: Self.scrollSpace)
        .accessibilityIdentifier("HistoryList")
        .onPreferenceChange(HeaderFramePreferenceKey.self) { frames in
            updateElevatedGroup(with: frames)
        }
    }

    // MARK: - Day-group header (D8/D10)

    /// The total renders only when the header is elevated (pinned at the top
    /// while the list is scrolled); in-list headers show only the day label.
    @ViewBuilder
    private func dayGroupHeader(_ group: DayGroup) -> some View {
        SectionHeader(title: group.label) {
            if isElevated(group) {
                Text("\(group.total) \(L10n.historyTracked.text)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Theme.spacingMedium)
        .background(Theme.backgroundPrimary)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: HeaderFramePreferenceKey.self,
                    value: [HeaderFrame(groupID: group.id, minY: geo.frame(in: .named(Self.scrollSpace)).minY)]
                )
            }
        )
    }

    private func isElevated(_ group: DayGroup) -> Bool {
        elevatedGroupID == group.id
    }

    /// Derives the elevated header (D8) from the day-header frames: a pinned
    /// header clamps at `minY ≈ 0`. Uses hysteresis-friendly semantics (only
    /// set on a clamp, never cleared transiently) and no explicit animation —
    /// a hair-trigger threshold makes layout effects feed back into the
    /// measurement and oscillate.
    private func updateElevatedGroup(with frames: [HeaderFrame]) {
        // Elevated header (D8): the pinned one — the last header whose frame
        // clamps at the top of the visible area. Only ever set on a clamp;
        // never clear on an empty/transient report, so animation frames that
        // briefly move every header off zero cannot flap the total (a stale
        // id simply matches no header once the groups change).
        if let pinned = frames.last(where: { abs($0.minY) <= Self.headerEpsilon }) {
            if pinned.groupID != elevatedGroupID {
                elevatedGroupID = pinned.groupID
            }
        }
    }

    // MARK: - Layout constants

    private static let scrollSpace = "HistoryScroll"
    /// Pinned headers clamp at `minY ≈ 0`.
    private static let headerEpsilon: CGFloat = 1
}

// MARK: - Pull notice (history-pull-to-sync)

/// Inline verdict below the navigation bar for signed-out/offline pulls
/// (one at a time; newest pull wins). The signed-out notice carries the
/// sign-in link; the offline notice has no action. `Theme` colors only.
private struct PullNoticeBanner: View {
    let notice: HistoryPullModel.Notice?
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
            if notice == .signedOut {
                Button(action: onSignIn) {
                    Text(L10n.historyPullSignIn.text)
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Theme.accentPrimary)
                .accessibilityIdentifier("HistoryPullSignInLink")
            }
        }
        .padding(.vertical, Theme.spacingSmall)
        .padding(.horizontal, Theme.spacingMedium)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundSecondary)
        .accessibilityIdentifier(
            notice == .signedOut ? "HistorySignedOutNotice" : "HistoryOfflineNotice"
        )
    }

    private var message: String {
        notice == .signedOut
            ? L10n.historyPullSignedOut.text
            : L10n.historyPullOffline.text
    }
}

// MARK: - Scroll preferences

private struct HeaderFrame: Equatable {
    let groupID: String
    let minY: CGFloat
}

/// Preference values are read and written only on the main actor (SwiftUI
/// layout passes); `nonisolated(unsafe)` satisfies the strict-concurrency
/// check for the required mutable `defaultValue`.
private struct HeaderFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [HeaderFrame] = []
    static func reduce(value: inout [HeaderFrame], nextValue: () -> [HeaderFrame]) {
        value += nextValue()
    }
}

#if DEBUG
#Preview("History with entries") {
    let container = AppContainer.production()
    NavigationView {
        HistoryView(
            store: container.localStore,
            authService: container.authService,
            sessionStore: container.sessionStore,
            sync: container.syncController,
            connectivity: container.connectivity
        )
    }
    .navigationViewStyle(.stack)
    .environmentObject(container)
    .environmentObject(container.syncController)
}

#Preview("History empty") {
    let container = AppContainer.production()
    NavigationView {
        HistoryView(
            store: container.localStore,
            authService: container.authService,
            sessionStore: container.sessionStore,
            sync: container.syncController,
            connectivity: container.connectivity
        )
    }
    .navigationViewStyle(.stack)
    .environmentObject(container)
    .environmentObject(container.syncController)
}
#endif
