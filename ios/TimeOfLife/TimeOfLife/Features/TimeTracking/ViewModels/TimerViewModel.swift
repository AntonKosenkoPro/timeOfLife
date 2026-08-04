import Foundation
import SwiftUI
import Combine

/// View model for the time-tracking timer screen.
///
/// Owns the running timer state, manages free-text activity auto-creation,
/// suggestion ranking, and delegates persistence to `TimerService`.
@MainActor
final class TimerViewModel: ObservableObject {
    @Published var activityName: String = ""
    @Published var fieldError: String?
    @Published var isLoading = false
    @Published var elapsed: TimeInterval = 0
    @Published var isRunning = false
    @Published var didSave = false
    @Published var suggestions: [Activity] = []
    @Published var selectedActivityId: String?
    @Published var isQuickAddPresented = false

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

    /// Loads suggestions from the local store (top 5 by `last_used_at`).
    func loadSuggestions() async {
        do {
            suggestions = try await service.suggestions()
        } catch {
            suggestions = []
        }
    }

    /// Refreshes suggestions when the activity name changes (prefix matching,
    /// idle only).
    func refreshSuggestions() async {
        guard !isRunning else { return }
        await loadSuggestions()
    }

    /// Selects a suggestion: prefills the activity name and sets the
    /// `selectedActivityId`.
    func selectSuggestion(_ activity: Activity) {
        activityName = activity.name
        selectedActivityId = activity.id
        fieldError = nil
    }

    /// Starts the timer if the activity name is valid. Auto-creates or reuses
    /// an activity from the typed name (F4 / D20).
    func start() async {
        guard validate() else {
            Haptics.error()
            return
        }

        // Auto-create or reuse the activity (F4 / D20).
        do {
            let activity = try await service.resolveActivity(
                name: activityName,
                selectedActivityId: selectedActivityId)
            selectedActivityId = activity.id
        } catch {
            Haptics.error()
            fieldError = L10n.text(in: .default, code: "error.unknown")
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

        // Bump local recency immediately at timer start; no activity PATCH
        // sent solely for last_used_at (server updates recency on entry POST).
        if let id = selectedActivityId {
            try? await service.bumpRecencyLocally(activityId: id)
            await loadSuggestions()
        }

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
            guard let activityId = selectedActivityId else {
                fieldError = L10n.text(in: .default, code: "error.unknown")
                Haptics.error()
                return
            }
            try await service.saveEntry(
                activityId: activityId,
                duration: duration,
                startedAt: startDate)
            didSave = true
            reset()
            await loadSuggestions()
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
        selectedActivityId = nil
        timerCancellable?.cancel()
        timerCancellable = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Signs the user out. Works offline by clearing local session state.
    func signOut() async {
        await authService.logout()
    }

    /// Called when the quick-add sheet saves a new activity — selects it on
    /// the timer.
    func didSelectNewActivity(_ activity: Activity) {
        activityName = activity.name
        selectedActivityId = activity.id
        fieldError = nil
        Task { await loadSuggestions() }
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
