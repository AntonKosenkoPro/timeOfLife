import SwiftUI

/// The app shell (app-shell spec): Track, History, and Insights as primary
/// destinations, with Profile opened from a consistent top-trailing person
/// control. A running timer stays visible and stoppable on History and
/// Insights through the compact timer.
struct AppShellView: View {
    @ObservedObject var vm: AppShellViewModel
    @EnvironmentObject var container: AppContainer
    @StateObject private var trackVM: TrackViewModel
    @State private var isShowingProfile = false

    init(vm: AppShellViewModel, container: AppContainer) {
        self.vm = vm
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
                DestinationPlaceholder(
                    title: L10n.tabHistory.text,
                    symbol: "clock.arrow.circlepath",
                    emptyTitle: L10n.historyEmptyTitle.text,
                    emptySubtitle: L10n.historyEmptySubtitle.text
                )
                .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            }
            .tabItem { Label(L10n.tabHistory.text, systemImage: "clock.arrow.circlepath") }
            .tag(AppShellViewModel.Tab.history)
            .accessibilityIdentifier("TabHistory")

            navigationRoot {
                DestinationPlaceholder(
                    title: L10n.tabInsights.text,
                    symbol: "chart.line.uptrend.xyaxis",
                    emptyTitle: L10n.insightsEmptyTitle.text,
                    emptySubtitle: L10n.insightsEmptySubtitle.text
                )
                .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            }
            .tabItem { Label(L10n.tabInsights.text, systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppShellViewModel.Tab.insights)
            .accessibilityIdentifier("TabInsights")
        }
        .tint(Theme.accentPrimary)
        .sheet(isPresented: $isShowingProfile) {
            ProfileView()
                .environmentObject(container)
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func navigationRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationView {
            content()
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isShowingProfile = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 19, weight: .regular))
                        }
                        .accessibilityLabel(L10n.profileTitle.text)
                        .accessibilityIdentifier("ProfileButton")
                    }
                }
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
           let activityID = running.activityID,
           let startedAt = running.startedAt {
            CompactTimer(
                activityName: running.activityName ?? "",
                startedAt: startedAt,
                openTrack: {
                    vm.selectedTab = .track
                },
                stop: {
                    Task { await vm.stopFromCompact() }
                }
            )
            .accessibilityIdentifier("CompactTimer(\(activityID))")
        }
    }
}

/// Honest empty state for History and Insights (app-shell spec: do not fill
/// destinations with fake data in production).
private struct DestinationPlaceholder: View {
    let title: String
    let symbol: String
    let emptyTitle: String
    let emptySubtitle: String

    var body: some View {
        EmptyState(icon: symbol, title: emptyTitle, subtitle: emptySubtitle)
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .accessibilityLabel("\(title), \(emptyTitle). \(emptySubtitle)")
    }
}

#if DEBUG
#Preview("App Shell") {
    let container = AppContainer.production()
    AppShellView(vm: AppShellViewModel(service: container.timerService), container: container)
        .environmentObject(container)
}
#endif
