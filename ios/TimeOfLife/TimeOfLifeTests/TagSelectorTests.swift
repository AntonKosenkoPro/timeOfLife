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

    @Test("reselecting appends at the end")
    func reselectAppendsAtEnd() {
        let selected = ["c2", "c1"]
        #expect(TagSelector.glyph(for: "c2", in: selected) == .ordinal(1))
        #expect(TagSelector.glyph(for: "c1", in: selected) == .ordinal(2))
    }

    @Test("ordinals cap at 99")
    func ordinalsCapAt99() {
        let selected = (0..<100).map { "c\($0)" }
        #expect(TagSelector.glyph(for: "c0", in: selected) == .ordinal(1))
        #expect(TagSelector.glyph(for: "c98", in: selected) == .ordinal(99))
        #expect(TagSelector.glyph(for: "c99", in: selected) == .ordinal(99))
    }
}
