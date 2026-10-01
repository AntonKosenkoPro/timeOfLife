import Foundation

/// One exact-text name: the trimmed, case-sensitive entry text plus the
/// newest entry's ordered categories and first-position category id (the
/// chip/row icon source). Identity is the exact text (`Gym` ≠ `GYM`).
///
/// The single UI shape for Track recents chips, the shared name picker, and
/// the Log Time name recents (timer-capture-experience, name-picker specs).
/// The store DTO (`RecentEntry` in `CatalogModels`, with `startedAt`) maps
/// into this at call sites via `init(storeRecent:)` — one mapper, no
/// parallel shapes.
struct ExactName: Identifiable, Equatable, Sendable {
    let text: String
    let categoryIDs: [String]
    /// The first-position category id, or nil when the newest entry has no
    /// categories (the chip/row renders without an icon).
    let firstCategoryID: String?

    var id: String { text }

    init(text: String, categoryIDs: [String], firstCategoryID: String? = nil) {
        self.text = text
        self.categoryIDs = categoryIDs
        self.firstCategoryID = firstCategoryID ?? categoryIDs.first
    }

    /// Single mapper from the store DTO (which also carries `startedAt`,
    /// irrelevant to the UI shape).
    init(storeRecent recent: RecentEntry) {
        self.init(
            text: recent.activityText,
            categoryIDs: recent.categoryIDs,
            firstCategoryID: recent.categoryIDs.first
        )
    }
}
