import Foundation
import Testing
@testable import TimeOfLife

@MainActor
@Suite("CatalogSeeder")
struct CatalogSeederTests {
    @Test("first run creates seven English categories and sets the flag")
    func seedsEnglishCategories() async {
        let (seeder, repository, cache) = make(locale: "en")

        await seeder.seedIfNeeded()

        let creates = repository.calls.compactMap { call -> Category? in
            guard case let .createCategory(category) = call else { return nil }
            return category
        }
        #expect(creates.count == 7)
        #expect(creates.map(\.name) == ["Work", "Hobby", "Sport", "Education", "Relax", "Sleep", "Entertainment"])
        #expect(creates.map(\.icon) == [.briefcase, .paintbrush, .figureRun, .book, .cupAndSaucer, .bedDouble, .tv])
        #expect(cache.categoriesSeeded(for: Self.userId))
    }

    @Test("a seeded flag makes relaunch idempotent")
    func flagGatesSecondRun() async {
        let (seeder, repository, cache) = make(locale: "en")
        cache.setCategoriesSeeded(true, for: Self.userId)

        await seeder.seedIfNeeded()

        #expect(repository.calls.isEmpty)
    }

    @Test("Russian locale resolves Russian seed names")
    func seedsRussianNames() async {
        let (seeder, repository, _) = make(locale: "ru")

        await seeder.seedIfNeeded()

        let names = repository.calls.compactMap { call -> String? in
            guard case let .createCategory(category) = call else { return nil }
            return category.name
        }
        #expect(names == ["Работа", "Хобби", "Спорт", "Образование", "Отдых", "Сон", "Развлечения"])
    }

    @Test("a category collision is treated as a successful seed")
    func collisionIsSuccess() async {
        let (seeder, repository, cache) = make(locale: "en")
        repository.createCategoryError = CatalogError.categoryExists(
            existingId: UUID.v7(), existingName: "Work"
        )

        await seeder.seedIfNeeded()

        #expect(cache.categoriesSeeded(for: Self.userId))
    }

    @Test("an offline request stays queued and completes seeding locally")
    func offlineRequestIsQueued() async {
        let (seeder, repository, cache) = make(locale: "en")
        repository.createCategoryError = CatalogError.offline

        await seeder.seedIfNeeded()

        #expect(cache.categoriesSeeded(for: Self.userId))
        #expect(repository.calls.count == 7)
    }

    @Test("a transient mid-seed failure does not abandon remaining categories")
    func midSeedFailureContinues() async {
        let (seeder, repository, cache) = make(locale: "en")
        repository.createCategoryErrors = [nil, CatalogError.offline]

        await seeder.seedIfNeeded()

        #expect(cache.categoriesSeeded(for: Self.userId))
        #expect(repository.calls.count == 8) // Seven seeds plus one queued retry.
    }

    @Test("unknown locales fall back to English seed names")
    func unknownLocaleUsesEnglish() async {
        let (seeder, repository, _) = make(locale: "fr")

        await seeder.seedIfNeeded()

        let firstName: String? = repository.calls.compactMap { call in
            guard case let .createCategory(category) = call else { return nil }
            return category.name
        }.first
        #expect(firstName == "Work")
    }

    private func make(locale: String) -> (CatalogSeeder, FakeCatalogRepository, SessionCache) {
        let suite = "CatalogSeederTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let cache = SessionCache(defaults: defaults)
        cache.save(CachedSession(id: Self.userId, email: "test@example.com", emailVerified: true))
        let store = MockCatalogStore()
        let repository = FakeCatalogRepository()
        let queue = SyncQueue(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TimeOfLife-")
                .appendingPathComponent(UUID().uuidString)
        )
        let undoBuffer = UndoBuffer(scheduler: .manual)
        let connectivity = MockConnectivity(connected: true)
        let service = CatalogService(
            store: store,
            repository: repository,
            syncQueue: queue,
            undoBuffer: undoBuffer,
            connectivity: connectivity
        )
        let seeder = CatalogSeeder(
            repository: repository,
            service: service,
            sessionCache: cache,
            locale: Locale(identifier: locale)
        )
        return (seeder, repository, cache)
    }

    private static let userId = "user-id"
}
