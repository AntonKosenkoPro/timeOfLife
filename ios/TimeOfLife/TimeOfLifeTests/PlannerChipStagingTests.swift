import Testing
import Foundation
@testable import TimeOfLife

/// Composer chip staging (day-planner 16.2): each chip shows its Recent's
/// first category icon, tapping stages the full set for the created task,
/// the line shows only the selected chip until typing resumes, the staged
/// set survives typing until the draft clears or another chip is tapped,
/// and submit creates the task with the staged set. Split from
/// `PlannerViewModelTests` (file-length rule).
@MainActor
@Suite("Planner chip staging (day-planner 16.2)")
struct PlannerChipStagingTests {
    @Test("a tap stages the full set and narrows the line to the selected chip")
    func tapStagesAndNarrows() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "gym"
        #expect(vm.chips.map(\.activityText) == ["Gymnastics", "Gym"])
        let selected = try #require(vm.chips.last)
        vm.fillFromChip(selected)
        #expect(vm.draft == "Gym")
        #expect(vm.stagedChip == StagedChip(text: "Gym", categoryIDs: ["c1", "c2"]))
        // Selected-only display: the longer prefix match hides until typing
        // resumes — no task created, no timer started.
        #expect(vm.chips.map(\.activityText) == ["Gym"])
        #expect(vm.snapshot.total == 0)
    }

    @Test("typing after a tap resumes filtering but keeps the staged set")
    func typingResumesFilterKeepsStaged() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.fillFromChip(try #require(vm.chips.first { $0.activityText == "Gym" }))
        vm.draft = "Gymn"
        // The display filters again, but staging survives the keystrokes.
        #expect(vm.chips.map(\.activityText) == ["Gymnastics"])
        #expect(vm.showsChipsNoMatch == false)
        #expect(vm.stagedChip == StagedChip(text: "Gym", categoryIDs: ["c1", "c2"]))
        // A draft matching nothing raises the placeholder while staged.
        vm.draft = "Gym xyz"
        #expect(vm.chips.isEmpty)
        #expect(vm.showsChipsNoMatch)
        #expect(vm.stagedChip?.categoryIDs == ["c1", "c2"])
    }

    @Test("submit creates the task with the staged set and clears staging")
    func submitCarriesStagedSet() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        vm.fillFromChip(try #require(vm.chips.first { $0.activityText == "Gym" }))
        await vm.submit()
        let task = try #require(vm.snapshot.tasks.first)
        #expect(task.name == "Gym")
        #expect(task.categoryIDs == ["c1", "c2"])
        #expect(try await store.plannerTask(id: task.id)?.categoryIDs == ["c1", "c2"])
        // The create row carries the initial set (the relay reads optional
        // `category_ids` on create — no wire change).
        let payloads = try await store.outboxRows().compactMap { row -> PlannerOperationPayload? in
            guard let data = row.payload?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(PlannerOperationPayload.self, from: data)
        }
        let payload = try #require(payloads.first { $0.intent == PlannerIntent.create.rawValue })
        #expect(payload.categoryIDs == ["c1", "c2"])
        // Submit clears the draft, and the clear drops the staged set: the
        // line falls back to the full capped strip.
        #expect(vm.draft.isEmpty)
        #expect(vm.stagedChip == nil)
        #expect(vm.chips.map(\.activityText) == ["Gymnastics", "Gym"])
    }

    @Test("clearing the draft clears the staged set")
    func clearDraftClearsStaged() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.fillFromChip(try #require(vm.chips.first { $0.activityText == "Gym" }))
        #expect(vm.stagedChip != nil)
        vm.draft = ""
        #expect(vm.stagedChip == nil)
        #expect(vm.chips.map(\.activityText) == ["Gymnastics", "Gym"])
    }

    @Test("a second tap replaces the staged set")
    func retapReplacesStaged() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        vm.fillFromChip(try #require(vm.chips.first { $0.activityText == "Gym" }))
        #expect(vm.stagedChip?.categoryIDs == ["c1", "c2"])
        // Typing resumes filtering (the staged set survives), and tapping
        // another chip replaces it.
        vm.draft = "gym"
        #expect(vm.chips.map(\.activityText) == ["Gymnastics", "Gym"])
        vm.fillFromChip(try #require(vm.chips.first { $0.activityText == "Gymnastics" }))
        #expect(vm.stagedChip == StagedChip(text: "Gymnastics", categoryIDs: []))
        await vm.submit()
        #expect(vm.snapshot.tasks.first?.categoryIDs.isEmpty == true)
    }

    @Test("submit without a tap carries no categories")
    func untappedSubmitStaysBare() async throws {
        let (vm, store) = await makeContext()
        await vm.loadIfNeeded()
        vm.draft = "Plain"
        await vm.submit()
        #expect(vm.snapshot.tasks.first?.categoryIDs.isEmpty == true)
        let payloads = try await store.outboxRows().compactMap { row -> PlannerOperationPayload? in
            guard let data = row.payload?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(PlannerOperationPayload.self, from: data)
        }
        let payload = try #require(payloads.first { $0.intent == PlannerIntent.create.rawValue })
        // The pre-16.2 wire shape is unchanged for untapped submits.
        #expect(payload.categoryIDs == nil)
    }

    @Test("chip icons resolve the first category or nothing")
    func chipIconResolution() async throws {
        let (vm, _) = await makeContext()
        await vm.loadIfNeeded()
        let tagged = try #require(vm.chips.first { $0.activityText == "Gym" })
        #expect(vm.chipIconSymbol(for: tagged) == CatalogIcon.tag.displaySymbol)
        let bare = try #require(vm.chips.first { $0.activityText == "Gymnastics" })
        #expect(vm.chipIconSymbol(for: bare) == nil)
        let unknown = RecentEntry(activityText: "Ghost", categoryIDs: ["missing"], startedAt: Date())
        #expect(vm.chipIconSymbol(for: unknown) == nil)
    }

    // MARK: - Helpers

    private func makeContext() async -> (vm: PlannerViewModel, store: LocalStore) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        for (id, name) in [("c1", "Work"), ("c2", "Gym")] {
            _ = try? await store.createCategory(Category(id: id, name: name, icon: CatalogIcon.tag.rawValue))
        }
        // Newest-first pool: "Gymnastics" (bare) sorts before "Gym"
        // (tagged c1 + c2), so the "gym" prefix matches both.
        _ = try? await store.createEntry(TimeEntry(
            id: "e1", activityText: "Gym",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600), durationSeconds: 600,
            categoryIDs: ["c1", "c2"]
        ))
        _ = try? await store.createEntry(TimeEntry(
            id: "e2", activityText: "Gymnastics",
            startedAt: Date(timeIntervalSinceReferenceDate: 2_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 2_600), durationSeconds: 600
        ))
        let vm = PlannerViewModel(
            store: store,
            undoBuffer: UndoBufferStore(store: store),
            timer: TimerService(store: store)
        )
        return (vm, store)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "planner-staging"))
    }
}
