## ADDED Requirements

### Requirement: Editor sheets support the full-height toolbar-chrome presentation
Editor sheets MAY use the Log Time presentation instead of the collapsing-header one: a full-height sheet (no medium detent — closed or fully open) with an inline title, an `xmark` cancel button at the cancellation action, and a `checkmark` confirm button at the confirmation action. The confirm button SHALL be disabled while the draft is invalid or a save is in flight; Cancel SHALL be disabled (and swipe-down dismissal SHALL remain disabled) while a save is in flight. When the keyboard appears, the sheet SHALL NOT resize or jump, and scrollable content SHALL remain top-anchored with the focused field fully visible (no auto-scroll displacement, no content parked under the navigation bar).

#### Scenario: Full-height editor opens without detents
- **WHEN** the category editor is presented
- **THEN** the sheet opens full-height with an inline title, X, and ✓ — no medium-detent stop, no collapse animation to settle

#### Scenario: Confirm gated on validity
- **WHEN** the category draft name is empty/whitespace-only or a save is in flight
- **THEN** the ✓ button is disabled and no save is attempted

#### Scenario: Cancel discards the draft
- **WHEN** the user activates the X button (and no save is in flight)
- **THEN** the sheet dismisses and the persisted catalog remains unchanged

#### Scenario: Keyboard opens without sheet jump
- **WHEN** the editor autofocuses its name field and the keyboard appears
- **THEN** the sheet stays full-height (no resize jump) and the content stays top-anchored with the name field fully visible

## MODIFIED Requirements

### Requirement: Keyboard-safe pinned action bar is preserved
Editors using the bottom action-bar presentation SHALL keep their primary action pinned above the keyboard via the bottom safe-area inset, and the scrollable content SHALL reserve the measured height of that bar so no field is permanently hidden behind it. The collapsing header SHALL NOT interfere with the pinned bar or its keyboard-following behavior. Editors using the full-height toolbar-chrome presentation instead keep their confirm action in the always-visible toolbar, which needs no keyboard-following behavior.

#### Scenario: Keyboard appears in an editor with the collapsing header
- **WHEN** the editor opens and focuses its name field
- **THEN** the pinned action bar follows the keyboard, the reserved scroll space matches the bar height, and the collapsing header continues to behave normally
