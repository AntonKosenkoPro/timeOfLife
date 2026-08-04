import Testing
import Foundation
@testable import TimeOfLife

@Suite("Seeder")
@MainActor
struct SeederTests {

    private func makeStore() throws -> LocalStore {
        try LocalStore(inMemory: true)
    }

    @Test("seedIfNeeded inserts seven categories when empty")
    func seedsSevenWhenEmpty() async throws {
        let store = try makeStore()
        let seeder = Seeder(localStore: store, syncCoordinator: nil)

        let didSeed = await seeder.seedIfNeeded()
        #expect(didSeed)

        let categories = try await store.categoriesSortedByName()
        #expect(categories.count == 7)

        // The seed decision is recorded.
        let decision = try await store.metadataValue(forKey: Seeder.seedDecisionKey)
        #expect(decision == "true")
    }

    @Test("seedIfNeeded is idempotent — does not duplicate on second run")
    func idempotentOnSecondRun() async throws {
        let store = try makeStore()
        let seeder = Seeder(localStore: store, syncCoordinator: nil)

        _ = await seeder.seedIfNeeded()
        let categoriesAfterFirst = try await store.categoriesSortedByName()
        #expect(categoriesAfterFirst.count == 7)

        let didSeedAgain = await seeder.seedIfNeeded()
        #expect(!didSeedAgain)

        let categoriesAfterSecond = try await store.categoriesSortedByName()
        #expect(categoriesAfterSecond.count == 7)
    }

    @Test("seedIfNeeded does not seed when categories already exist")
    func doesNotSeedWhenNonEmpty() async throws {
        let store = try makeStore()
        // Insert a user category first.
        let userCategory = CatalogTestFactory.makeCategory(
            id: "user-1", name: "Custom", icon: "star", sync: .newPending())
        try await store.upsertCategory(userCategory)

        let seeder = Seeder(localStore: store, syncCoordinator: nil)
        let didSeed = await seeder.seedIfNeeded()
        #expect(!didSeed)

        let categories = try await store.categoriesSortedByName()
        #expect(categories.count == 1)
        #expect(categories.first?.name == "Custom")
    }

    @Test("seed categories have the seven approved icons")
    func seedIconsMatchSpec() {
        let seeds = Seeder.seedCategories()
        #expect(seeds.count == 7)
        let icons = seeds.map(\.icon)
        #expect(
            icons == [
                "briefcase", "paintbrush", "figure.run", "book",
                "cup.and.saucer", "bed.double", "tv",
            ])
    }

    @Test("seed categories use deterministic ids for idempotency")
    func seedIdsAreDeterministic() {
        let seeds1 = Seeder.seedCategories()
        let seeds2 = Seeder.seedCategories()
        #expect(seeds1.map(\.id) == seeds2.map(\.id))
    }

    @Test("interrupted bootstrap remains retryable — decision not set until after inserts")
    func interruptedBootstrapRetryable() async throws {
        let store = try makeStore()
        // Simulate an interrupted bootstrap: insert some seeds but don't set
        // the decision flag.
        let seeds = Seeder.seedCategories()
        for category in seeds.prefix(3) {
            try await store.upsertCategory(category)
        }
        // Decision is NOT set.
        let decision = try await store.metadataValue(forKey: Seeder.seedDecisionKey)
        #expect(decision == nil)

        // On re-run, the seeder sees 3 categories (non-empty) and marks the
        // decision without duplicating.
        let seeder = Seeder(localStore: store, syncCoordinator: nil)
        let didSeed = await seeder.seedIfNeeded()
        #expect(!didSeed)

        let categories = try await store.categoriesSortedByName()
        #expect(categories.count == 3)
        let decisionAfter = try await store.metadataValue(forKey: Seeder.seedDecisionKey)
        #expect(decisionAfter == "true")
    }

    @Test("hasSeeded returns false before seeding and true after")
    func hasSeededFlag() async throws {
        let store = try makeStore()
        let seeder = Seeder(localStore: store, syncCoordinator: nil)

        let before = await seeder.hasSeeded()
        #expect(!before)

        _ = await seeder.seedIfNeeded()
        let after = await seeder.hasSeeded()
        #expect(after)
    }

    @Test("CatalogIcon allowedSymbols contains all seed icons")
    func seedIconsAreAllowed() {
        for icon in CatalogIcon.seedIcons {
            #expect(CatalogIcon.allowedSymbols.contains(icon), "Seed icon \(icon) not in allowed set")
        }
    }

    @Test("CatalogIcon allowedSymbols has no duplicates")
    func allowedSymbolsNoDuplicates() {
        let symbols = CatalogIcon.allowedSymbols
        #expect(Set(symbols).count == symbols.count)
    }
}
