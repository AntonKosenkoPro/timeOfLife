import SwiftUI

/// Trailing clear (`×`) button for plain-text name fields
/// (feat-name-field-affordances): one tap empties the field. Shared by the
/// Track name field and the entry-form name row so both presentations stay
/// identical. Visibility is owned by the caller (shown only when the field
/// holds text and is editable).
struct ClearTextButton: View {
    /// Action run on tap (clears the caller's draft text).
    let action: () -> Void
    /// Accessibility identifier supplied by the caller
    /// (`TimerNameClearButton` / `EntryNameClearButton`).
    let accessibilityId: String

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: Theme.minTapArea, minHeight: Theme.minTapArea)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
        .accessibilityLabel(L10n.nameClear.text)
    }
}

#if DEBUG
#Preview("Clear Text Button") {
    ClearTextButton(action: {}, accessibilityId: "PreviewClearButton")
        .padding()
}
#endif
