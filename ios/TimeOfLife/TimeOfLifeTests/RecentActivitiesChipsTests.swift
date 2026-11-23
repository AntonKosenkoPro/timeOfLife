import Testing
import Foundation
import SwiftUI
@testable import TimeOfLife

@Suite("RecentActivitiesChips.recents")
struct RecentActivitiesChipsTests {

    private func recent(_ id: String) -> ExactName {
        ExactName(text: id, categoryIDs: [], firstCategoryID: nil)
    }

    @Test("caps at ten recents, preserving the input order")
    func capsAtTen() {
        let recents = (0..<(TrackViewModel.recentsLimit + 4)).map { recent("a\($0)") }
        let capped = RecentActivitiesChips.recents(from: recents)
        #expect(capped.count == TrackViewModel.recentsLimit)
        #expect(capped.map(\.text) == (0..<TrackViewModel.recentsLimit).map { "a\($0)" })
    }

    @Test("omits the oldest recents beyond the cap")
    func omitsOldestBeyondCap() {
        let recents = (0...(TrackViewModel.recentsLimit)).map { recent("a\($0)") }
        let capped = RecentActivitiesChips.recents(from: recents)
        #expect(!capped.map(\.text).contains("a\(TrackViewModel.recentsLimit)"))
        #expect(capped.last?.text == "a\(TrackViewModel.recentsLimit - 1)")
    }

    @Test("returns all recents when fewer than the cap")
    func fewerThanCap() {
        let recents = (0..<3).map { recent("a\($0)") }
        let capped = RecentActivitiesChips.recents(from: recents)
        #expect(capped.count == 3)
        #expect(capped.map(\.text) == recents.map(\.text))
    }

    @Test("returns nothing for an empty input")
    func emptyInput() {
        #expect(RecentActivitiesChips.recents(from: []).isEmpty)
    }

    @Test("preserves the store-sorted order exactly")
    func preservesOrder() {
        let recents = [recent("oldest"), recent("middle"), recent("newest")]
        #expect(RecentActivitiesChips.recents(from: recents).map(\.text) == ["oldest", "middle", "newest"])
    }

    @Test("honours a custom limit")
    func customLimit() {
        let recents = (0..<4).map { recent("a\($0)") }
        #expect(RecentActivitiesChips.recents(from: recents, limit: 2).count == 2)
    }
}

@Suite("RecentActivitiesChips.ChipSizes")
struct ChipSizesTests {
    @Test("byte-identical sizes at a new generation compare unequal, so the preference refires after a DT clear")
    func generationBumpRefiresIdenticalSizes() {
        let sizes = ["a": CGSize(width: 100, height: 44)]
        let before = ChipSizes(generation: .large, sizes: sizes)
        let after = ChipSizes(generation: .xLarge, sizes: sizes)
        #expect(before != after)
    }

    @Test("reduce merges per-key sizes and adopts the latest generation")
    func reduceMergesAndAdoptsGeneration() {
        var value = ChipSizes(generation: .large, sizes: ["a": CGSize(width: 100, height: 44)])
        let next = ChipSizes(generation: .xLarge, sizes: ["b": CGSize(width: 120, height: 44)])
        ChipSizesKey.reduce(value: &value) { next }
        #expect(value.sizes == ["a": CGSize(width: 100, height: 44), "b": CGSize(width: 120, height: 44)])
        #expect(value.generation == .xLarge)
    }

    @Test("reduce lets later reports win per key")
    func reduceLaterWinsPerKey() {
        var value = ChipSizes(generation: .large, sizes: ["a": CGSize(width: 100, height: 44)])
        let next = ChipSizes(generation: .large, sizes: ["a": CGSize(width: 110, height: 44)])
        ChipSizesKey.reduce(value: &value) { next }
        #expect(value.sizes == ["a": CGSize(width: 110, height: 44)])
    }
}
