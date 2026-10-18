import Testing
import Foundation
@testable import TimeOfLife

@Suite("TagSelector.glyph")
struct TagSelectorTests {

    @Test("unselected chips show the icon")
    func unselectedShowsIcon() {
        #expect(TagSelector.glyph(for: "c1", in: []) == .icon)
        #expect(TagSelector.glyph(for: "c1", in: ["c2", "c3"]) == .icon)
    }

    @Test("a lone selection shows the checkmark")
    func loneSelectionShowsCheckmark() {
        #expect(TagSelector.glyph(for: "c1", in: ["c1"]) == .checkmark)
    }

    @Test("two selections show ordinals in tap order, not catalog order")
    func twoSelectionsShowOrdinals() {
        let selected = ["c2", "c1"]
        #expect(TagSelector.glyph(for: "c2", in: selected) == .ordinal(1))
        #expect(TagSelector.glyph(for: "c1", in: selected) == .ordinal(2))
    }

    @Test("deselecting the middle renumbers densely")
    func deselectRenumbersDensely() {
        let selected = ["c1", "c3"]
        #expect(TagSelector.glyph(for: "c1", in: selected) == .ordinal(1))
        #expect(TagSelector.glyph(for: "c3", in: selected) == .ordinal(2))
        #expect(TagSelector.glyph(for: "c2", in: selected) == .icon)
    }

    @Test("returning to one selection restores the checkmark")
    func backToOneRestoresCheckmark() {
        #expect(TagSelector.glyph(for: "c3", in: ["c3"]) == .checkmark)
    }

    @Test("three selections show ordinals in tap order")
    func threeSelectionsShowOrdinals() {
        let selected = ["c3", "c1", "c2"]
        #expect(TagSelector.glyph(for: "c3", in: selected) == .ordinal(1))
        #expect(TagSelector.glyph(for: "c1", in: selected) == .ordinal(2))
        #expect(TagSelector.glyph(for: "c2", in: selected) == .ordinal(3))
    }

    @Test("ordinals cap at 99")
    func ordinalsCapAt99() {
        let selected = (0..<100).map { "c\($0)" }
        #expect(TagSelector.glyph(for: "c0", in: selected) == .ordinal(1))
        #expect(TagSelector.glyph(for: "c98", in: selected) == .ordinal(99))
        #expect(TagSelector.glyph(for: "c99", in: selected) == .ordinal(99))
    }
}

@Suite("TagSelector.createChip")
struct TagSelectorCreateChipTests {

    private func makeSelector(onCreate: (@Sendable () -> Void)?) -> TagSelector {
        TagSelector(
            options: [Category(id: "c1", name: "Work", icon: "briefcase")],
            selected: [],
            onToggle: { _ in },
            onCreate: onCreate,
            accessibilityId: "TestTags"
        )
    }

    @Test("creation chip renders if and only if onCreate is provided")
    func createChipOptIn() {
        #expect(makeSelector {}.showsCreateChip)
        #expect(!makeSelector(onCreate: nil).showsCreateChip)
    }

    @Test("viewport clamps at 3.5 rows plus inter-row gaps")
    func clampMath() {
        #expect(ChipViewport.clampedHeight(rowHeight: 44, spacing: 8) == 3.5 * 44 + 3 * 8)
        #expect(ChipViewport.clampedHeight(rowHeight: 60, spacing: 8) == 3.5 * 60 + 3 * 8)
    }

    @Test("both dividers hide when the catalog fits without scrolling")
    func edgesFitHideBoth() {
        let edges = ChipViewport.edges(offsetY: 0, containerHeight: 200, contentHeight: 100)
        #expect(edges.atTop)
        #expect(edges.atEnd)
    }

    @Test("top divider hides at rest, bottom shows while content remains")
    func edgesAtTop() {
        let edges = ChipViewport.edges(offsetY: 0, containerHeight: 178, contentHeight: 400)
        #expect(edges.atTop)
        #expect(!edges.atEnd)
    }

    @Test("both dividers show mid-scroll")
    func edgesMidScroll() {
        let edges = ChipViewport.edges(offsetY: 100, containerHeight: 178, contentHeight: 400)
        #expect(!edges.atTop)
        #expect(!edges.atEnd)
    }

    @Test("bottom divider hides at the content end")
    func edgesAtEnd() {
        let edges = ChipViewport.edges(offsetY: 222, containerHeight: 178, contentHeight: 400)
        #expect(!edges.atTop)
        #expect(edges.atEnd)
    }
}
