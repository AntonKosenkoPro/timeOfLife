import SwiftUI

/// Multi-select category chips for an activity (Design/COMPONENTS.md,
/// `TagSelector`). Wrapping flow of content-sized tappable chips with equal
/// `Theme.spacingSmall` gaps; toggling a chip adds/removes the category id
/// from the ordered selection (category-management D5/D6: zero-or-more,
/// selection order preserved). Categories are optional — the selector never
/// forces a selection.
///
/// Chips follow category-management D9: each chip is as wide as its content
/// (uniform `Theme.spacingChip` padding on all sides). Typography matches
/// `RecentActivitiesChips` (Recents as reference): subheadline labels
/// with a 14 pt subheadline-scaled leading slot, scaling with Dynamic Type.
/// The leading slot shows the category icon when unselected, a `checkmark`
/// for a lone selection, and the 1-based selection ordinal when two or more
/// chips are selected (two-digit ordinals shrink to fit), no outline
/// circles, and a 44 pt minimum tap target. The slot keeps the measured chip
/// width exact in every state, so toggling never re-packs rows. Glyph changes
/// fade in place. Chips wrap via the shared `FlowLayout` with equal
/// `Theme.spacingSmall` gaps.
///
/// The optional trailing creation chip (inline-category-creation) renders
/// last in the flow only when `onCreate` is non-nil. It is an action, not a
/// choice: dashed accent outline, `plus` glyph, and the localized
/// Add-category label — never a category icon, checkmark, or ordinal — so it
/// differs from both unselected and selected chips by shape as well as color.
/// The chip viewport grows with content and clamps at 3.5 visible rows with
/// internal scroll, so small catalogs stay compact and large ones never push
/// past the clamp; edge-aware hairlines mark hidden content above/below.
struct TagSelector: View {
    let options: [Category]
    /// The selected ids in selection (tap) order; deselect-then-reselect
    /// appends at the end. The parent owns the order.
    let selected: [String]
    /// Called with the toggled category id; the parent owns the ordered
    /// selection.
    let onToggle: (String) -> Void
    /// When non-nil, the pinned creation footer renders below the chips and
    /// tapping it calls this closure. Nil (the default) keeps the selector
    /// select-only.
    let onCreate: (() -> Void)?
    let accessibilityId: String

    /// Whether the trailing creation chip renders. Pure so the opt-in
    /// contract is unit-testable.
    var showsCreateChip: Bool { onCreate != nil }

