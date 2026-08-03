import Foundation

@MainActor
final class CatalogSeeder {
    struct Seed: Sendable {
        let key: String
        let icon: CatalogIcon
        let id: UUID
    }

    static let seeds: [Seed] = [
        Seed(key: "category.seed.work", icon: .briefcase, id: UUID(uuidString: "018f0000-0000-7000-8000-000000000001")!),
        Seed(key: "category.seed.hobby", icon: .paintbrush, id: UUID(uuidString: "018f0000-0000-7000-8000-000000000002")!),
        Seed(key: "category.seed.sport", icon: .figureRun, id: UUID(uuidString: "018f0000-0000-7000-8000-000000000003")!),
        Seed(key: "category.seed.education", icon: .book, id: UUID(uuidString: "018f0000-0000-7000-8000-000000000004")!),
        Seed(key: "category.seed.relax", icon: .cupAndSaucer, id: UUID(uuidString: "018f0000-0000-7000-8000-000000000005")!),
        Seed(key: "category.seed.sleep", icon: .bedDouble, id: UUID(uuidString: "018f0000-0000-7000-8000-000000000006")!),
        Seed(key: "category.seed.entertainment", icon: .tv, id: UUID(uuidString: "018f0000-0000-7000-8000-000000000007")!),
    ]

    private let repository: CatalogRepository
    private let service: CatalogService
    private let sessionCache: SessionCache
    private let locale: Locale
    private var isSeeding = false

    init(
        repository: CatalogRepository,
        service: CatalogService,
        sessionCache: SessionCache,
        locale: Locale = .current
    ) {
        self.repository = repository
        self.service = service
        self.sessionCache = sessionCache
        self.locale = locale
    }

    func seedIfNeeded() async {
        guard !sessionCache.categoriesSeeded, !isSeeding else { return }
        isSeeding = true
        defer { isSeeding = false }

        for seed in Self.seeds {
            let now = Date()
            let category = Category(
                id: seed.id,
                name: localizedName(for: seed.key),
                icon: seed.icon,
                createdAt: now,
                updatedAt: now
            )
            do {
                _ = try await service.createCategory(category)
            } catch {
                let catalogError = CatalogError.map(error)
                guard case let .categoryExists(existingId, existingName) = catalogError else {
                    return
                }
                let survivor = await existingCategory(
                    id: existingId,
                    name: existingName,
                    fallback: category
                )
                await service.store.upsertCategory(survivor)
            }
        }

        sessionCache.categoriesSeeded = true
    }

    private func existingCategory(id: UUID, name: String, fallback: Category) async -> Category {
        if let category = try? await repository.getCategory(id) {
            return category
        }
        return Category(
            id: id,
            name: name,
            icon: fallback.icon,
            createdAt: fallback.createdAt,
            updatedAt: fallback.updatedAt
        )
    }

    private func localizedName(for key: String) -> String {
        let language = normalizedLanguageCode
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private var normalizedLanguageCode: String {
        let code: String?
        if #available(iOS 16.0, *) {
            code = locale.language.languageCode?.identifier
        } else {
            code = locale.languageCode
        }
        return code?.lowercased().hasPrefix("ru") == true ? "ru" : "en"
    }
}
