## ADDED Requirements

### Requirement: Editor autofocus engages after presentation settles
Editor sheets that autofocus a field on appear SHALL engage focus only after the sheet presentation animation has settled, so the keyboard-driven auto-scroll computes against final layout and the focused field lands fully in viewport. If the sheet is dismissed before focus engages, the pending autofocus SHALL be cancelled and focus SHALL NOT be forced onto a disappearing view.

#### Scenario: Autofocus lands the field fully in viewport
- **WHEN** the category editor opens in create or edit mode and autofocus engages
- **THEN** the name field is fully visible (not clipped by the navigation bar, keyboard, or sheet edge) with the caret visible and the keyboard open

#### Scenario: Dismiss before autofocus cancels cleanly
- **WHEN** the user dismisses the editor sheet before the settled autofocus fires
- **THEN** the sheet dismisses normally with no focus change, no stray keyboard, and no warning
