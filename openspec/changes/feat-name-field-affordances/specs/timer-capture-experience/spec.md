## MODIFIED Requirements

### Requirement: Track name field has clear and autocomplete affordances

The Track name field SHALL offer a trailing clear (`×`) button and autocomplete suggestions over recent texts. The clear button SHALL be visible only when the field holds non-empty text while idle/ready/saved (never while running — the name is locked then); one tap SHALL clear the draft and return Track to idle. Suggestions SHALL be drawn from the exact-text Recents (cap 6, newest-first, `Gym` ≠ `GYM`): when the trimmed draft is a non-empty prefix, Track SHALL suggest the recents whose text starts with it (case-insensitive prefix), excluding the case-sensitive exact match. Suggestions SHALL render without moving the main action (overlay, not layout). Picking a suggestion SHALL follow the Recents tap contract: fill the exact text plus that recent's full ordered categories without starting timing and without creating anything.

#### Scenario: Clear button clears the Track draft

- **WHEN** the Track name field holds text while idle, ready, or saved
- **THEN** a trailing `×` button is visible, and one tap empties the field and returns Track to idle

#### Scenario: No clear button while running

- **WHEN** a timer is running
- **THEN** the name is locked and no clear button is shown

#### Scenario: Typing shows prefix suggestions without moving Start

- **WHEN** the user types a non-empty prefix matching one or more recents
- **THEN** those recents are suggested newest-first (exact match excluded) and the Start/Stop action does not move

#### Scenario: Picking a suggestion prepares without starting

- **WHEN** the user picks a suggestion
- **THEN** the field fills with that exact text plus its ordered categories, the ready timer appears, and no timer starts and no entry is created
