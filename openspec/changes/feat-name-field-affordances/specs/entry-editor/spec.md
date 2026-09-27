## MODIFIED Requirements

### Requirement: Entry-form name row has clear and autocomplete affordances

The entry-form Name row SHALL offer a trailing clear (`×`) button and autocomplete suggestions. The clear button SHALL be visible only when the field holds non-empty text and the form is editable (hidden in LOCKED mode and when the field is empty); one tap SHALL clear the draft name (categories, notes, and interval untouched; the validity gate re-evaluates). Suggestions SHALL be drawn from recent committed entry texts (exact-text history, case-sensitive identity: `Gym` ≠ `GYM`): when the trimmed input is non-empty, the row SHALL list the loaded recents (cap 6, newest-first) whose text starts with the input (case-insensitive prefix), excluding the case-sensitive exact match. Picking a suggestion SHALL fill the field with that exact text and inherit that entry's full ordered categories (the Recents tap contract); suggestions SHALL never mutate committed history.

#### Scenario: Clear button clears the draft name

- **WHEN** the entry-form name field holds text and the form is editable
- **THEN** a trailing `×` button is visible, and one tap empties the field while categories, notes, and Start/End stay unchanged

#### Scenario: Clear button hidden when nothing to clear

- **WHEN** the entry-form name field is empty, or the form is LOCKED (read-only)
- **THEN** no clear button is shown

#### Scenario: Typing shows prefix suggestions

- **WHEN** the user types a non-empty prefix matching one or more recent texts
- **THEN** those recents are suggested newest-first, excluding the exact text already in the field

#### Scenario: Picking a suggestion fills text plus categories

- **WHEN** the user picks a suggestion
- **THEN** the field fills with that exact text and the ordered categories become that entry's categories; no committed entry changes

#### Scenario: Exact-text identity is case-sensitive

- **WHEN** recents hold both `Gym` and `GYM` and the user types `g`
- **THEN** both are suggested; typing the exact `Gym` excludes only `Gym`, not `GYM`
