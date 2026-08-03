import Foundation
import SwiftUI
import Combine

/// View model for the time-tracking timer screen.
///
/// Owns the running timer state, validates the activity name, and delegates
/// persistence to `TimerService`.
@MainActor
final class TimerViewModel: ObservableObject {
    @Published var activityName: String = ""
    @Published var fieldError: String?
    @Published var isLoading = false
    @Published var elapsed: TimeInterval = 0
    @Published var isRunning = false
    @Published var didSave = false

    let service: TimerService
    let authService: AuthService
    private let connectivity: Connectivity
    private var startDate: Date?
    private var timerCancellable: AnyCancellable?

    init(service: TimerService, authService: AuthService, connectivity: Connectivity) {
        self.service = service
        self.authService = authService
        self.connectivity = connectivity
    }

    /// Starts the timer if the activity name is valid.
    func start() {
        guard validate() else {
            Haptics.error()
            return
        }
        isRunning = true
        didSave = false
        startDate = Date()
        elapsed = 0
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
        UIApplication.shared.isIdleTimerDisabled = true
        Haptics.selection()
    }

    /// Stops the timer and saves the completed entry.
    func stop() async {
        guard isRunning, let startDate else { return }
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        UIApplication.shared.isIdleTimerDisabled = false

        let duration = Date().timeIntervalSince(startDate)
        isLoading = true
        defer { isLoading = false }

        do {
            try await service.saveEntry(name: activityName, duration: duration, startedAt: startDate)
            didSave = true
            reset()
            Haptics.success()
        } catch {
            Haptics.error()
            fieldError = connectivity.isConnected
                ? L10n.text(in: .default, code: "error.unknown")
                : L10n.text(in: .default, code: "error.offline")
        }
    }

    /// Resets the form and timer state.
    func reset() {
        activityName = ""
        fieldError = nil
        elapsed = 0
        isRunning = false
        startDate = nil
        timerCancellable?.cancel()
        timerCancellable = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Signs the user out. Works offline by clearing local session state.
    func signOut() async {
        await authService.logout()
    }

    private func tick() {
        guard let startDate else { return }
        elapsed = Date().timeIntervalSince(startDate)
    }

    private func validate() -> Bool {
        let name = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            fieldError = L10n.timerEmptyActivityError.text
            return false
        }
        fieldError = nil
        return true
    }
}
