import Foundation
@testable import TimeOfLife

// `Category` collides with an Objective-C class in Foundation; alias our type
// so factory methods can reference it unambiguously.
typealias Cat = TimeOfLife.Category

/// Factories for building catalog domain models and DTOs in tests.
enum CatalogTestFactory {

    // MARK: - Dates

    static let referenceDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    static func date(offset seconds: TimeInterval = 0) -> Date {
        referenceDate.addingTimeInterval(seconds)
    }

    // MARK: - Categories

    static func makeCategory(
        id: String = "cat-1",
        name: String = "Work",
        icon: String = "briefcase",
        createdAt: Date = date(),
        updatedAt: Date = date(),
        sync: SyncMetadata = .adoptedClean()
    ) -> Cat {
        Cat(
            id: id,
            name: name,
            icon: icon,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sync: sync
        )
    }

    static func makeCategoryDTO(
        id: String = "cat-1",
        name: String = "Work",
        icon: String = "briefcase",
        createdAt: Date = date(),
        updatedAt: Date = date()
    ) -> CategoryDTO {
        CategoryDTO(
            id: id,
            name: name,
            icon: icon,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func makeCategoryCreateRequest(
        id: String = "cat-1",
        name: String = "Work",
        icon: String = "briefcase"
    ) -> CategoryCreateRequest {
        CategoryCreateRequest(id: id, name: name, icon: icon)
    }

    // MARK: - Activities

    static func makeActivity(
        id: String = "act-1",
        name: String = "Reading",
        notes: String? = nil,
        lastUsedAt: Date? = nil,
        createdAt: Date = date(),
        updatedAt: Date = date(),
        categoryIds: [String] = [],
        sync: SyncMetadata = .adoptedClean()
    ) -> Activity {
        Activity(
            id: id,
            name: name,
            notes: notes,
            lastUsedAt: lastUsedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            categoryIds: categoryIds,
            sync: sync
        )
    }

    static func makeActivityDTO(
        id: String = "act-1",
        name: String = "Reading",
        notes: String? = nil,
        lastUsedAt: Date? = nil,
        createdAt: Date = date(),
        updatedAt: Date = date(),
        categories: [CategoryTag] = []
    ) -> ActivityDTO {
        ActivityDTO(
            id: id,
            name: name,
            notes: notes,
            lastUsedAt: lastUsedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            categories: categories
        )
    }

    static func makeCategoryTag(
        id: String = "cat-1",
        name: String = "Work",
        icon: String = "briefcase"
    ) -> CategoryTag {
        CategoryTag(id: id, name: name, icon: icon)
    }

    // MARK: - Entries

    static func makeEntry(
        id: String = "ent-1",
        activityId: String = "act-1",
        startedAt: Date = date(),
        endedAt: Date? = date(offset: 60),
        durationSeconds: Double? = 60,
        createdAt: Date = date(),
        updatedAt: Date = date(),
        sync: SyncMetadata = .adoptedClean()
    ) -> Entry {
        Entry(
            id: id,
            activityId: activityId,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sync: sync
        )
    }

    static func makeEntryDTO(
        id: String = "ent-1",
        activityId: String = "act-1",
        activityName: String = "Reading",
        startedAt: Date = date(),
        endedAt: Date? = date(offset: 60),
        durationSeconds: Double? = 60,
        createdAt: Date = date(),
        updatedAt: Date = date(),
        categories: [CategoryTag] = []
    ) -> EntryDTO {
        EntryDTO(
            id: id,
            activityId: activityId,
            activityName: activityName,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt,
            categories: categories
        )
    }
}
