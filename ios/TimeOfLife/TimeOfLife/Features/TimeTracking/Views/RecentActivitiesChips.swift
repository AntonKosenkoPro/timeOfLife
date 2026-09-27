import SwiftUI

/// The Track Recents chip flow (timer-capture-experience spec,
/// design D5). Presents up to six most-recently-used exact entry texts as a
/// wrapping flow of chips with 44 pt tap targets; chips wrap onto additional
/// rows and never require horizontal scrolling.
///
/// Each chip shows the icon of the first category of that exact text's
/// newest committed entry (first by stored position, resolved through the
/// id-to-Category map); texts without categories render name-only. The
/// prepared text's chip keeps its icon and switches to a filled accent
/// presentation (accent background, on-accent text, accent border) — the
/// same non-color-only selected treatment as `TagSelector` (fill + contrast,
/// no checkmark, so chips stay compact). Chips wrap via the shared
/// `FlowLayout` with equal `Theme.spacingSmall` gaps.
struct RecentActivitiesChips: View {
    let recents: [TrackViewModel.RecentEntry]
    let categories: [String: Category]
    let selectedText: String?
    let onSelect: (TrackViewModel.RecentEntry) -> Void

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    /// The capped, most-recently-used-first slice (the store already sorts
    /// by the text's newest `started_at`).
    private var capped: [TrackViewModel.RecentEntry] { Self.recents(from: recents) }

    /// The capped, most-recently-used-first slice of the given recents.
    /// Pure (no view state), so `nonisolated` like `EntryRow.accessibilityLabel`.
    nonisolated static func recents(
        from recents: [TrackViewModel.RecentEntry],
        limit: Int = 6
    ) -> [TrackViewModel.RecentEntry] {
        Array(recents.prefix(limit))
    }

    var body: some View {
        FlowLayout(spacing: Theme.spacingSmall) {
            ForEach(capped) { recent in
                chip(recent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sizing

    /// The subheadline metrics object used for the icon glyph size.
    private var metrics: UIFontMetrics { UIFontMetrics(forTextStyle: .subheadline) }

    /// A trait collection matching the SwiftUI environment's effective
    /// Dynamic Type size, so the icon glyph scales with rendering
    /// (also under a `.dynamicTypeSize` environment override,
    /// which `UIFont.preferredFont` alone would not reflect).
    private var sizeTrait: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
    }

    /// Icon glyph size at the effective size.
    private var symbolFontSize: CGFloat {
        metrics.scaledFont(for: UIFont.systemFont(ofSize: 14), compatibleWith: sizeTrait).pointSize
    }

    /// Fixed icon slot so wide SF Symbols stay fully visible and the
    /// measured chip width is exact.
    private var symbolSlotSize: CGFloat {
        ceil(symbolFontSize * 1.5)
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(_ recent: TrackViewModel.RecentEntry) -> some View {
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

    private func chipLabel(recent: TrackViewModel.RecentEntry, isSelected: Bool) -> some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            if let categoryID = recent.firstCategoryID,
               let category = categories[categoryID] {
                Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                    .font(.system(size: symbolFontSize))
                    .frame(width: symbolSlotSize)
                    .accessibilityHidden(true)
            }
            Text(recent.text)
                .font(.subheadline.weight(.medium))
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
        TrackViewModel.RecentEntry(text: "Deep work", categoryIDs: ["c1"], firstCategoryID: "c1"),
        TrackViewModel.RecentEntry(text: "Reading", categoryIDs: ["c2"], firstCategoryID: "c2"),
        TrackViewModel.RecentEntry(text: "Gym session", categoryIDs: ["c3"], firstCategoryID: "c3"),
        TrackViewModel.RecentEntry(text: "Planning", categoryIDs: [], firstCategoryID: nil),
        TrackViewModel.RecentEntry(text: "A very long entry name that truncates", categoryIDs: ["c1"], firstCategoryID: "c1")
    ]
    return RecentActivitiesChips(
        recents: recents,
        categories: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }),
        selectedText: "Deep work"
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
