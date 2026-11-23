// swiftlint:disable file_length
// (view + fit-plan wiring + off-screen measurement pass + previews form one
// unit; splitting would scatter the plan inputs across files.)
import SwiftUI

/// The Track Recents chip flow (timer-capture-experience spec,
/// design D5). Presents up to ten most-recently-used exact entry texts as
/// a wrapping flow of chips with 44 pt tap targets. The view mounts only the
/// fitting newest-first prefix: when five or more candidates fit the finite
/// host budget it renders that prefix as a plain (non-scrolling) flow, and
/// only a smaller fitting set falls back to offering the newest five through
/// an internally scrolling viewport — so Recents overflow alone never grows
/// the Track page and never fights page gestures. Omitted candidates are
/// never mounted: no invisible interactive or accessibility overflow.
///
/// Each chip shows the icon of the first category of that exact text's
/// newest committed entry (first by stored position, resolved through the
/// id-to-Category map); texts without categories render name-only. The
/// prepared text's chip keeps its icon and switches to a filled accent
/// presentation (accent background, on-accent text, accent border) — the
/// same non-color-only selected treatment as `TagSelector` (fill + contrast,
/// no checkmark, so chips stay compact). Chips wrap via the shared
/// `FlowLayout` with equal `Theme.spacingSmall` gaps.
///
/// Fitting reuses the actual rendered chip sizes: an off-screen measurement
/// pass lays the full candidate set out at the same container width (same
/// fonts, icon slots, and selected presentation), non-interactive and
/// accessibility-hidden, and the pure `RecentsFitPolicy` packs those sizes
/// with the shared `FlowPacking` arithmetic — the same greedy packing the
/// visible `FlowLayout` uses for placement.
struct RecentActivitiesChips: View {
    let recents: [ExactName]
    let categories: [String: Category]
    let selectedText: String?
    let onSelect: (ExactName) -> Void
    /// Finite host budget for the chip area (Track): the host viewport minus
    /// the measured siblings, gaps, and tab-bar margin (see `TrackContent`).
    /// Nil (or non-positive/non-finite) keeps a bounded provisional one-row
    /// layout until the viewport measures.
    let availableHeight: CGFloat?

    init(
        recents: [ExactName],
        categories: [String: Category],
        selectedText: String?,
        availableHeight: CGFloat? = nil,
        onSelect: @escaping (ExactName) -> Void
    ) {
        self.recents = recents
        self.categories = categories
        self.selectedText = selectedText
        self.availableHeight = availableHeight
        self.onSelect = onSelect
    }

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    /// Scroll-edge state for the viewport dividers (shared `ChipViewport`
    /// math — same clamp and fade contract as the tag selector). Only
    /// meaningful in the scrolling presentation; reset whenever the offered
    /// set or viewport changes.
    @State private var edges = ChipViewport.Edges()

    /// Measured container width (background reader): 0 until the first
    /// layout pass.
    @State private var containerWidth: CGFloat = 0

    /// Rendered chip sizes from the off-screen measurement pass, keyed by
    /// exact text. Empty until the pass reports.
    @State private var measuredSizes: [String: CGSize] = [:]

    /// Last fully-measured plan, retained across transient measurement gaps
    /// (a newly arrived candidate the off-screen pass has not reported yet,
    /// a transient zero width). Reused only for the same candidate count,
    /// container width, and host budget — geometry can change during a nil-
    /// measurement window, and a count-only key would serve a stale larger-
    /// budget plan into unclamped static flow. Without retention, one
    /// unmeasured text discards the measured fit for all candidates and the
    /// view flashes from a fitting static flow into the provisional scroller
    /// for a frame.
    @State private var stickyPlan: (
        candidateCount: Int,
        containerWidth: CGFloat,
        budget: CGFloat?,
        plan: RecentsFitPolicy.Plan
    )?

    /// The capped, most-recently-used-first slice (the store already sorts
    /// by the text's newest `started_at`; the cap is
    /// `TrackViewModel.recentsLimit`).
    private var candidates: [ExactName] { Self.recents(from: recents) }

