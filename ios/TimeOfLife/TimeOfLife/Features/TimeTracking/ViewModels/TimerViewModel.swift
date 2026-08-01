import Foundation
import SwiftUI
import Combine

/// View model for the time-tracking timer screen.
///
/// Owns the running timer state, validates the activity name, and delegates
/// persistence to `TimerService`. Integrates with the activity catalog for
/// recency-based suggestions, quick-add, and auto-create.
@MainActor
final class TimerViewModel: ObservableObject {
    @Published var activityName: String = "" {
        didSet {
            guard let selectedActivityId else { return }
            guard let selected = knownActivities.first(where: { $0.id == selectedActivityId }) else {
                self.selectedActivityId = nil
                return
            }
            if CatalogValidator.normalizeName(activityName) != CatalogValidator.normalizeName(selected.name) {
                self.selectedActivityId = nil
            }
        }
    }
    @Published var fieldError: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var elapsed: TimeInterval = 0
    @Published var isRunning = false
    @Published var didSave = false
    @Published var suggestions: [Activity] = []
    @Published var selectedActivityId: UUID?
    @Published var showQuickAdd = false
    @Published var isActivityFocused = false

    let service: TimerService
    let authService: AuthService
    let catalogStore: CatalogStore
    let catalogService: CatalogService
    private let connectivity: Connectivity
    private var startDate: Date?
    private var timerCancellable: AnyCancellable?
    private var storeCancellable: AnyCancellable?
    private var knownActivities: [Activity] = []

    /// Whether suggestions should be shown: field is focused, not running,
    /// and the current text is empty or case-insensitively prefix-matches
    /// at least one existing activity.
    var shouldShowSuggestions: Bool {
        guard isActivityFocused, !isRunning, !suggestions.isEmpty else { return false }
        guard !activityName.isEmpty else { return true }
        let key = CatalogValidator.normalizeName(activityName)
        return knownActivities.contains { CatalogValidator.normalizeName($0.name).hasPrefix(key) }
    }

    init(
        service: TimerService,
        authService: AuthService,
        connectivity: Connectivity,
        catalogStore: CatalogStore,
        catalogService: CatalogService
    ) {
        self.service = service
        self.authService = authService
        self.connectivity = connectivity
        self.catalogStore = catalogStore
        self.catalogService = catalogService

        // Observe catalog store changes to keep suggestions fresh.
        storeCancellable = catalogService.$storeRevision
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshSuggestions() }
            }
    }

    /// Refreshes suggestions from the local catalog store.
    func refreshSuggestions() async {
        let activities = await catalogStore.activitiesSortedByLastUsedAt()
        knownActivities = activities
        suggestions = Array(activities.prefix(5))
    }

    /// Prefills the activity field from a suggestion.
    func prefill(from activity: Activity) {
        activityName = activity.name
        selectedActivityId = activity.id
        fieldError = nil
    }

    /// Opens the quick-add sheet (no-op while running).
    func openQuickAdd() {
        guard !isRunning else { return }
        showQuickAdd = true
    }

    /// Called when a new activity is created via the quick-add sheet.
    /// Persists the activity first so the entry POST does not 404.
    func didSelectNewActivity(_ activity: Activity) {
        showQuickAdd = false
        Task {
            do {
                let created = try await catalogService.createActivity(activity)
                prefill(from: created)
                await refreshSuggestions()
            } catch {
                errorMessage = localizedMessage(for: error)
            }
        }
    }

    /// Receives the shared activity editor's result without creating the
    /// activity a second time. The editor owns persistence; the timer only
    /// selects the returned activity for the upcoming entry.
    func didSelectActivity(_ activity: Activity) {
        showQuickAdd = false
        prefill(from: activity)
        Task { await refreshSuggestions() }
    }

    /// Starts the timer if the activity name is valid.
    /// Handles auto-create: reuses an existing activity by name or creates a new one.
    func start() async {
        guard validate() else {
            Haptics.error()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            selectedActivityId = try await resolveActivityId()
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
        } catch {
            Haptics.error()
            errorMessage = localizedMessage(for: error)
        }
    }

    /// Stops the timer and saves the completed entry.
    func stop() async {
        guard isRunning, let startDate, let selectedActivityId else { return }
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        UIApplication.shared.isIdleTimerDisabled = false

        let duration = Date().timeIntervalSince(startDate)
        isLoading = true
        defer { isLoading = false }

        do {
            try await service.saveEntry(
                activityId: selectedActivityId,
                duration: duration,
                startedAt: startDate
            )
            didSave = true
            reset()
            await refreshSuggestions()
            Haptics.success()
        } catch {
            Haptics.error()
            errorMessage = localizedMessage(for: error)
        }
    }

    /// Resolves the activity ID for the current entry.
    /// Uses `selectedActivityId` if set; otherwise reuses an existing activity
    /// by case-insensitive name, or auto-creates a new one. Bumps the
    /// resolved activity's `lastUsedAt` so suggestions reflect recency.
    func resolveActivityId() async throws -> UUID {
        let name = activityName.trimmingCharacters(in: .whitespacesAndNewlines)

        // If already linked to a suggestion/quick-add, use it directly.
        if let selectedActivityId {
            await bumpLastUsedAt(selectedActivityId)
            return selectedActivityId
        }

        // Try case-insensitive reuse.
        if let existing = await catalogService.caseInsensitiveReuse(named: name) {
            await bumpLastUsedAt(existing.id)
            return existing.id
        }

        // Auto-create a new activity with defaults (seeded with current
        // `lastUsedAt` so it ranks first in suggestions).
        let newActivity = Activity(
            id: UUID.v7(),
            name: name,
            color: .mint,
            icon: .clock,
            notes: nil,
            lastUsedAt: Date(),
            categoryIds: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        let created = try await catalogService.createActivity(newActivity)
        return created.id
    }

    private func bumpLastUsedAt(_ id: UUID) async {
        guard var activity = await catalogStore.activity(id) else { return }
        let now = Date()
        activity.lastUsedAt = now
        activity.updatedAt = now
        _ = try? await catalogService.updateActivity(activity)
    }

    private func localizedMessage(for error: Error) -> String {
        if let error = error as? CatalogError {
            return ErrorLocalization.message(for: error)
        }
        if let error = error as? APIError {
            return ErrorLocalization.message(for: error)
        }
        return L10n.text(in: .default, code: "error.unknown")
    }

    /// Resets the form and timer state.
    func reset() {
        activityName = ""
        fieldError = nil
        errorMessage = nil
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
        if let message = CatalogValidator.unifiedNameMessage(
            CatalogValidator.validateName(activityName)
        ) {
            fieldError = message
            return false
        }
        fieldError = nil
        return true
    }
}
