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
struct HistoryView: View {
    @StateObject private var vm: HistoryViewModel
    @State private var elevatedGroupID: String?
    /// Changes whenever the shell's running timer starts or stops (nil on
    /// stop). Lets History reload an entry saved from the compact timer
    /// without leaving the tab.
    private let refreshSignal: String

    init(store: LocalStore, refreshSignal: String = "") {
        _vm = StateObject(wrappedValue: HistoryViewModel(store: store))
        self.refreshSignal = refreshSignal
    }

    var body: some View {
        // ZStack, not Group: the lifecycle modifiers below must hang on a
        // structurally stable container. On a bare conditional, every
        // `isLoading`/`dayGroups` branch flip re-fires `.task`/`onAppear`/
        // `onDisappear` — and `onDisappear` invalidates, so each load fed
        // the next one (infinite spinner loop).
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
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        // `.task` alone misses re-entry after saving an entry on Track; a
        // plain `onAppear` reload would re-fire on every inner re-render.
        // The load is guarded by `needsReload` inside the VM.
        .task { await vm.loadIfNeeded() }
        .onAppear { Task { await vm.loadIfNeeded() } }
        // Entries can be saved on Track (or from the compact timer) while
        // History is off-screen; mark stale on leave so the next appear
        // reloads. Without this the `needsReload` guard serves the first
        // snapshot forever.
        .onDisappear { vm.invalidate() }
        .onChange(of: refreshSignal) { _ in
            vm.invalidate()
            Task { await vm.loadIfNeeded() }
        }
    }

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
                                isInProgress: vm.isInProgress(entry)
                            )
                            .padding(.horizontal, Theme.spacingMedium)
                        }
                    } header: {
                        dayGroupHeader(group)
                    }
                }
            }
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
        HistoryView(store: container.localStore)
    }
    .navigationViewStyle(.stack)
    .environmentObject(container)
}

#Preview("History empty") {
    let container = AppContainer.production()
    NavigationView {
        HistoryView(store: container.localStore)
    }
    .navigationViewStyle(.stack)
    .environmentObject(container)
}
#endif