    /// The capped, most-recently-used-first slice of the given recents.
    /// Pure (no view state), so `nonisolated` like `EntryRow.accessibilityLabel`.
    nonisolated static func recents(
        from recents: [ExactName],
        limit: Int = TrackViewModel.recentsLimit
    ) -> [ExactName] {
        Array(recents.prefix(limit))
    }

    /// Measured sizes in candidate order, or nil while the measurement pass
    /// has not reported every candidate (partial sizes would flap the plan).
    private var readySizes: [CGSize]? {
        guard containerWidth.isFinite, containerWidth > 0, !candidates.isEmpty else { return nil }
        var sizes: [CGSize] = []
        sizes.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard let size = measuredSizes[candidate.text] else { return nil }
            sizes.append(size)
        }
        return sizes
    }

    /// Measured fit when every candidate has reported, else nil while the
    /// measurement pass has not caught up.
    private var resolvedPlan: RecentsFitPolicy.Plan? {
        guard let sizes = readySizes else { return nil }
        return RecentsFitPolicy.plan(
            itemSizes: sizes,
            containerWidth: containerWidth,
            spacing: Theme.spacingSmall,
            budget: availableHeight,
            rowHeight: chipRowHeight,
            maxCandidates: TrackViewModel.recentsLimit
        )
    }

    /// The mounting plan for this pass: measured fit, the retained plan
    /// across a transient measurement gap, or the bounded provisional
    /// fallback while measuring.
    private var effectivePlan: RecentsFitPolicy.Plan {
        if let resolvedPlan {
            return resolvedPlan
        }
        if let stickyPlan,
           stickyPlan.candidateCount == candidates.count,
           stickyPlan.containerWidth == containerWidth,
           stickyPlan.budget == availableHeight {
            return stickyPlan.plan
        }
        return RecentsFitPolicy.provisional(
            candidateCount: candidates.count,
            rowHeight: chipRowHeight,
            maxCandidates: TrackViewModel.recentsLimit
        )
    }

    /// The newest-first prefix actually mounted this pass.
    private var offered: [ExactName] {
        Array(candidates.prefix(effectivePlan.offered))
    }

    /// Identity for the scrolling viewport: the offered texts only, so a
    /// viewport-only change (host budget) keeps the scroll offset instead of
    /// recreating the scroller. Edge dividers reset on appear and on the
    /// static/scrolling transition (see `body`), not here.
    private var offeredIdentifier: String {
        offered.map(\.text).joined(separator: "\u{1F}")
    }

    /// Chip row height: subheadline line height at the environment's Dynamic
    /// Type size plus uniform padding, floored at the 44 pt target so the
    /// floor holds under Dynamic Type.
    private var chipRowHeight: CGFloat {
        let lineHeight = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: sizeTrait
        ).lineHeight
        return max(Theme.minTapArea, lineHeight + 2 * 12)
    }

    var body: some View {
        Group {
            if effectivePlan.scrolling {
                scrollingFlow
            } else {
                staticFlow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(measureBackground)
        .onChange(of: resolvedPlan) {
            if let resolvedPlan {
                stickyPlan = (candidates.count, containerWidth, availableHeight, resolvedPlan)
            }
        }
        // Dynamic Type changes every chip size (subheadline font, icon slot,
        // row height): drop the text-keyed measurements and the retained plan
        // so the gap falls back to the bounded provisional instead of serving
        // a stale fit. Clearing measurements alone is not enough — the sticky
        // plan would still serve the old prefix until the pass re-reports.
        .onChange(of: dynamicTypeSize) {
            measuredSizes = [:]
            stickyPlan = nil
        }
        // The static/scrolling branches are distinct subtrees: a fresh
        // scrolling insertion never fires its own onChange, so the edge
        // dividers reset on the transition itself (and on appear below).
        .onChange(of: effectivePlan.scrolling) {
            edges = ChipViewport.Edges()
        }
    }

    /// The fitting-prefix presentation: a plain wrapping flow with no scroll
    /// view, so it never owns gestures and never fights page scrolling.
    private var staticFlow: some View {
        FlowLayout(spacing: Theme.spacingSmall) {
            ForEach(offered) { recent in
                chip(recent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The newest-five fallback presentation: hugs its offered content up to
    /// the planned viewport and scrolls internally beyond it — never pushing
    /// siblings or the page. Zero-layout edge hairlines overlay the
    /// ScrollView's outer frame (not VStack siblings, never scrolled
    /// content), so the viewport total stays within the measured host budget
    /// as the top hairline fades in — top fades in once chips scroll under
    /// it, bottom fades out at the content end, both hidden when everything
    /// fits.
    private var scrollingFlow: some View {
        ScrollView(.vertical) {
            FlowLayout(spacing: Theme.spacingSmall) {
                ForEach(offered) { recent in
                    chip(recent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Content inset carries the border clearance (same as
            // `TagSelector`): when the offered set fits, `fixedSize` hugs
            // the content height, so frame slack alone never
            // materializes. 1 pt top/bottom keeps the chip strokes
            // fully visible.
            .padding(.vertical, ChipViewport.borderBleed / 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: effectivePlan.viewport)
        .fixedSize(horizontal: false, vertical: true)
        .id(offeredIdentifier)
        // A recreated scroller (new offered texts) and a fresh static →
        // scrolling insertion both start at offset zero, so the dividers
        // restart from the top edge; geometry updates correct them after.
        .onAppear { edges = ChipViewport.Edges() }
        .onChange(of: offeredIdentifier) { edges = ChipViewport.Edges() }
        .onScrollGeometryChange(for: ChipViewport.Edges.self, of: { geometry in
            ChipViewport.edges(
                offsetY: geometry.contentOffset.y,
                containerHeight: geometry.containerSize.height,
                contentHeight: geometry.contentSize.height
            )
        }, action: { _, new in
            edges = new
        })
        // Overlays add zero layout height and ignore hits, so divider
        // visibility never changes geometry or intercepts chip taps/scroll.
        .overlay(alignment: .top) {
            if !edges.atTop {
                Divider().background(Theme.hairline)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if !edges.atEnd {
                Divider().background(Theme.hairline)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: edges)
    }

    /// Width capture plus the off-screen measurement pass: lays the full
    /// candidate set out at the container width with the real chip views
    /// (same fonts, icon slots, selected presentation), reporting each
    /// chip's rendered size. Non-interactive and accessibility-hidden, and
    /// a background so it never contributes to layout.
    private var measureBackground: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                if proxy.size.width > 0 {
                    FlowLayout(spacing: Theme.spacingSmall) {
                        ForEach(candidates) { recent in
                            chip(recent)
                                .background {
                                    GeometryReader { chipProxy in
                                        Color.clear.preference(
                                            key: ChipSizesKey.self,
                                            value: [recent.text: chipProxy.size]
                                        )
                                    }
                                }
                        }
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .preference(key: ChipAreaWidthKey.self, value: proxy.size.width)
        }
        .onPreferenceChange(ChipAreaWidthKey.self) {
            if containerWidth != $0 { containerWidth = $0 }
        }
        .onPreferenceChange(ChipSizesKey.self) {
            if measuredSizes != $0 { measuredSizes = $0 }
        }
    }

    /// A trait collection matching the SwiftUI environment's effective
    /// Dynamic Type size, so the icon glyph scales with rendering
    /// (also under a `.dynamicTypeSize` environment override,
    /// which `UIFont.preferredFont` alone would not reflect).
    private var sizeTrait: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
    }

    /// Icon glyph size at the effective size.
    private var symbolFontSize: CGFloat {
        let metrics = UIFontMetrics(forTextStyle: .subheadline)
        return metrics.scaledFont(
            for: UIFont.systemFont(ofSize: 14),
            compatibleWith: sizeTrait
        ).pointSize
    }

    /// Fixed icon slot so wide SF Symbols stay fully visible and the
    /// measured chip width is exact.
    private var symbolSlotSize: CGFloat {
        DynamicTypeMetrics.symbolSlotSize(
            basePointSize: 14,
            textStyle: .subheadline,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    @ViewBuilder
    private func chip(_ recent: ExactName) -> some View {
        let isSelected = selectedText == recent.text
        Button {
            onSelect(recent)
        } label: {
            chipLabel(recent: recent, isSelected: isSelected)
        }
        .accessibilityLabel(String(format: L10n.timerSelectActivity.text, recent.text))
        .accessibilityValue(isSelected ? L10n.undoSelected.text : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("TimerSuggestion(\(recent.text))")
    }

    private func chipLabel(recent: ExactName, isSelected: Bool) -> some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            if let categoryID = recent.firstCategoryID,
               let category = categories[categoryID] {
                Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                    .font(.system(size: symbolFontSize))
                    .frame(width: symbolSlotSize)
                    .accessibilityHidden(true)
            }
            Text(recent.text)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isSelected ? Theme.textOnAccent : Theme.textPrimary)
        .padding(.horizontal, Theme.spacingMedium)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.minTapArea)
        .background(isSelected ? Theme.accentPrimary : Theme.backgroundSecondary)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(
                isSelected ? Theme.accentPrimary : Theme.hairline,
                lineWidth: 0.7
            )
        }
    }
}

/// Container width reported by the Recents background reader.
private struct ChipAreaWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Rendered chip sizes from the off-screen measurement pass, keyed by exact
/// text. Later reports win per key so re-measurement converges.
private struct ChipSizesKey: PreferenceKey {
    static let defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension DynamicTypeSize {
    /// The `UIContentSizeCategory` equivalent of the environment's Dynamic
    /// Type size, used to build a measurement trait collection.
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

#if DEBUG
#Preview("Recents — Icons, selected, wrapped") {
    let categories = [
        Category(id: "c1", name: "Work", icon: "laptopcomputer"),
        Category(id: "c2", name: "Study", icon: "book"),
        Category(id: "c3", name: "Sport", icon: "figure.run")
    ]
    let recents = [
        ExactName(text: "Deep work", categoryIDs: ["c1"], firstCategoryID: "c1"),
        ExactName(text: "Reading", categoryIDs: ["c2"], firstCategoryID: "c2"),
        ExactName(text: "Gym session", categoryIDs: ["c3"], firstCategoryID: "c3"),
        ExactName(text: "Planning", categoryIDs: [], firstCategoryID: nil),
        ExactName(text: "A very long entry name that truncates", categoryIDs: ["c1"], firstCategoryID: "c1")
    ]
    return RecentActivitiesChips(
        recents: recents,
        categories: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }),
        selectedText: "Deep work",
        availableHeight: 400
    ) { _ in }
    .padding()
    .background(Theme.backgroundPrimary)
}

#Preview("Recents — Ten, fit prefix without scrolling") {
    let categories = [
        Category(id: "c1", name: "Work", icon: "laptopcomputer"),
        Category(id: "c2", name: "Study", icon: "book"),
        Category(id: "c3", name: "Sport", icon: "figure.run")
    ]
    let recents = (0..<10).map { index in
        let categorized = index < 6
        return ExactName(
            text: "Entry number \(index)",
            categoryIDs: categorized ? ["c1"] : [],
            firstCategoryID: categorized ? ["c1", "c2", "c3"][index / 2] : nil
        )
    }
    return RecentActivitiesChips(
        recents: recents,
        categories: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }),
        selectedText: "Entry number 0",
        availableHeight: 400
    ) { _ in }
    .padding()
    .background(Theme.backgroundPrimary)
}

#Preview("Recents — Empty") {
    RecentActivitiesChips(
        recents: [],
        categories: [:],
        selectedText: nil
    ) { _ in }
    .padding()
    .background(Theme.backgroundPrimary)
}
#endif
