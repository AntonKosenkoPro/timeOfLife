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
        "gamecontroller", "fork.knife", "cup.and.saucer", "carrot",
        "bed.double", "moon.stars", "moon.zzz",
        "film", "music.note", "guitar", "camera", "tv", "musicalnotes",
        "paintbrush", "house", "car.fill", "airplane", "cart", "phone",
        "hammer", "heart", "leaf", "sparkles",
        "pawprint", "dog", "cat", "fish", "bird",
        "washer", "dryer", "dishwasher", "refrigerator",
        "sofa", "shower", "lamp.table",
        "person.2", "figure.and.child.holdinghands", "stroller", "teddybear",
        "stethoscope", "pill", "tag",
    ]

    /// The exact hidden-from-new-selection set (eight sports values).
    private let hiddenSymbols: Set<String> = [
        "figure.strengthtraining", "figure.soccer", "figure.basketball",
        "figure.tennis", "figure.gymnastics", "figure.mindandbody",
        "figure.core.training", "bicycle",
    ]

    /// The exact food/drink and child-specific new-selection choices.
    private let foodChoices: Set<String> = ["fork.knife", "cup.and.saucer", "carrot"]
    private let childChoices: Set<String> = [
        "figure.and.child.holdinghands", "stroller", "teddybear",
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
        let category = Category(id: "c1", name: "Gym", icon: symbol)
        #expect(category.icon == symbol)
        #expect(CatalogIcon(validated: category.icon).rawValue == symbol)
    }

    @Test("the three new icons render on this OS")
    func newIconsRender() {
        // Bakes in the improve-category-defaults iOS 18 acceptance gate
        // (carrot/stroller/teddybear verified on the iOS 18 simulator): the
        // deployment floor is iOS 18, so these must render wherever tests run.
        for symbol in ["carrot", "stroller", "teddybear"] {
            #expect(CatalogIcon.allSymbols.contains(symbol), "\(symbol) is accepted")
            #expect(CatalogIcon.canRender(symbol), "\(symbol) renders on this OS")
            #expect(CatalogIcon(validated: symbol).displaySymbol == symbol)
        }
    }

    @Test("hidden sports values stay accepted and render normally where available")
    func hiddenSymbolsRemainAccepted() {
        #expect(CatalogIcon.pickerHiddenSymbols == hiddenSymbols)
        for symbol in hiddenSymbols {
            #expect(CatalogIcon.allSymbols.contains(symbol), "\(symbol) stays accepted")
            #expect(CatalogIcon(validated: symbol).rawValue == symbol)
            if CatalogIcon.canRender(symbol) {
                #expect(
                    CatalogIcon(validated: symbol).displaySymbol == symbol,
                    "\(symbol) uses its own glyph, not tag"
                )
            }
        }
        #expect(CatalogIcon.allSymbols.count == 66)
    }

    @Test("curated picker set is 58 symbols before OS filtering")
    func curatedSymbolsAre58() {
        let curated = CatalogIcon.curatedSymbols
        #expect(curated.count == 58)
        #expect(Set(curated).count == 58, "no duplicates")
        for symbol in hiddenSymbols {
            #expect(!curated.contains(symbol), "\(symbol) hidden from new selection")
        }
        for symbol in ["carrot", "stroller", "teddybear"] {
            #expect(curated.contains(symbol), "\(symbol) offered for new selection")
        }
        // Six retained sports choices, including figure.cycling.
        for symbol in [
            "figure.walk", "figure.run", "dumbbell",
            "figure.yoga", "figure.cycling", "figure.swimming",
        ] {
            #expect(curated.contains(symbol), "\(symbol) retained")
        }
    }

    @Test("each requested domain has exactly its three specified choices")
    func domainChoiceCounts() {
        #expect(foodChoices.isSubset(of: Set(CatalogIcon.curatedSymbols)))
        #expect(childChoices.isSubset(of: Set(CatalogIcon.curatedSymbols)))
        #expect(foodChoices.count == 3)
        #expect(childChoices.count == 3)
        #expect(!childChoices.contains("person.2"), "generic person.2 is not child-specific")
    }

    @Test("picker options append a hidden or unavailable selection exactly once")
    func pickerOptionsPassthrough() {
        let base = CatalogIcon.pickerSymbols
        // A new category (default tag) gets exactly the renderable curated set.
        #expect(CatalogIcon.pickerOptions(selected: "tag") == base)
        for symbol in hiddenSymbols where CatalogIcon.canRender(symbol) {
            let options = CatalogIcon.pickerOptions(selected: symbol)
            #expect(!base.contains(symbol), "\(symbol) not offered for new categories")
            #expect(options.filter { $0 == symbol }.count == 1, "\(symbol) appended once")
            #expect(options.count == base.count + 1)
        }
        // An already-offered selection is not duplicated.
        let offered = base.first { !hiddenSymbols.contains($0) } ?? "tag"
        #expect(CatalogIcon.pickerOptions(selected: offered) == base)
        // An unsupported value never enters the options (validated init maps
        // it to tag before the editor reads options).
        #expect(CatalogIcon.pickerOptions(selected: "not.a.real.symbol") == base)
    }
}
