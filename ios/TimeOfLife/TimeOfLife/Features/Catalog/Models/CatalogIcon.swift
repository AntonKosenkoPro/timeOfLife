import Foundation
import UIKit

/// The closed set of catalog SF Symbols a category may use
/// (category-management D1). The raw values mirror the authoritative
/// `CategoryIcon` enum in `backend/api/openapi.yaml` exactly — the backend
/// `validIcons` set, this type, and `Design/TOKENS.md` all use the same list,
/// and parity tests fail when they drift.
enum CatalogIcon: String, Codable, CaseIterable, Sendable {
    case clock
    case laptopcomputer
    case briefcase
    case book
    case pencilAndRuler = "pencil.and.ruler"
    case brainHeadProfile = "brain.head.profile"
    case figureWalk = "figure.walk"
    case figureRun = "figure.run"
    case figureStrengthtraining = "figure.strengthtraining"
    case figureYoga = "figure.yoga"
    case figureCycling = "figure.cycling"
    case figureSwimming = "figure.swimming"
    case figureSoccer = "figure.soccer"
    case figureBasketball = "figure.basketball"
    case figureTennis = "figure.tennis"
    case figureGymnastics = "figure.gymnastics"
    case figureMindandbody = "figure.mindandbody"
    case figureCoreTraining = "figure.core.training"
    case dumbbell
    case bicycle
    case books
    case graduationcap
    case desktopcomputer
    case keyboard
    case gamecontroller
    case forkKnife = "fork.knife"
    case cupAndSaucer = "cup.and.saucer"
    case bedDouble = "bed.double"
    case moonStars = "moon.stars"
    case moonZzz = "moon.zzz"
    case film
    case musicNote = "music.note"
    case guitar
    case camera
    case tv
    case musicalnotes
    case paintbrush
    case house
    case carFill = "car.fill"
    case airplane
    case cart
    case phone
    case hammer
    case heart
    case leaf
    case sparkles
    case tag

    /// The default icon for a newly created category.
    static let `default` = CatalogIcon.tag
}

extension CatalogIcon {
    /// All catalog symbols as their SF Symbol names.
    static var allSymbols: [String] { allCases.map(\.rawValue) }

    /// The catalog symbols that can render on the running OS. Some catalog
    /// symbols are unavailable on older supported OS versions; the picker
    /// hides them so the user only ever chooses a renderable symbol.
    static var renderableSymbols: [String] {
        allSymbols.filter(Self.canRender)
    }

    /// Whether the symbol can render on the running OS.
    static func canRender(_ symbol: String) -> Bool {
        UIImage(systemName: symbol) != nil
    }

    /// The symbol to display for a category. A valid synchronized raw value
    /// that cannot render on this OS is displayed as `tag` WITHOUT changing
    /// the stored value.
    var displaySymbol: String {
        Self.canRender(rawValue) ? rawValue : CatalogIcon.default.rawValue
    }

    /// Creates an icon from a raw value, defaulting to `tag` when the value
    /// is not in the supported catalog (e.g. a stale synchronized value).
    init(validated rawValue: String) {
        self = Self(rawValue: rawValue) ?? .tag
    }
}
