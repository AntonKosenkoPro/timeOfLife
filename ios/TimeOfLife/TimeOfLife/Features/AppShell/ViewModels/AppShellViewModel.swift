import Foundation
import Combine

/// View model for the app shell (app-shell spec): owns the selected
/// destination and observes the persisted running timer so History and
/// Insights can show the compact timer.
@MainActor
final class AppShellViewModel: ObservableObject {
    enum Tab: Hashable {
        case track
        case history
        case insights
    }

    @Published var selectedTab: Tab = .track
    @Published private(set) var runningTimer: RunningTimerState?

    let service: TimerService
    private var ticker: AnyCancellable?

    init(service: TimerService) {
        self.service = service
    }

    /// Loads the persisted running timer (R2) and starts a periodic refresh so
    /// the compact timer stays live. Call on appear.
    func load() async {
        do {
            runningTimer = try await service.runningTimerState()
        } catch {
            runningTimer = nil
        }
        startTicker()
    }

    /// Stops the running timer from the compact surface, saving the entry in
    /// place (app-shell spec: keeps the current destination selected).
    func stopFromCompact() async {
        guard let running = runningTimer,
              let activityID = running.activityID,
              let startedAt = running.startedAt else { return }
        do {
            try await service.stopTimer(activityID: activityID, startedAt: startedAt, endedAt: Date())
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
                    self.runningTimer = try? await self.service.runningTimerState()
                }
            }
    }
}
