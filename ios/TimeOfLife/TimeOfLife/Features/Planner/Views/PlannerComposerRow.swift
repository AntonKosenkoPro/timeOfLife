import SwiftUI

/// The bottom-fixed Today composer card (day-planner 9.1/10.1/11.1/17.5,
/// 7.1 no-resign, 21.1 no dismiss button): the persistent inline field
/// in the shared `FieldCard` chrome (secondary background against the
/// primary page, `minTapArea` minimum height, contrasting hairline border
/// in both appearances), so it reads as a card apart from the list.
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
/// requests). Return on an empty draft dismisses the keyboard — the only
/// submit-path resign allowed and the only keyboard-dismiss path (no
/// dismiss button). The composer never unmounts and no layout
/// jumps; the representable keeps its stable identity inside the card, so
/// first-responder survival is unchanged.
struct PlannerComposerRow: View {
    @ObservedObject var vm: PlannerViewModel
    /// Focus intent (issue #82 precedent — the binding belongs on the
    /// field itself, passed straight through to `PlannerComposerField`).
    let focused: FocusState<Bool>.Binding
    /// UIKit editing state of the field (drives the clear-button
    /// visibility).
    @Binding var editing: Bool

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
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
                }
            }
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .padding(.vertical, Theme.spacingSmall)
    }
}
