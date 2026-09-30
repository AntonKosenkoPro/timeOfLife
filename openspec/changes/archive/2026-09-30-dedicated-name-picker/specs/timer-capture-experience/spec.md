## MODIFIED Requirements

### Requirement: Track name field has autocomplete suggestions over recents
(Clear-button behavior for this field — focused-AND-non-empty visibility, Apple-standard look — is owned by the "Track name clear shows only when focused and non-empty" requirement.) The Track name field SHALL open the shared dedicated name-picker page (`name-picker` capability) instead of rendering a floating overlay. Tapping the idle/ready/saved name row SHALL push the picker prefilled with the current draft. Picking a suggestion or completing with Done SHALL follow the picker completion contract: fill the exact text plus that recent's full ordered categories without starting timing and without creating anything. The Start/Stop action SHALL never be covered by suggestions by construction (typing and starting live on different screens), and the main-action frame requirements are unchanged.

#### Scenario: Tapping the name row opens the picker
- **WHEN** the user taps the Track name row while idle, ready, or saved
- **THEN** the shared picker pushes prefilled with the current draft text and the Start/Stop action stays uncovered behind it

#### Scenario: Typing shows prefix suggestions without moving Start
- **WHEN** the user types a non-empty prefix matching one or more committed names on the picker page
- **THEN** those names are suggested newest-first (exact match included) and the Track Start/Stop action does not move and is never covered

#### Scenario: Picking a suggestion prepares without starting
- **WHEN** the user picks a suggestion or completes with Done on the picker page
- **THEN** the field fills with that exact text plus its ordered categories, the picker pops back to Track showing the ready timer, and no timer starts and no entry is created

## REMOVED Requirements

### Requirement: Floating autocomplete overlay on Track
**Reason**: Replaced by the dedicated picker page — the overlay covered the Start button (issue #69: even one 44pt row overlaps the 24pt field-to-button gap).
**Migration**: The `name-picker` capability owns suggestion rendering; `TrackContent.nameSuggestionsCard` overlay is deleted and the idle/ready/saved name control becomes a push row.
