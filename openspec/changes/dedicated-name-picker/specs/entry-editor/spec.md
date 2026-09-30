## MODIFIED Requirements

### Requirement: Entry-form name row has autocomplete suggestions
(Clear-button behavior for this row — focused-AND-non-empty visibility, editable only — is owned by the "Entry-form name clear shows only when focused and non-empty" requirement.) The entry-form Name row SHALL open the shared dedicated name-picker page (`name-picker` capability) instead of rendering an inline suggestion list. Tapping the Name row in an editable form (CREATE or EDIT mode) SHALL push the picker prefilled with the current draft name. Picking a suggestion or completing with Done SHALL fill the field with that exact text and inherit that entry's full ordered categories (the Recents tap contract); suggestions SHALL cover every committed name (newest-first, uncapped) and SHALL never mutate committed history. LOCKED mode is unchanged: the Name row stays read-only and never opens the picker.

#### Scenario: Tapping the Name row opens the picker
- **WHEN** the user taps the entry-form Name row in CREATE or EDIT mode
- **THEN** the shared picker pushes prefilled with the current draft name

#### Scenario: Typing shows prefix suggestions
- **WHEN** the user types a non-empty prefix matching one or more committed names on the picker page
- **THEN** those names are suggested newest-first, including the exact text already in the field

#### Scenario: Picking a suggestion fills text plus categories
- **WHEN** the user picks a suggestion or completes with Done on the picker page
- **THEN** the field fills with that exact text and the ordered categories become that entry's categories; no committed entry changes

#### Scenario: Exact-text identity is case-sensitive
- **WHEN** committed names hold both `Gym` and `GYM` and the user types `g`
- **THEN** both are suggested; typing the exact `Gym` suggests `Gym` itself (plus longer prefix matches)

## REMOVED Requirements

### Requirement: Inline autocomplete list in the entry-form Name row
**Reason**: Replaced by the shared dedicated picker page for one consistent pick flow across Track and the entry form.
**Migration**: The `name-picker` capability owns suggestion rendering; `LogTimeView.nameSuggestions` inline list is deleted and the Name row becomes a push affordance.
