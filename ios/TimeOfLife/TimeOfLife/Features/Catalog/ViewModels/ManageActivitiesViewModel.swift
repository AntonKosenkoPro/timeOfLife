import Combine
import Foundation

struct UndoToastState: Equatable, Sendable {
    let message: String
    let startedAt: Date
}

enum ActivityDeleteScope: Sendable {
    case all
    case entryOnly
}

enum ActivityEditorSheetState: Identifiable, Equatable {
    case create
    case edit(Activity)

    var id: UUID {
        switch self {
        case .create: return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        case let .edit(activity): return activity.id
        }
    }
}

@MainActor
final class ManageActivitiesViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var categories: [Category] = []
    @Published var isLoading = false
    @Published var undoToast: UndoToastState?
    @Published var errorMessage: String?
    @Published var showDeleteScope = false {
        didSet {
            if !showDeleteScope { pendingDelete = nil }
        }
    }
    @Published var showDeleteConfirmation = false {
        didSet {
            if !showDeleteConfirmation { pendingDelete = nil }
        }
    }
    @Published var pendingDelete: Activity?
    @Published var editorSheet: ActivityEditorSheetState?

    private let store: CatalogStoring
    private let service: CatalogService
    private let repository: CatalogRepository
    private let undoBuffer: UndoBuffer
    private let entryCounter: ActivityEntryCounting
    private var entryCounts: [UUID: Int] = [:]
    private var toastTask: Task<Void, Never>?
    private var deleteRequestId: UUID?
    private var serviceCancellable: AnyCancellable?

    init(
        store: CatalogStoring,
        service: CatalogService,
        repository: CatalogRepository,
        undoBuffer: UndoBuffer,
        entryCounter: ActivityEntryCounting
    ) {
        self.store = store
        self.service = service
        self.repository = repository
        self.undoBuffer = undoBuffer
        self.entryCounter = entryCounter
        serviceCancellable = service.$storeRevision
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshConflict() }
            }
    }

    func load() async {
        isLoading = true
        activities = await store.activitiesSortedByLastUsedAt()
            .filter { !undoBuffer.heldIds.contains($0.id) }
        categories = await store.loadCategories()
        isLoading = false
    }

    func categories(for activity: Activity) -> [Category] {
        categories.filter { activity.categoryIds.contains($0.id) }
    }

    func create() {
        editorSheet = .create
    }

    func edit(_ activity: Activity) {
        editorSheet = .edit(activity)
    }

    func requestDelete(_ activity: Activity) async {
        guard pendingDelete == nil, deleteRequestId == nil else { return }
        let requestId = UUID()
        deleteRequestId = requestId
        let count = await entryCounter.entryCount(forActivityId: activity.id)
        guard deleteRequestId == requestId else { return }
        deleteRequestId = nil
        entryCounts[activity.id] = count
        pendingDelete = activity
        if count == 0 {
            showDeleteConfirmation = true
        } else {
            showDeleteScope = true
        }
    }

    func entryCount(for activity: Activity?) -> Int {
        guard let activity else { return 0 }
        return entryCounts[activity.id] ?? 0
    }

    func performDelete(_ activity: Activity, scope: ActivityDeleteScope) async {
        pendingDelete = nil
        showDeleteScope = false
        showDeleteConfirmation = false
        if scope == .all {
            activities.removeAll { $0.id == activity.id }
        }

        let count = entryCount(for: activity)
        let item: UndoableItem
        switch scope {
        case .all where count > 0:
            item = .activityWithEntries(activity)
        case .all:
            item = .activity(activity)
        case .entryOnly:
            let latest = await entryCounter.latestEntry(forActivityId: activity.id)
            guard let latest else { return }
            item = .entryOnly(latest)
        }
        undoBuffer.record(item)
        let message = scope == .entryOnly
            ? L10n.undoEntryDeleted.text
            : L10n.undoActivityDeleted.text
        undoToast = UndoToastState(message: message, startedAt: Date())
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.undoToast = nil
            }
        }
        errorMessage = nil
    }

    func performUndo() async {
        guard undoBuffer.state != .empty else { return }
        guard let restored = await service.undo() else {
            errorMessage = L10n.errorUndoFailed.text
            return
        }
        await load()
        toastTask?.cancel()
        toastTask = nil
        undoToast = nil
        if case .entryOnly = restored { return }
    }

    func dismissUndo() {
        toastTask?.cancel()
        toastTask = nil
        undoToast = nil
    }

    func onShake() {
        Task { await performUndo() }
    }

    private func refreshConflict() async {
        let conflictedIds = service.consumeActivityConflicts()
        guard !conflictedIds.isEmpty else { return }
        let updated = await store.activitiesSortedByLastUsedAt()
            .filter { !undoBuffer.heldIds.contains($0.id) }
        activities = updated
        if updated.contains(where: { conflictedIds.contains($0.id) }) {
            errorMessage = L10n.errorConflict.text
        }
    }
}
