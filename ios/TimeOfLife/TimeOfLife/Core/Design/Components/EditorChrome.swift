import SwiftUI

/// Shared editor chrome extracted from the duplicated TrackContent /
/// NamePicker / LogTime / CategoryEditor surfaces (no behavior change:
/// identical tokens and padding at every adopted call site).
///
/// - `FieldCard`: the rounded secondary-background field chrome (name rows,
///   locked name labels, picker field).
/// - `DestructiveBottomButton`: the bottom-of-page destructive Delete.
/// - `EditorToolbar`: the Calendar-grammar X-dismiss / checkmark-confirm
///   toolbar pair shared by the Log Time and Category Editor forms.

/// Rounded secondary-background field chrome: horizontal `spacingMedium`
/// padding, `minTapArea` minimum height, `cornerRadius` with a 0.7pt
/// `hairline` stroke. Matches the former NamePicker field card and the
/// Track name row / locked label pixel-for-pixel.
struct FieldCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, Theme.spacingMedium)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.hairline, lineWidth: 0.7)
            }
    }
}

/// Bottom-of-page destructive Delete (EDIT + LOCKED entry form, Category
/// Editor edit mode): headline danger label, full-width `minTapArea` tap
/// target, secondary background, `cornerRadius`. Identical to both former
/// per-screen delete sections.
struct DestructiveBottomButton: View {
    let title: String
    let accessibilityId: String
    let action: () -> Void

    init(title: String, accessibilityId: String, action: @escaping () -> Void) {
        self.title = title
        self.accessibilityId = accessibilityId
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
                .contentShape(Rectangle())
        }
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier(accessibilityId)
    }
}

/// Calendar-grammar editor toolbar: X dismiss (cancellation) + checkmark
/// confirm (confirmation), shared by the Log Time form and the Category
/// Editor. Labels, identifiers, and disabled gates are caller-supplied so
/// both presentations keep their exact accessibility contracts.
///
/// `onDismiss` is an autoclosure (the `FormCard.resignFocus` precedent) so
/// call sites keep single-trailing-closure form per
/// `multiple_closures_with_trailing_closure`: `onDismiss: dismiss()` plus
/// a trailing confirm.
struct EditorToolbar: ToolbarContent {
    let showsDismiss: Bool
    let dismissAccessibilityLabel: String
    let dismissAccessibilityId: String
    let isDismissDisabled: Bool
    let onDismiss: () -> Void
    let showsConfirm: Bool
    let confirmAccessibilityLabel: String
    let confirmAccessibilityId: String
    let isConfirmDisabled: Bool
    let onConfirm: () -> Void

    init(
        showsDismiss: Bool,
        dismissAccessibilityLabel: String,
        dismissAccessibilityId: String,
        isDismissDisabled: Bool,
        onDismiss: @autoclosure @escaping () -> Void,
        showsConfirm: Bool,
        confirmAccessibilityLabel: String,
        confirmAccessibilityId: String,
        isConfirmDisabled: Bool,
        onConfirm: @escaping () -> Void
    ) {
        self.showsDismiss = showsDismiss
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
        self.dismissAccessibilityId = dismissAccessibilityId
        self.isDismissDisabled = isDismissDisabled
        self.onDismiss = onDismiss
        self.showsConfirm = showsConfirm
        self.confirmAccessibilityLabel = confirmAccessibilityLabel
        self.confirmAccessibilityId = confirmAccessibilityId
        self.isConfirmDisabled = isConfirmDisabled
        self.onConfirm = onConfirm
    }

    var body: some ToolbarContent {
        if showsDismiss {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .disabled(isDismissDisabled)
                .accessibilityLabel(dismissAccessibilityLabel)
                .accessibilityIdentifier(dismissAccessibilityId)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if showsConfirm {
                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                }
                .disabled(isConfirmDisabled)
                .accessibilityLabel(confirmAccessibilityLabel)
                .accessibilityIdentifier(confirmAccessibilityId)
            }
        }
    }
}