    /// Scroll-edge state for the viewport dividers (shared `ChipViewport`
    /// math — same clamp and fade contract as Recents).
    @State private var edges = ChipViewport.Edges()
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    /// Chip row height: subheadline line height at the environment's Dynamic
    /// Type size plus uniform padding, floored at the 44 pt target so the
    /// clamp holds under Dynamic Type. Resolved against the environment
    /// trait (Recents `sizeTrait` pattern) — `preferredFont` alone already
    /// resolves at the current category, so it must not be re-scaled.
    private var chipRowHeight: CGFloat {
        let lineHeight = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        ).lineHeight
        return max(Theme.minTapArea, lineHeight + Theme.spacingChip * 2)
    }

    /// Fade duration for glyph transitions (select, deselect, renumber,
    /// checkmark↔ordinal swap).
    private static let glyphFadeDuration = 0.2

    /// The leading-slot content contract: icon when unselected, checkmark for
    /// a lone selection, else the 1-based selection ordinal. Pure so the
    /// ordinal derivation is unit-testable.
    enum ChipGlyph: Equatable {
        case icon
        case checkmark
        case ordinal(Int)
    }

    /// Resolves which glyph a chip shows for `id` within the ordered
    /// `selected` ids. Ordinals cap at 99 (a third digit is impossible).
    /// Pure and `nonisolated` so unit tests (and any nonisolated caller)
    /// can use it without an actor hop.
    nonisolated static func glyph(for id: String, in selected: [String]) -> ChipGlyph {
        guard let index = selected.firstIndex(of: id) else { return .icon }
        guard selected.count > 1 else { return .checkmark }
        return .ordinal(min(index + 1, 99))
    }

    var body: some View {
        // Zero inter-spacing: dividers sit exactly on the viewport cuts.
        // The top divider fades in once chips scroll under it; the bottom
        // one fades out at the content end — both stay hidden when the
        // catalog fits without scrolling.
        VStack(alignment: .leading, spacing: 0) {
            if !edges.atTop {
                Divider().background(Theme.hairline)
                    .transition(.opacity)
            }
            ScrollView {
                FlowLayout(spacing: Theme.spacingSmall) {
                    ForEach(options) { category in
                        chip(category)
                    }
                    if showsCreateChip {
                        createChip
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Flexible viewport (inline-category-creation): sizes to content
            // until the 3.5-row clamp, then scrolls internally. Small catalogs
            // stay compact; the half-row peek signals scrollability.
            .frame(maxHeight: ChipViewport.clampedHeight(
                rowHeight: chipRowHeight,
                spacing: Theme.spacingSmall
            ))
            // Hug content up to the clamp (Recents pattern): without this
            // the ScrollView claims the full clamp even for 1–2 rows.
            .fixedSize(horizontal: false, vertical: true)
            .onScrollGeometryChange(for: ChipViewport.Edges.self, of: { geometry in
                ChipViewport.edges(
                    offsetY: geometry.contentOffset.y,
                    containerHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height
                )
            }, action: { _, new in
                edges = new
            })
            if !edges.atEnd {
                Divider().background(Theme.hairline)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: edges)
    }

    /// Icon and checkmark glyph size: 14 pt subheadline scaled with Dynamic
    /// Type via `UIFontMetrics` — identical to the Recents chip glyphs.
    private var symbolFontSize: CGFloat {
        UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 14)
    }

    /// Ordinal glyph size: full size for a single digit, shrunk for two
    /// digits so the pair fits the fixed slot.
    private func ordinalFontSize(position: Int) -> CGFloat {
        position < 10 ? symbolFontSize : symbolFontSize * 0.8
    }

    /// Fixed symbol slot: wide SF Symbols (e.g. `figure.run`) stay fully
    /// visible while the slot keeps the measured chip width exact. The same
    /// slot serves the icon, the checkmark, and the ordinal, so toggling
    /// never re-packs rows.
    private var symbolSlotSize: CGFloat {
        ceil(symbolFontSize * 1.5)
    }

    @ViewBuilder
    private func chip(_ category: Category) -> some View {
        let glyph = Self.glyph(for: category.id, in: selected)
        Button {
            onToggle(category.id)
        } label: {
            chipLabel(category: category, glyph: glyph)
        }
        .accessibilityLabel("\(L10n.manageCategoriesRowA11y.text), \(category.name)")
        .accessibilityValue(accessibilityValue(for: category.id))
        .accessibilityIdentifier("\(accessibilityId)Chip(\(category.id))")
    }

    /// The trailing creation chip (inline-category-creation): same padding
    /// and 44 pt target as category chips so it packs identically, but
    /// styled as an action — dashed accent outline, `plus` glyph, and
    /// accent text on the secondary fill. Never a category icon, checkmark,
    /// or ordinal, so it differs from both unselected and selected chips by
    /// shape as well as color. Toggling categories never moves, restyles, or
    /// selects it: it sits outside the selection model.
    private var createChip: some View {
        Button {
            onCreate?()
        } label: {
            HStack(spacing: Theme.spacingExtraSmall) {
                Image(systemName: "plus")
                    .font(.system(size: symbolFontSize, weight: .semibold))
                    .frame(width: symbolSlotSize, height: symbolFontSize)
                    .accessibilityHidden(true)
                Text(L10n.manageCategoriesAdd.text)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.accentPrimary)
            .padding(Theme.spacingChip)
            .frame(minHeight: Theme.minTapArea)
            .background(Theme.backgroundSecondary)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(
                    Theme.accentPrimary,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
            }
        }
        .accessibilityLabel(L10n.manageCategoriesAdd.text)
        .accessibilityIdentifier("\(accessibilityId)NewCategory")
    }

    /// VoiceOver value: not-selected when unselected, selected for a lone
    /// selection, and the ordinal position when two or more are selected.
    /// Derived from `glyph(for:in:)` so the spoken position always agrees
    /// with the visible numeral, including at the 99 cap.
    private func accessibilityValue(for id: String) -> String {
        switch Self.glyph(for: id, in: selected) {
        case .icon:
            return L10n.undoNotSelected.text
        case .checkmark:
            return L10n.undoSelected.text
        case let .ordinal(position):
            return String(format: L10n.undoSelectedPosition.text, locale: .current, position, selected.count)
        }
    }

    private func chipLabel(category: Category, glyph: ChipGlyph) -> some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            glyphView(category: category, glyph: glyph)
            Text(category.name)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(glyph == .icon ? Theme.textPrimary : Theme.textOnAccent)
        .padding(Theme.spacingChip)
        .frame(minHeight: Theme.minTapArea)
        .background(glyph == .icon ? Theme.backgroundSecondary : Theme.accentPrimary)
        .clipShape(Capsule())
        .overlay {
            if glyph == .icon {
                Capsule().stroke(Theme.hairline, lineWidth: 1)
            }
        }
    }

    /// The leading slot. Branch swaps (icon↔checkmark↔ordinal) fade via the
    /// opacity transition; digit-to-digit changes fade via the opacity
    /// content transition. The explicit animation is scoped to the slot so it
    /// survives ancestor nil-transactions (Track's `bottomFlow` keeps the
    /// Start/Stop swap instant without silencing this fade).
    @ViewBuilder
    private func glyphView(category: Category, glyph: ChipGlyph) -> some View {
        Group {
            switch glyph {
            case .icon:
                Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                    .font(.system(size: symbolFontSize, weight: .regular))
            case .checkmark:
                Image(systemName: "checkmark")
                    .font(.system(size: symbolFontSize, weight: .semibold))
            case let .ordinal(position):
                Text("\(position)")
                    .font(.system(size: ordinalFontSize(position: position), weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: symbolSlotSize, height: symbolFontSize)
        .accessibilityHidden(true)
        .transition(.opacity)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: Self.glyphFadeDuration), value: glyph)
    }
}

#if DEBUG
#Preview("TagSelector — with creation EN Light") {
    TagSelector(
        options: [
            Category(id: "c1", name: "Work", icon: "briefcase"),
            Category(id: "c2", name: "Sport", icon: "figure.run"),
        ],
        selected: ["c1"],
        onToggle: { _ in },
        onCreate: {},
        accessibilityId: "PreviewTags"
    )
    .padding()
}

#Preview("TagSelector — with creation RU Dark") {
    TagSelector(
        options: [
            Category(id: "c1", name: "Работа", icon: "briefcase"),
        ],
        selected: [],
        onToggle: { _ in },
        onCreate: {},
        accessibilityId: "PreviewTags"
    )
    .padding()
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}

#Preview("TagSelector — clamped viewport, many categories") {
    TagSelector(
        options: (1...12).map {
            Category(id: "c\($0)", name: "Category \($0)", icon: "tag")
        },
        selected: ["c1", "c3"],
        onToggle: { _ in },
        onCreate: {},
        accessibilityId: "PreviewTags"
    )
    .padding()
}
#endif
