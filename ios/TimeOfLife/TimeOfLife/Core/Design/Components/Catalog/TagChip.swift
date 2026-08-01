import SwiftUI

/// Read-only category pill: color dot + name (F3).
///
/// Displayed on `ActivityRow` and entries to surface an activity's tags.
/// No tap action, no selection state.
struct TagChip: View {
    let name: String
    let color: ActivityColor

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.activityColor(color))
                .frame(width: 6, height: 6)

            Text(name)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.spacingSmall)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.backgroundSecondary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag, \(name)")
    }
}

#if DEBUG

#Preview("EN Light") {
    HStack {
        TagChip(name: "Work", color: .blue)
        TagChip(name: "Fitness", color: .green)
        TagChip(name: "Reading", color: .purple)
    }
    .padding()
}

#Preview("RU Dark") {
    HStack {
        TagChip(name: "Работа", color: .blue)
        TagChip(name: "Фитнес", color: .green)
    }
    .padding()
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}

#endif
