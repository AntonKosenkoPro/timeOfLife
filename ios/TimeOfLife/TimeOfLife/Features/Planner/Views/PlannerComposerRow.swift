import SwiftUI

/// Visibility rule for the composer keyboard-dismiss control (day-planner
/// 18.3): shown whenever the field is being edited — including an empty
/// draft, whose only other way off the keyboard is Return-on-empty.
/// Text-independent, unlike `ClearButtonVisibility` (which also needs
/// non-empty text). Pinned here because SwiftUI mounting is not
/// unit-testable (the `ClearButtonVisibility` precedent).
enum ComposerDismissVisibility {
    static func shouldShow(isEditing: Bool) -> Bool { isEditing }
}

/// The bottom-fixed Today composer card (day-planner 9.1/10.1/11.1/17.5,
/// 7.1 no-resign, 18.3 dismiss): the persistent inline field in the shared
/// `FieldCard` chrome (secondary background against the primary page,
/// `minTapArea` minimum height, contrasting hairline border in both
/// appearances), so it reads as a card apart from the list.
///
/// Return prepends one task at the top, clears the draft, and focus never
/// leaves — the UIKit-backed field declines the Return default resign at
/// dispatch (day-planner 7.1), so the keyboard never animates away no
/// matter how slow the store/reload round-trip is. There is no visible Add
/// button (day-planner 11.1): submission runs through Return or the
/// composer's Add accessibility action, so VoiceOver retains a submit path.
/// A persistent leading plus (day-planner 17.5 — the placeholder disappears
/// while typing, so the affordance names the purpose with and without text;
/// decorative, hidden from assistive tech) opens the row, and a trailing
/// clear button (the Track × grammar — small dim trailing × while editing)
/// empties the draft without dismissing the keyboard or losing focus; its
/// visibility follows the UIKit editing state mirrored from the field
/// delegate (ground truth), not the focus flag (which only issues focus
/// requests). While editing, a trailing keyboard-dismiss control
/// (`keyboard.chevron.compact.down`, `L10n.plannerDismissKeyboard`) offers
/// explicit keyboard dismissal without submitting; Return on an empty draft
/// dismisses too — the only submit-path resign allowed (day-planner 18.3).
/// The composer never unmounts and no layout jumps; the representable keeps
/// its stable identity inside the card, so first-responder survival is
/// unchanged.
struct PlannerComposerRow: View {
    @ObservedObject var vm: PlannerViewModel
    /// Focus intent (issue #82 precedent — the binding belongs on the
    /// field itself, passed straight through to `PlannerComposerField`).
    let focused: FocusState<Bool>.Binding
    /// UIKit editing state of the field (drives clear/dismiss visibility).
    @Binding var editing: Bool
    /// Dismiss requests (day-planner 18.3): the dismiss control bumps this;
    /// the field resigns once per new value. Submit never touches it.
    @Binding var dismissID: Int

    var body: some View {
        FieldCard {
            HStack(spacing: Theme.spacingSmall) {
                Image(systemName: "plus")
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                PlannerComposerField(
                    text: $vm.draft,
                    placeholder: L10n.plannerComposerPlaceholder.text,
                    focused: focused,
                    accessibilityIdentifier: "PlannerComposerField",
                    dismissID: dismissID,
                    onReturn: { Task { await vm.submit() } },
                    onEditingChanged: { editing = $0 }
                )
                .accessibilityAction(named: Text(L10n.plannerAdd.text)) {
                    Task { await vm.submit() }
                }
                if ClearButtonVisibility.shouldShow(isFocused: editing, text: vm.draft) {
                    ClearTextButton(
                        action: {
                            vm.draft = ""
                            focused.wrappedValue = true
                        },
                        accessibilityId: "PlannerComposerClear"
                    )
                }
                // Keyboard-dismiss control (day-planner 18.3): explicit
                // user intent while editing — the field resigns without
                // submitting. Same visibility family as the clear button
                // (editing only), so an empty draft still offers a way off
                // the keyboard alongside Return-on-empty.
                if ComposerDismissVisibility.shouldShow(isEditing: editing) {
                    Button {
                        dismissID += 1
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(
                                minWidth: Theme.minTapArea,
                                minHeight: Theme.minTapArea,
                                alignment: .trailing
                            )
                            .padding(.trailing, Theme.spacingSmall)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.plannerDismissKeyboard.text)
                    .accessibilityIdentifier("PlannerComposerDismiss")
                }
            }
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .padding(.vertical, Theme.spacingSmall)
    }
}
