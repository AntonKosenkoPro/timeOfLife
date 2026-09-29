## MODIFIED Requirements

### Requirement: Log Time sheet uses cross-plus-checkmark chrome

The CREATE-mode `Log Time` sheet SHALL show a cross (`X`, `xmark` symbol) dismiss action in the cancellation placement — performing the same draft-discarding dismiss as today's `Cancel` — and a checkmark (`✓`, `checkmark` symbol) confirm action in the confirmation placement performing the same save as today's `Add` under the same validity gate (enabled only when the trimmed name is non-empty AND end is strictly after start; otherwise disabled with no error text). The dismiss button SHALL carry the `LogTimeDismissButton` accessibility identifier; the confirm button SHALL keep the `LogTimeAddButton` identifier. Both icon buttons SHALL carry localized VoiceOver labels. Toolbar tint stays the system default. Title, cards, pickers, defaults, and save behavior are unchanged.

#### Scenario: Sheet contents use icon actions

- **WHEN** the Log Time sheet is open
- **THEN** it shows an `X` dismiss button and a `✓` confirm button (with the `Log time` title and the unchanged Name/Start/End/Categories/Notes cards) — and no `Cancel`/`Add` text buttons

#### Scenario: Cross discards the draft

- **WHEN** the user activates the `X` button
- **THEN** the sheet dismisses and no entry is created

#### Scenario: Checkmark gate matches Add gate

- **WHEN** the sheet holds an empty trimmed name or an end equal to or before the start
- **THEN** the `✓` button is disabled with no error text, exactly as `Add` was
