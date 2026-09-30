## Purpose

A single shared page for choosing an entry name across Track and the entry form: an autofocused field pinned at the top with a scrollable suggestion list below, replacing the floating overlay and inline lists that caused issue #69.

## ADDED Requirements

### Requirement: Dedicated name-picker page layout and navigation
The app SHALL provide one shared name-picker page pushed on the caller's `NavigationStack` with the standard system back button (chevron + previous-screen title, edge-swipe gesture preserved) and no confirm button in the navigation chrome. The page SHALL show an autofocused entry field pinned at the top and a scrollable suggestion list below it. The page SHALL use `Theme` semantic colors only, with all user-facing strings localized (EN + RU), support Dynamic Type and light/dark appearance, and expose accessible identities for the field and rows.

#### Scenario: Picker opens focused
- **WHEN** the user taps the Track name row or the entry-form Name row
- **THEN** the picker pushes with the entry field focused (keyboard visible), prefilled with the caller's current draft text and cursor at the end
#### Scenario: Standard back cancels without applying
- **WHEN** the user activates the system back button or the edge-swipe gesture on the picker
- **THEN** the picker pops restoring the caller's pre-push draft (text and categories unchanged) and nothing is prepared or saved

#### Scenario: Suggestions scroll under a pinned field
- **WHEN** the suggestion list exceeds the visible space (small screen, large Dynamic Type, or many matches)
- **THEN** the list scrolls while the entry field stays pinned at the top, and no content clips at the screen edges

#### Scenario: Field stays pinned while results change
- **WHEN** the results switch between suggestion rows, the empty hint, and the no-match hint while typing
- **THEN** the entry field keeps its top position (top-aligned layout, one persistent scroll container, uniform spacing) instead of riding up and down

### Requirement: Picker suggestion source and filtering
The picker SHALL suggest from every committed exact-text name in recency order (newest first, uncapped — not the capped Recents): when the trimmed input is a non-empty prefix, the picker SHALL list the names starting with it (case-insensitive prefix), including the case-sensitive exact match. An empty trimmed input SHALL list all names newest-first. The filter SHALL be pure over the caller's already-loaded names — the picker SHALL perform no store reads. Suggestion rows SHALL show the exact text (single-line, tail-truncated) plus the first-category icon, or the `questionmark` fallback when the newest entry carries no categories (History/Insights convention; the fixed icon slot keeps every row's text aligned, unlike the space-saving chips which omit the icon), with a minimum 44×44pt tap target.

#### Scenario: Typing filters prefix matches
- **WHEN** the user types a non-empty prefix matching one or more names
- **THEN** those names are listed newest-first, including the exact text already in the field

#### Scenario: Empty field lists all names
- **WHEN** the entry field is empty
- **THEN** all committed names are listed newest-first (browsable without typing)

#### Scenario: Exact-text identity is case-sensitive
- **WHEN** committed names hold both `Gym` and `GYM` and the user types `g`
- **THEN** both are listed; typing the exact `Gym` lists `Gym` itself (plus longer prefix matches), never the new-name hint

#### Scenario: Typing a lone existing name narrows to its row
- **WHEN** the trimmed input exactly matches one committed name and no other name starts with it
- **THEN** the list shows that single row — tapping it applies the existing name, and no new-name hint appears

#### Scenario: No matches offers the typed text as new
- **WHEN** the trimmed input matches no committed name at all
- **THEN** the list shows an empty-state hint naming that Done will use the typed text as a new name with no categories

### Requirement: Picker completion semantics
Picking a suggestion SHALL fill the exact text plus that entry's full ordered categories (the Recents-tap contract) without starting timing and without creating or mutating any committed entry, then pop the picker. Activating the keyboard Done/Return with non-empty trimmed text SHALL apply that text — exact-recent match's categories where one exists, otherwise the caller's categories — then pop. Activating Done with empty/whitespace-only text SHALL be a no-op (Back remains the exit). Completion SHALL never start a timer and SHALL never mutate committed history.

#### Scenario: Picking a suggestion prepares without starting
- **WHEN** the user taps a suggestion row
- **THEN** the caller's draft fills with that exact text plus its ordered categories, the picker pops, and no timer starts and no entry is created or changed

#### Scenario: Done completes with typed text
- **WHEN** the user activates Done with a non-empty trimmed text (whether or not it matches a recent)
- **THEN** the caller's draft takes the typed text (with the exact-match recent's categories where applicable), the picker pops, and no timer starts and no entry is created or changed

#### Scenario: Done with empty text does nothing
- **WHEN** the user activates Done while the field holds only whitespace
- **THEN** nothing is applied and the picker stays open (Back remains the exit)

#### Scenario: VoiceOver completes the same ways
- **WHEN** VoiceOver focuses a suggestion row or the keyboard Done control
- **THEN** it announces the row text (and selected state where applicable) and activating it completes exactly as in the sighted paths
