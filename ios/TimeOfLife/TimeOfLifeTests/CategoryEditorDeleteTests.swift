import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("CategoryEditorViewModel Delete (unify-catalog-deletion)")
struct CategoryEditorDeleteTests {

    @Test("editor deleteConfirmed removes the category and returns true")
    func editorDeleteRemovesCategory() async throws {
        let store = try makeStore()
        try await store.createCategory(draft: CategoryDraft(name: "Work", icon: .briefcase), id: "c1", now: Date())
        let category = try #require(await store.category(id: "c1"))
        let vm = CategoryEditorViewModel(store: store, category: category, onSaved: { _ in }, onDuplicate: { _ in })

        let shouldDismiss = await vm.deleteConfirmed()

        #expect(shouldDismiss)
        #expect(try await store.category(id: "c1") == nil)
        // Buffered, not synced.
        #expect(try await store.undoBufferMostRecent() != nil)
        let rows = try await store.outboxRows()
        #expect(rows.allSatisfy { $0.op != "delete" })
    }

    @Test("editor deleteConfirmed on an already-gone category returns true")
    func editorDeleteMissingDismisses() async throws {
        let store = try makeStore()
        let vm = CategoryEditorViewModel(
            store: store,
            category: TimeOfLife.Category(id: "gone", name: "Gone", icon: "tag"),
            onSaved: { _ in },
            onDuplicate: { _ in }
        )

        #expect(await vm.deleteConfirmed())
    }

    @Test("create mode has nothing to delete")
    func createModeDeleteReturnsFalse() async throws {
        let store = try makeStore()
        let vm = CategoryEditorViewModel(store: store, category: nil, onSaved: { _ in }, onDuplicate: { _ in })

        #expect(await vm.deleteConfirmed() == false)
    }

    // MARK: - Helpers

    private func makeStore() throws -> LocalStore {
        try LocalStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeoflife.sqlite"))
    }
}
