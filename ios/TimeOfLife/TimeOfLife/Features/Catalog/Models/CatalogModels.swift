import Foundation

// MARK: - Catalog icons

/// The allowed SF Symbols set shared by catalog activities and categories
/// (F1 / TOKENS); default `.tag`.
///
/// Raw values are the exact SF Symbol strings. This enum is the **union** of the
/// backend's `validIcons` (`catalog_validators.go`) and the design set in
/// `TOKENS.md`, so the client does not pre-reject icons from either source.
/// The backend remains the authoritative validator (U1): an icon outside its
/// set will still get a 422 from the server, but the client keeps the full
/// union acceptable on-device. Decision: union, per the
/// cross-doc icon-set variance (backend `validIcons` ≠ TOKENS.md; `clock` is
/// not backend-valid).
enum CatalogIcon: String, Codable, CaseIterable, Sendable {
    // Shared by backend + TOKENS.md
    case figureRun = "figure.run"
    case figureStrengthtraining = "figure.strengthtraining"
    case figureYoga = "figure.yoga"
    case book
    case laptopcomputer
    case briefcase
    case gamecontroller
    case tv
    case paintbrush
    case forkKnife = "fork.knife"
    case cupAndSaucer = "cup.and.saucer"
    case carFill = "car.fill"
    case airplane

    // TOKENS.md only
    case clock
    case pencilAndRuler = "pencil.and.ruler"
    case brainHeadProfile = "brain.head.profile"
    case dumbbell
    case bicycle
    case bedDouble = "bed.double"
    case moonStars = "moon.stars"
    case film
    case musicNote = "music.note"
    case guitar
    case camera
    case hammer
    case heart
    case leaf
    case sparkles
    case tag

    // Backend validIcons only
    case figureWalk = "figure.walk"
    case figureCycling = "figure.cycling"
    case figureSwimming = "figure.swimming"
    case figureSoccer = "figure.soccer"
    case figureBasketball = "figure.basketball"
    case figureTennis = "figure.tennis"
    case figureGymnastics = "figure.gymnastics"
    case figureMindandbody = "figure.mindandbody"
    case figureCoreTraining = "figure.core.training"
    case books
    case graduationcap
    case desktopcomputer
    case keyboard
    case musicalnotes
    case house
    case moonZzz = "moon.zzz"
    case cart
    case phone

    /// Default icon for a newly created category (UX default per TOKENS.md).
    static let `default` = CatalogIcon.tag

    /// All valid raw SF Symbol names, for client-side pre-checks.
    static var validKeys: Set<String> { Set(allCases.map(\.rawValue)) }

    /// The approved design set of SF Symbol names for the `IconPickerGrid`.
    /// Matches `TOKENS.md` → Category icons, plus the shared catalog defaults.
    static let allowedSymbols: [String] = [
        "tag", "clock", "laptopcomputer", "briefcase", "book",
        "pencil.and.ruler", "brain.head.profile",
        "figure.run", "figure.strengthtraining", "figure.yoga",
        "dumbbell", "bicycle",
        "fork.knife", "cup.and.saucer",
        "bed.double", "moon.stars",
        "gamecontroller", "tv", "film",
        "music.note", "guitar", "paintbrush", "camera",
        "airplane", "car.fill", "hammer",
        "heart", "leaf", "sparkles",
    ]
}

// MARK: - Preview fixtures

#if DEBUG
extension Category {
    static let sampleBlue = Category(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Work",
        icon: .briefcase,
        createdAt: Date(),
        updatedAt: Date()
    )

    static let sampleGreen = Category(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Fitness",
        icon: .figureRun,
        createdAt: Date(),
        updatedAt: Date()
    )

    static let sampleOrange = Category(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Reading",
        icon: .tag,
        createdAt: Date(),
        updatedAt: Date()
    )
}
#endif

// MARK: - Domain models

/// A catalog activity. Persisted locally by `CatalogStore` (file-based JSON,
/// deferred-to-date encoding) and synced via `RemoteCatalogRepository`.
///
/// `categoryIds` are the tags (F2/F3); the resolved `categories[]` are carried
/// only on the GET DTOs. `Activity.id` is a client-generated UUID v7 (F9).
struct Activity: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var notes: String?
    var lastUsedAt: Date?
    var categoryIds: [UUID]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lastUsedAt = "last_used_at"
        case categoryIds = "category_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A catalog category. Persisted locally by `CatalogStore` and synced via the
/// remote repository. `Category.id` is a client-generated UUID v7.
struct Category: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var icon: CatalogIcon
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
