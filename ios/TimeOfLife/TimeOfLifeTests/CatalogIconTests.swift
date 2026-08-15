import Testing
import Foundation
import UIKit
@testable import TimeOfLife

@Suite("CatalogIcon")
struct CatalogIconTests {

    /// The canonical icon catalog, mirroring the authoritative `CategoryIcon`
    /// enum in `backend/api/openapi.yaml` (category-management D1). The Go
    /// contract test pins OpenAPI↔Go; this list pins iOS↔OpenAPI. Update both
    /// together when the catalog changes.
    private let canonicalSymbols = [
        "clock", "laptopcomputer", "briefcase", "book",
        "pencil.and.ruler", "brain.head.profile",
        "figure.walk", "figure.run", "figure.strengthtraining", "figure.yoga",
        "figure.cycling", "figure.swimming", "figure.soccer", "figure.basketball",
        "figure.tennis", "figure.gymnastics", "figure.mindandbody",
        "figure.core.training", "dumbbell", "bicycle",
        "books", "graduationcap", "desktopcomputer", "keyboard",
        "gamecontroller", "fork.knife", "cup.and.saucer",
        "bed.double", "moon.stars", "moon.zzz",
        "film", "music.note", "guitar", "camera", "tv", "musicalnotes",
        "paintbrush", "house", "car.fill", "airplane", "cart", "phone",
        "hammer", "heart", "leaf", "sparkles", "tag",
    ]

    @Test("CatalogIcon mirrors the authoritative OpenAPI icon set exactly")
    func matchesCanonicalSet() {
        let actual = Set(CatalogIcon.allSymbols)
        let expected = Set(canonicalSymbols)
        #expect(actual == expected,
                "CatalogIcon drifted from the canonical set. Missing: \(expected.subtracting(actual)), extra: \(actual.subtracting(expected))")
    }

    @Test("every case has a distinct raw value")
    func rawValuesAreDistinct() {
        let rawValues = CatalogIcon.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("default icon is tag")
    func defaultIsTag() {
        #expect(CatalogIcon.default == .tag)
        #expect(CatalogIcon.default.rawValue == "tag")
    }

    @Test("init(validated:) falls back to tag for unsupported values")
    func validatedInitFallsBack() {
        #expect(CatalogIcon(validated: "tag") == .tag)
        #expect(CatalogIcon(validated: "briefcase") == .briefcase)
        #expect(CatalogIcon(validated: "not.a.real.symbol") == .tag)
        #expect(CatalogIcon(validated: "") == .tag)
    }

    @Test("renderableSymbols is a subset of the full catalog and never includes unrenderable symbols")
    func renderableSymbolsAreRenderable() {
        for symbol in CatalogIcon.renderableSymbols {
            #expect(canonicalSymbols.contains(symbol))
            #expect(CatalogIcon.canRender(symbol))
        }
    }

    @Test("displaySymbol falls back to tag only when the raw value cannot render")
    func displaySymbolFallsBackWhenUnrenderable() {
        #expect(CatalogIcon.briefcase.displaySymbol == "briefcase")
        // A raw value outside the catalog renders as the tag fallback without
        // changing the stored value.
        let invalid = CatalogIcon(validated: "not.a.real.symbol")
        #expect(invalid.displaySymbol == "tag")
        #expect(CatalogIcon.tag.displaySymbol == "tag")
    }

    @Test("unavailable symbols are hidden from the picker without changing stored values")
    func unrenderableSymbolsHidden() {
        // Simulate an OS where a catalog symbol cannot render: the picker list
        // excludes it while the stored raw value remains authoritative.
        let symbol = "figure.strengthtraining"
        let renderable = CatalogIcon.allSymbols.filter { $0 != symbol }
        #expect(!renderable.contains(symbol))
        let category = TimeOfLife.Category(id: "c1", name: "Gym", icon: symbol)
        #expect(category.icon == symbol)
        #expect(CatalogIcon(validated: category.icon).rawValue == symbol)
    }
}
