## MODIFIED Requirements

### Requirement: Track name field has autocomplete suggestions over recents

(Clear-button behavior for this field — focused-AND-non-empty visibility, Apple-standard look — is owned by the baseline "Track name clear shows only when focused and non-empty" requirement.) The Track name field SHALL offer autocomplete suggestions over recent texts. Suggestions SHALL be drawn from the exact-text Recents (cap 6, newest-first, `Gym` ≠ `GYM`): when the trimmed draft is a non-empty prefix, Track SHALL suggest the recents whose text starts with it (case-insensitive prefix), excluding the case-sensitive exact match. Suggestions SHALL render without moving the main action (overlay, not layout). Picking a suggestion SHALL follow the Recents tap contract: fill the exact text plus that recent's full ordered categories without starting timing and without creating anything.

#### Scenario: Typing shows prefix suggestions without moving Start

- **WHEN** the user types a non-empty prefix matching one or more recents
- **THEN** those recents are suggested newest-first (exact match excluded) and the Start/Stop action does not move

#### Scenario: Picking a suggestion prepares without starting

- **WHEN** the user picks a suggestion
- **THEN** the field fills with that exact text plus its ordered categories, the ready timer appears, and no timer starts and no entry is created
