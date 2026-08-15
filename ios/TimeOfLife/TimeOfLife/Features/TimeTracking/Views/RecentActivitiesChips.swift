import SwiftUI

/// The Track Recents chip flow (timer-capture-experience spec,
/// refine-track-recents D2/D3/D4). Presents up to six most-recently-used
/// Activities as a wrapping flow of chips with 44 pt tap targets; chips wrap
/// onto additional rows and never require horizontal scrolling.
///
/// Each chip shows the icon of the first Category assigned to its Activity
/// (first by assignment position, resolved through the id-to-Category map);
/// Activities without Categories render name-only. The prepared Activity's
/// chip keeps its icon and switches to a filled accent presentation (accent
/// background, on-accent text, accent border) — the same non-color-only
/// selected treatment as `TagSelector` (fill + contrast, no checkmark, so
/// chips stay compact). Rows are packed from measured chip widths because
/// the `Layout` protocol is iOS 16+ and the app supports iOS 15 (same
/// algorithm as `TagSelector`, category-management D9).
struct RecentActivitiesChips: View {
    let activities: [Activity]
    let categories: [String: Category]
    let selectedID: String?
    let onSelect: (Activity) -> Void

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @State private var containerWidth: CGFloat = 0

    /// The capped, most-recently-used-first slice (the store already sorts
    /// by `last_used_at`).
    private var recents: [Activity] { Self.recents(from: activities) }

    /// The capped, most-recently-used-first slice of the given activities.
    static func recents(from activities: [Activity], limit: Int = 6) -> [Activity] {
        Array(activities.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: Theme.spacingSmall) {
                    ForEach(rows[rowIndex]) { activity in
                        chip(activity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: RecentsWidthKey.self, value: geometry.size.width)
            }
        )
        .onPreferenceChange(RecentsWidthKey.self) { containerWidth = $0 }
    }

    // MARK: - Sizing

    /// The subheadline metrics object used for both the icon glyph and the
    /// measured name width.
    private var metrics: UIFontMetrics { UIFontMetrics(forTextStyle: .subheadline) }

    /// A trait collection matching the SwiftUI environment's effective
    /// Dynamic Type size, so measurement and rendering always scale
    /// together (also under a `.dynamicTypeSize` environment override,
    /// which `UIFont.preferredFont` alone would not reflect).
    private var sizeTrait: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
    }

    /// The name font at the effective size, used to measure chip widths.
    private var nameFont: UIFont {
        metrics.scaledFont(for: UIFont.systemFont(ofSize: 17), compatibleWith: sizeTrait)
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

    /// Natural chip width: optional icon slot + name + uniform horizontal
    /// padding.
    private func chipWidth(for activity: Activity) -> CGFloat {
        let name = activity.name.size(withAttributes: [.font: nameFont]).width
        let iconWidth = activity.categoryIDs.first != nil
            ? symbolSlotSize + Theme.spacingExtraSmall
            : 0
        return iconWidth + name + Theme.spacingMedium * 2
    }

    /// Greedy packing: fill each row with as many content-sized chips as fit,
    /// keeping equal `Theme.spacingSmall` gaps. Until the container width is
    /// measured, every chip sits on its own row (single pass, no flicker).
    private var rows: [[Activity]] {
        guard containerWidth > 0 else { return recents.map { [$0] } }
        var result: [[Activity]] = []
        var current: [Activity] = []
        var currentWidth: CGFloat = 0
        for activity in recents {
            let width = min(chipWidth(for: activity), containerWidth)
            let projected = currentWidth + (current.isEmpty ? 0 : Theme.spacingSmall) + width
            if current.isEmpty || projected <= containerWidth {
                current.append(activity)
                currentWidth = projected
            } else {
                result.append(current)
                current = [activity]
                currentWidth = width
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(_ activity: Activity) -> some View {
        let isSelected = selectedID == activity.id
        let label = chipLabel(activity: activity, isSelected: isSelected)
        // A chip wider than the container gets a fixed container-width frame
        // so its name truncates instead of overflowing.
        if containerWidth > 0, chipWidth(for: activity) > containerWidth {
            Button {
                onSelect(activity)
            } label: {
                label.frame(width: containerWidth)
            }
            .accessibilityLabel(String(format: L10n.timerSelectActivity.text, activity.name))
            .accessibilityValue(isSelected ? L10n.undoSelected.text : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("TimerSuggestion(\(activity.id))")
        } else {
            Button {
                onSelect(activity)
            } label: {
                label
            }
            .accessibilityLabel(String(format: L10n.timerSelectActivity.text, activity.name))
            .accessibilityValue(isSelected ? L10n.undoSelected.text : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("TimerSuggestion(\(activity.id))")
        }
    }

    private func chipLabel(activity: Activity, isSelected: Bool) -> some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            if let categoryID = activity.categoryIDs.first,
               let category = categories[categoryID] {
                Image(systemName: CatalogIcon(validated: category.icon).displaySymbol)
                    .font(.system(size: symbolFontSize))
                    .frame(width: symbolSlotSize)
                    .accessibilityHidden(true)
            }
            Text(activity.name)
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

private struct RecentsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
    let activities = [
        Activity(id: "a1", name: "Deep work", categoryIDs: ["c1"]),
        Activity(id: "a2", name: "Reading", categoryIDs: ["c2"]),
        Activity(id: "a3", name: "Gym session", categoryIDs: ["c3"]),
        Activity(id: "a4", name: "Planning", categoryIDs: []),
        Activity(id: "a5", name: "A very long activity name that truncates", categoryIDs: ["c1"])
    ]
    return RecentActivitiesChips(
        activities: activities,
        categories: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }),
        selectedID: "a1"
    ) { _ in }
    .padding()
    .background(Theme.backgroundPrimary)
}

#Preview("Recents — Empty") {
    RecentActivitiesChips(
        activities: [],
        categories: [:],
        selectedID: nil
    ) { _ in }
    .padding()
    .background(Theme.backgroundPrimary)
}
#endif
