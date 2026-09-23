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
    @StateObject private var trackVM: TrackViewModel
    @State private var isShowingProfile = false
    /// Presents the Log Time sheet from History (manual-entry spec). Owned
    /// here so the [+] lives in the same toolbar scope as the Profile
    /// button — one scope renders on every supported iOS version; the
    /// sheet itself stays in `HistoryView`, which owns the refresh.
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
            navigationRoot {
                TrackView(vm: trackVM)
            }
            .tabItem { Label(L10n.tabTrack.text, systemImage: "timer") }
            .tag(AppShellViewModel.Tab.track)
            .accessibilityIdentifier("TabTrack")

            navigationRoot {
                HistoryView(
                    store: container.localStore,
                    authService: container.authService,
                    sessionStore: container.sessionStore,
                    sync: container.syncController,
                    connectivity: container.connectivity,
                    refreshSignal: vm.runningTimer?.activityText ?? "",
                    logTimeActive: $isHistoryLogTimeActive
                )
                    .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            }
            .tabItem { Label(L10n.tabHistory.text, systemImage: "clock.arrow.circlepath") }
            .tag(AppShellViewModel.Tab.history)
            .accessibilityIdentifier("TabHistory")

            navigationRoot {
                InsightsView(
                    store: container.localStore,
                    refreshSignal: vm.runningTimer?.activityText ?? ""
                )
                .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            }
            .tabItem { Label(L10n.tabInsights.text, systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppShellViewModel.Tab.insights)
            .accessibilityIdentifier("TabInsights")
        }
        .tint(Theme.accentPrimary)
        .sheet(isPresented: $isShowingProfile, onDismiss: {
            // A category created in Profile must be toggleable immediately.
            Task { await trackVM.load() }
        }, content: {
            ProfileView(enableSync: EnableSyncPresenter(
                authService: container.authService,
                sessionStore: container.sessionStore
            ))
            .environmentObject(container)
        })
        .task { await vm.load() }
        // TabView keeps mounted tabs alive, so Track's own `.task` runs only
        // on first appear: refresh recents + categories on every return, so
        // History edits are inherited and chip icons stay current.
        // `dropFirst` skips the initial value (already covered by `.task`).
        .onReceive(vm.$selectedTab.dropFirst().filter { $0 == .track }) { _ in
            Task { await trackVM.load() }
        }
    }

    @ViewBuilder
    private func navigationRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationView {
            content()
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(ShellToolbar(
                    showsLogTime: vm.selectedTab == .history,
                    onLogTime: { isHistoryLogTimeActive = true },
                    onProfile: { isShowingProfile = true }
                ))
        }
        .navigationViewStyle(.stack)
    }

    private var navigationTitle: String {
        switch vm.selectedTab {
        case .track: L10n.tabTrack.text
        case .history: L10n.tabHistory.text
        case .insights: L10n.tabInsights.text
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
/// One scope (never nested child scopes) so the bar renders identically on
/// every supported iOS version. The `if/else` lives at the View level —
/// `if` directly inside `.toolbar {}` needs iOS 16 — with the [+] branch
/// duplicating the Profile item.
private struct ShellToolbar: ViewModifier {
    let showsLogTime: Bool
    let onLogTime: () -> Void
    let onProfile: () -> Void

    func body(content: Content) -> some View {
        if showsLogTime {
            content.toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onLogTime) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.historyLogTime.text)
                    .accessibilityIdentifier("HistoryLogTimeButton")
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
        } else {
            content.toolbar {
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
}
#if DEBUG
#Preview("App Shell") {
    let container = AppContainer.production()
    AppShellView(vm: AppShellViewModel(service: container.timerService), container: container)
        .environmentObject(container)
}
#endif
