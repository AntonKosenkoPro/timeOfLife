import Foundation
@testable import TimeOfLife

/// Factories for catalog test fixtures. Ids default to UUID v7 (the client
/// generator under test) so create/replay flows are realistic.
enum TestCatalogFactory {
    static func activity(
        id: UUID = UUID.v7(),
        name: String = "Gym",
        notes: String? = nil,
        lastUsedAt: Date? = nil,
        categoryIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> Activity {
        Activity(id: id, name: name, notes: notes,
                 lastUsedAt: lastUsedAt, categoryIds: categoryIds,
                 createdAt: createdAt, updatedAt: updatedAt)
    }

    static func category(
        id: UUID = UUID.v7(),
        name: String = "Sport",
        icon: CatalogIcon = .tag,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> Category {
        Category(id: id, name: name, icon: icon,
                 createdAt: createdAt, updatedAt: updatedAt)
    }
}
