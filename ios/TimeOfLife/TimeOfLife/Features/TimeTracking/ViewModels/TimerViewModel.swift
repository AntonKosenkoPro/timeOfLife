import Foundation
import SwiftUI
import Combine

/// View model for the time-tracking timer screen.
///
/// Owns the running timer state, validates the activity name, and delegates
/// persistence to `TimerService` (which writes only to the local database).
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
    private var activityID: String?
    private var timerCancellable: AnyCancellable?

    init(service: TimerService, authService: AuthService, connectivity: Connectivity) {
        self.service = service
        self.authService = authService
        self.connectivity = connectivity
    }

    /// Starts the timer if the activity name is valid. Persists the running
    /// state so it survives a crash and is readable by widgets/Controls.
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
        Task {
            do {
                try await service.startTimer(
                    activityName: activityName.trimmingCharacters(in: .whitespacesAndNewlines),
                    startedAt: startDate ?? Date()
                )
                activityID = try await service.store.activity(named: activityName.trimmingCharacters(in: .whitespacesAndNewlines))?.id
            } catch {
                // Local persistence failure: surface it but keep the timer
                // running in memory so the user can still stop and retry.
                fieldError = L10n.text(in: .default, code: "error.unknown")
            }
        }
    }

    /// Stops the timer and saves the completed entry locally.
    func stop() async {
        guard isRunning, let startDate else { return }
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        UIApplication.shared.isIdleTimerDisabled = false

        isLoading = true
        defer { isLoading = false }

        do {
            try await service.stopTimer(
                activityID: activityID ?? UUID().uuidString.lowercased(),
                activityName: activityName.trimmingCharacters(in: .whitespacesAndNewlines),
                startedAt: startDate,
                endedAt: Date()
            )
            didSave = true
            reset()
            Haptics.success()
        } catch {
            Haptics.error()
            fieldError = L10n.text(in: .default, code: "error.unknown")
        }
    }

    /// Resets the form and timer state.
    func reset() {
        activityName = ""
        fieldError = nil
        elapsed = 0
        isRunning = false
        startDate = nil
        activityID = nil
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
