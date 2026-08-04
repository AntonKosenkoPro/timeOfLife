import Foundation

/// The validated category icon set (F2/U1).
///
/// The union of the backend `validIcons` and the iOS-only additions. The
/// backend is the authoritative validator (U1); the client keeps the full
/// union so local seeds and user-created categories never send an icon the
/// server rejects. See `backend/internal/handlers/catalog_validators.go`
/// `validIcons` and `Design/TOKENS.md`.
enum CatalogIcon {
    /// The full allowed SF Symbol set for categories. Callers pass this to
    /// `IconPickerGrid` and seed logic.
    static let allowedSymbols: [String] = [
        // Figures — activity
        "figure.walk", "figure.run", "figure.strengthtraining",
        "figure.yoga", "figure.cycling", "figure.swimming",
        "figure.soccer", "figure.basketball", "figure.tennis",
        "figure.gymnastics", "figure.mindandbody", "figure.core.training",
        // Knowledge / work
        "book", "books", "graduationcap",
        "laptopcomputer", "desktopcomputer", "keyboard",
        // Entertainment
        "gamecontroller", "tv", "musicalnotes",
        // Creative / household
        "paintbrush", "briefcase", "house",
        // Food / drink
        "fork.knife", "cup.and.saucer",
        // Rest
        "moon.zzz", "bed.double", "moon.stars",
        // Travel
        "car.fill", "airplane", "cart", "phone",
        // Misc
        "clock", "tag",
        // iOS-only (union)
        "pencil.and.ruler", "brain.head.profile",
        "dumbbell", "bicycle",
        "film", "music.note", "guitar", "camera",
        "hammer", "heart", "leaf", "sparkles",
    ]

    /// The seven default seed icons (F6).
    static let seedIcons: [String] = [
        "briefcase",        // Work
        "paintbrush",       // Hobby
        "figure.run",       // Sport
        "book",             // Education
        "cup.and.saucer",   // Relax
        "bed.double",       // Sleep
        "tv",               // Entertainment
    ]
}
