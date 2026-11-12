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
    case carrot
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
    case pawprint
    case dog
    case cat
    case fish
    case bird
    case washer
    case dryer
    case dishwasher
    case refrigerator
    case sofa
    case shower
    case lampTable = "lamp.table"
    case person2 = "person.2"
    case figureAndChildHoldinghands = "figure.and.child.holdinghands"
    case stroller
    case teddybear
    case stethoscope
    case pill
    case tag

    /// The default icon for a newly created category.
    static let `default` = CatalogIcon.tag
}

extension CatalogIcon {
    /// All catalog symbols as their SF Symbol names.
    static var allSymbols: [String] { allCases.map(\.rawValue) }

    /// Symbols hidden from new selection (category-management): the six
    /// redundant sports choices plus `bicycle` (covered by `figure.cycling`).
    /// Hidden values stay fully accepted, valid, renderable, and syncable —
    /// hiding only removes them from the new-category picker.
    static let pickerHiddenSymbols: Set<String> = [
        "figure.strengthtraining", "figure.soccer", "figure.basketball",
        "figure.tennis", "figure.gymnastics", "figure.mindandbody",
        "figure.core.training", "bicycle",
    ]

    /// The curated new-selection catalog: every accepted symbol except the
    /// hidden set, in declaration order (58 before OS renderability
    /// filtering: 66 accepted minus 8 hidden).
    static var curatedSymbols: [String] {
        allSymbols.filter { !pickerHiddenSymbols.contains($0) }
    }

    /// The symbols offered for a new category on the running OS: the curated
    /// set minus symbols the OS cannot render.
    static var pickerSymbols: [String] {
        curatedSymbols.filter(Self.canRender)
    }

    /// The catalog symbols that can render on the running OS. Some catalog
    /// symbols are unavailable on older supported OS versions; the picker
    /// hides them so the user only ever chooses a renderable symbol.
    static var renderableSymbols: [String] {
        allSymbols.filter(Self.canRender)
    }

    /// Options for the shared category editor: the renderable curated set,
    /// plus the currently selected supported symbol appended once when it is
    /// hidden from new selection (or unrenderable on this OS). A hidden
    /// selected symbol keeps its original glyph where renderable; only
    /// genuine OS unavailability falls back to `tag` at display time, and
    /// only an explicit icon change mutates the stored value.
    static func pickerOptions(selected: String) -> [String] {
        let base = pickerSymbols
        guard allSymbols.contains(selected), !base.contains(selected) else { return base }
        return base + [selected]
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
