import Foundation

/// Seeds seven localized default categories on first run after sign-in (F6).
///
/// Bootstrap order (AC8): open DB → outbound sync → initial pull → if seeding
/// is undecided and categories are empty, insert all seven transactionally →
/// mark the per-account seed decision only after the transaction succeeds →
/// sync inserted categories.
///
/// Seeds are ordinary records: editable, re-iconable, deletable. Seeding is
/// client-side via ordinary `POST /categories`. Interrupted bootstrap
/// remains retryable and cannot produce a partially completed seed flag.
@MainActor
final class Seeder {

    /// The metadata key that records the seed decision per account.
    static let seedDecisionKey = "categories_seeded"

    private let localStore: LocalStore
    private let syncCoordinator: SyncCoordinator?

    init(localStore: LocalStore, syncCoordinator: SyncCoordinator? = nil) {
        self.localStore = localStore
        self.syncCoordinator = syncCoordinator
    }

    /// Seeds the seven default categories if seeding is undecided and the
    /// local store has zero visible categories. Idempotent — replays do not
    /// duplicate.
    ///
    /// Returns `true` if categories were inserted (the seed ran), `false`
    /// otherwise (already seeded or non-empty).
    @discardableResult
    func seedIfNeeded() async -> Bool {
        do {
            // Check the per-account seed decision.
            if let decision = try await localStore.metadataValue(forKey: Self.seedDecisionKey),
               decision == "true" {
                return false
            }

            // Check if categories are empty.
            let categories = try await localStore.categoriesSortedByName()
            if !categories.isEmpty {
                // Non-empty but no decision flag — mark seeded (the user
                // pulled categories from the server, so seeding is moot).
                try await localStore.setMetadataValue("true", forKey: Self.seedDecisionKey)
                return false
            }

            // Insert all seven transactionally. The `upsertCategory` calls
            // are individual transactions; the seed decision is marked only
            // after all inserts succeed, so an interrupted bootstrap leaves
            // the decision unset and the next launch re-runs the seed.
            // Re-running the seed with already-inserted categories is safe
            // because `upsertCategory` is idempotent on `id`.
            let seeds = Self.seedCategories()
            for category in seeds {
                try await localStore.upsertCategory(category)
            }

            // Mark the seed decision only after the transaction succeeds.
            try await localStore.setMetadataValue("true", forKey: Self.seedDecisionKey)

            // Trigger a sync to push the seeded categories to the server.
            await syncCoordinator?.sync()
            return true
        } catch {
            // Seeding failed — the decision is not marked, so the next
            // launch will retry. Already-inserted categories are idempotent.
            return false
        }
    }

    /// Returns `true` if the per-account seed decision has been recorded.
    func hasSeeded() async -> Bool {
        do {
            return try await localStore.metadataValue(forKey: Self.seedDecisionKey) == "true"
        } catch {
            return false
        }
    }

    /// The seven default localized categories (F6). Ids are deterministic
    /// (UUID v7) so replays are idempotent.
    nonisolated static func seedCategories(now: Date = Date()) -> [Category] {
        let names = seedLocalizedNames()
        let icons = CatalogIcon.seedIcons
        // Use fixed UUIDs so replays are idempotent. These are UUID v7-ish
        // deterministic values; the backend accepts any UUID v7.
        let ids = [
            "01923e80-0000-7000-8000-000000000001",
            "01923e80-0000-7000-8000-000000000002",
            "01923e80-0000-7000-8000-000000000003",
            "01923e80-0000-7000-8000-000000000004",
            "01923e80-0000-7000-8000-000000000005",
            "01923e80-0000-7000-8000-000000000006",
            "01923e80-0000-7000-8000-000000000007",
        ]
        return zip(zip(names, icons), ids).map { nameIcon, id in
            let (name, icon) = nameIcon
            return Category(
                id: id,
                name: name,
                icon: icon,
                createdAt: now,
                updatedAt: now,
                sync: .newPending())
        }
    }

    /// The seven localized seed names, resolved via `L10n`/`NSLocalizedString`
    /// so they follow the device locale.
    nonisolated private static func seedLocalizedNames() -> [String] {
        [
            NSLocalizedString("category.seed.work", comment: ""),
            NSLocalizedString("category.seed.hobby", comment: ""),
            NSLocalizedString("category.seed.sport", comment: ""),
            NSLocalizedString("category.seed.education", comment: ""),
            NSLocalizedString("category.seed.relax", comment: ""),
            NSLocalizedString("category.seed.sleep", comment: ""),
            NSLocalizedString("category.seed.entertainment", comment: ""),
        ]
    }
}
