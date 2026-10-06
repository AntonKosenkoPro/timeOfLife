import Foundation
import Combine

/// One push on a tab's navigation path (per-tab-navigation-paths).
///
/// `profile` opens the Profile page on the tab that pushed it; `entry`
/// carries the tapped History entry snapshot for the pushed unified entry
/// form (EDIT for `manual`, LOCKED for imported — resolved at the
/// destination, so the snapshot never changes spec behavior). NamePicker
/// pushes stay caller-local `NavigationLink`s on purpose: they complete
/// through caller-owned closures over live view-model state, which a value
/// route cannot carry — and they are already per-tab, so they need no
/// path to stay independent. Every case hides the tab bar at the
/// destination (app-shell "Tab bar hidden on pushed destinations").
enum ShellRoute: Hashable {
    case profile
    case entry(TimeEntry)
}

/// View model for the app shell (app-shell spec): owns the selected
/// destination and observes the persisted running draft so History and
/// Insights can show the compact timer.
@MainActor
final class AppShellViewModel: ObservableObject {
    enum Tab: Hashable {
        case track
        case history
        case insights
    }

    @Published var selectedTab: Tab = .track
    @Published private(set) var runningTimer: RunningTimerDraft?
    /// One independent push state per tab (per-tab-navigation-paths): opening
    /// Profile (or a History entry) on one tab never pre-pushes it on the
    /// others. Each tab's `NavigationStack(path:)` binds to its own path.
    @Published var trackPath: [ShellRoute] = []
    @Published var historyPath: [ShellRoute] = []
    @Published var insightsPath: [ShellRoute] = []

    let service: TimerService
    private var ticker: AnyCancellable?

    init(service: TimerService) {
        self.service = service
    }

    /// Pushes Profile onto the selected tab's own path. A no-op when Profile
    /// is already on that path (the toolbar button is unreachable while
    /// pushed — the tab bar hides — so this guards programmatic double-taps).
    func openProfile() {
        switch selectedTab {
        case .track:
            if !trackPath.contains(.profile) { trackPath.append(.profile) }
        case .history:
            if !historyPath.contains(.profile) { historyPath.append(.profile) }
        case .insights:
            if !insightsPath.contains(.profile) { insightsPath.append(.profile) }
        }
    }

    /// Whether a path transition popped Profile (was present, now absent).
    /// Pushes to Categories (a caller-local link, not a path value) never
    /// touch the path, so this fires once-on-exit only — never for
    /// Categories/editor traffic.
    static func profileWasPopped(old: [ShellRoute], new: [ShellRoute]) -> Bool {
        old.contains(.profile) && !new.contains(.profile)
    }

    /// Loads the persisted running draft (R2) and starts a periodic refresh so
    /// the compact timer stays live. Call on appear.
    func load() async {
        do {
            runningTimer = try await service.runningTimerDraft()
        } catch {
            runningTimer = nil
        }
        startTicker()
    }

    /// Stops the running timer from the compact surface, saving the entry
    /// with the draft's final categories in place (app-shell spec: keeps the
    /// current destination selected).
    func stopFromCompact() async {
        guard let running = runningTimer,
              !running.activityText.isEmpty,
              let startedAt = running.startedAt else { return }
        do {
            try await service.stopTimerDraft(
                text: running.activityText,
                categoryIDs: running.categoryIDs,
                startedAt: startedAt,
                endedAt: Date()
            )
            runningTimer = nil
        } catch {
            // Recoverable: keep the compact timer so the user can retry.
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.runningTimer = try? await self.service.runningTimerDraft()
                }
            }
    }
}
