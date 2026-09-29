## MODIFIED Requirements

### Requirement: Unified entry form field order

The unified entry form SHALL lay out its input cards in exactly this order in every mode (CREATE, EDIT, LOCKED): Activity name → Start time → End time → Categories → Notes. Start and Ends SHALL be separate cards (one `timeRow` each with its own date + time pills and inline single-open picker), not one combined Starts/Ends card. The validity gate, picker behavior (single-open, device locale/calendar), mode chrome (titles/actions/LOCKED dimming + provenance note), and bottom destructive Delete are unchanged.

#### Scenario: Card order in CREATE mode

- **WHEN** the Log Time sheet opens for a new entry
- **THEN** the cards read top-to-bottom: Name, Start, End, Categories, Notes

#### Scenario: Card order in EDIT mode

- **WHEN** the form opens for an existing `manual` entry
- **THEN** the cards read top-to-bottom: Name, Start, End, Categories, Notes with the same pills/pickers as creation

#### Scenario: Card order in LOCKED mode

- **WHEN** the form opens for an imported entry
- **THEN** the cards read top-to-bottom: Name, Start, End, Categories, Notes, disabled-dimmed with the provenance note and no Save action

### Requirement: All native gestures work in the entry form

The entry form SHALL NOT disable, block, or work around any system gesture to accommodate layout. Pull-down-to-scroll SHALL scroll the form with any picker open or closed; swipe-down-to-dismiss SHALL dismiss the sheet/cover presentation; the edge-back gesture SHALL pop the form wherever a back stack exists; tapping outside a focused text field SHALL dismiss the keyboard. If a presentation kills a system gesture, the presentation SHALL change (navigation push or interactive dismiss) rather than patching the gesture.

#### Scenario: Scroll with picker open

- **WHEN** a date or time picker is expanded and the user drags vertically starting outside the picker wheels
- **THEN** the form scrolls; the wheel picker never traps the scroll gesture

#### Scenario: Dismiss and back gestures

- **WHEN** the form is presented and the user swipes down (sheet/cover) or swipes back from the leading edge (pushed onto a navigation stack)
- **THEN** the form dismisses/pops with the draft discarded and no entry created or changed

#### Scenario: Keyboard dismissal

- **WHEN** the name or notes field is focused and the user taps outside the field or scrolls
- **THEN** the keyboard dismisses and the draft is preserved
