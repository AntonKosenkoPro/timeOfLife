## ADDED Requirements

### Requirement: Category editor uses toolbar X and checkmark affordances
The category editor (create and edit modes) SHALL offer cancellation as a toolbar `xmark` button and saving as a toolbar `checkmark` button, matching the Log Time sheet grammar — no text Cancel button and no bottom Save bar. The ✓ button SHALL be disabled while the draft name is invalid (empty/whitespace-only, over 60 characters) or a save is in flight; activating it with a valid draft SHALL save through the atomic `LocalStore` mutation and dismiss on success, preserving the draft and staying open on duplicate, stale, or persistence outcomes. The X button SHALL dismiss without saving (identical to the previous Cancel paths, including disabled-while-saving). Both buttons SHALL expose stable accessibility identifiers and meaningful VoiceOver labels.

#### Scenario: Checkmark saves a valid category
- **WHEN** the user activates ✓ with a unique valid name and supported icon
- **THEN** the category is created/updated, the editor dismisses, and Manage Categories shows the result

#### Scenario: Checkmark disabled for invalid drafts
- **WHEN** the draft name is empty, whitespace-only, or over the length limit, or a save is in flight
- **THEN** ✓ is disabled and no save is attempted

#### Scenario: X discards the draft
- **WHEN** the user activates X without a save in flight
- **THEN** the editor dismisses and the persisted catalog remains unchanged

#### Scenario: VoiceOver identifies the toolbar actions
- **WHEN** VoiceOver focuses the X or ✓ button in English or Russian
- **THEN** it announces the cancel/save meaning and the available action
