## ADDED Requirements

### Requirement: Plain-text name capture
Track SHALL capture the entry name as plain trimmed text with no catalog, no search sheet, and no quick-create. The idle screen SHALL show a plain-text name field plus the 6 exact-match recents chips. Start SHALL be enabled only when the trimmed text is non-empty. Typing a name that exactly matches a recent SHALL NOT start anything until Start is activated.

#### Scenario: Type a new name
- **WHEN** the user types a trimmed non-empty name with no exact recent match
- **THEN** Start becomes enabled and no catalog record is created

#### Scenario: Empty text cannot start
- **WHEN** the name field holds only whitespace
- **THEN** Start stays disabled with no error text

#### Scenario: Exact text identity
- **WHEN** the trimmed text differs from an existing recent only by letter case (e.g. `Gym` vs `GYM`)
- **THEN** the two are treated as different names with separate recents and separate inherited categories

### Requirement: Running timer hosts the category TagSelector
While a timer is running, Track SHALL show the shared ordered `TagSelector` (select-only from existing categories, zero allowed, order preserved) below the readout. The name SHALL be locked after Start; tags SHALL stay live until Stop. Toggles SHALL rewrite only the running draft (persisted `timer_state` snapshot) and SHALL never touch history. Stop SHALL save the entry with the final ordered categories.

#### Scenario: Toggle tags mid-run
- **WHEN** the user toggles a category while the timer runs
- **THEN** the draft selection updates, the persisted draft snapshot updates, and no entry or history row changes

#### Scenario: Name locked while running
- **WHEN** the timer is running
- **THEN** the name field is non-editable until Stop

#### Scenario: Category-less run allowed
- **WHEN** the user deselects every category mid-run
- **THEN** the run stays valid and Stop saves a category-less entry

#### Scenario: Stop saves final tags
- **WHEN** the user activates Stop
- **THEN** the entry is created with the trimmed locked text, the final ordered categories, empty notes, and derived duration, plus a single outbox row

## MODIFIED Requirements

### Requirement: Numeric timer is an instrumental readout
The Track numeric timer SHALL represent only timer readiness and exact elapsed timing; it SHALL NOT display fabricated progress, daily totals, goals, rings, sweeps, or history while idle.

#### Scenario: Nothing selected
- **WHEN** no name is entered and no timer is running
- **THEN** the numeric timer presents `00:00` and a clear action to enter a name

#### Scenario: Activity prepared
- **WHEN** the user enters a trimmed non-empty name or taps a recent
- **THEN** the numeric timer presents that name in a ready state with an explicit Start action and zero elapsed duration

#### Scenario: Timer running
- **WHEN** the user starts the prepared name
- **THEN** the numeric timer displays the exact live elapsed duration, including completed hours, without a secondary progress visualization

### Requirement: Starting always requires explicit confirmation
Selecting a recent or typing a name SHALL prepare it without starting a timer; the timer SHALL begin only after the user activates Start. Unconfirmed typed input SHALL NOT start a timer or create an entry.

#### Scenario: Select recent activity
- **WHEN** the user taps a recent chip
- **THEN** the app fills the exact text plus that recent's full ordered categories and shows the ready numeric timer without creating an entry

#### Scenario: Select or create through search
- **WHEN** the user types a trimmed non-empty name, whether or not it exactly matches a recent (no search sheet exists; typing is the only input)
- **THEN** the app shows the ready numeric timer without starting timing; an exact-recent match prefills that recent's categories, otherwise categories start empty

#### Scenario: Search input remains unresolved
- **WHEN** the user has typed text but has not activated Start
- **THEN** nothing starts, no entry is created, and the typed text stays editable in the name field

#### Scenario: Start selected activity
- **WHEN** a name is prepared and the user activates Start
- **THEN** the app persists the running draft immediately, begins elapsed-time presentation, and emits a subtle selection haptic

### Requirement: Recents present a capped wrapping chip flow
Track SHALL present its most-recently-used exact entry texts as a wrapping chip flow below the name field, ordered by each text's newest committed `started_at` first, and SHALL cap the flow at six chips. Identity SHALL be trimmed exact text (case-sensitive: `Gym` and `GYM` are distinct). Chips SHALL wrap onto additional rows as needed and SHALL NOT require horizontal scrolling. A single tap on a chip SHALL fill the name plus that recent's full ordered categories without starting timing. Recents SHALL NOT be presented while a timer is running (the running TagSelector occupies that region).

#### Scenario: More Activities than the cap
- **WHEN** the user has more than six distinct exact texts
- **THEN** Recents presents the six with the newest committed entries and omits the rest

#### Scenario: Six or fewer Activities
- **WHEN** the user has between one and six distinct exact texts
- **THEN** Recents presents all of them newest-first

#### Scenario: Chips wrap
- **WHEN** the Recents chips cannot fit on one row
- **THEN** the chips flow onto additional rows and every chip remains visible and reachable without horizontal scrolling

#### Scenario: Tap a Recents chip
- **WHEN** the user taps a Recents chip
- **THEN** the name field fills with that exact text plus its newest entry's ordered categories, the ready numeric timer appears, and no timer starts and no entry is created

#### Scenario: Timing hides Recents
- **WHEN** a timer is running
- **THEN** Recents is not presented and its occupied height is preserved so the main action does not move

### Requirement: Recents chips show the first inherited Category icon
A Recents chip SHALL display the icon of the first category of that exact text's newest committed entry (first by stored position). A text whose newest entry has no categories SHALL render its chip without an icon. Recents chips SHALL NOT display category names.

#### Scenario: Recent with one Category
- **WHEN** a Recents chip's newest entry has exactly one category
- **THEN** the chip displays that category's icon

#### Scenario: Recent with multiple Categories
- **WHEN** a Recents chip's newest entry has two or more categories
- **THEN** the chip displays only the icon of the category that is first by stored position

#### Scenario: Recent without Categories
- **WHEN** a Recents chip's newest entry has no categories
- **THEN** the chip renders with the exact text and no icon, keeping the full tap target

#### Scenario: Icon cannot render on this OS
- **WHEN** the first category's icon is unavailable on the running iOS version
- **THEN** the chip falls back to the tag glyph used elsewhere for unavailable category icons

### Requirement: Recents explain their empty state
When no committed entries exist, Recents SHALL present dedicated localized copy explaining that names the user tracks will appear there.

#### Scenario: Empty catalog
- **WHEN** Track is idle and no committed entries exist
- **THEN** Recents shows the dedicated localized hint that tracked names will appear there

#### Scenario: First Activity created
- **WHEN** the user saves the first entry and returns to Track
- **THEN** the empty hint is replaced by Recents chips containing that exact text

### Requirement: Categories are per-entry and never retroactive
The app SHALL treat categories as optional, zero-or-more metadata owned by each entry at creation. Editing categories on one entry (or on the running draft) SHALL NOT change any other entry. There SHALL be no query-time category resolution through any other record.

#### Scenario: Create without categories
- **WHEN** the user starts a timer for a name with no inherited categories
- **THEN** the run is valid with no categories assigned

#### Scenario: Retag affects one entry only
- **WHEN** the user changes an entry's categories
- **THEN** no other entry with the same text changes

### Requirement: Stop saves with stable feedback
Stopping a running timer SHALL save the completed entry locally, communicate success without a blocking loader, and retain the entered text in the ready state for an optional later restart. When the persisted running draft is gone but Track still holds a `.running` state (the timer was stopped from the compact timer on another destination), Track SHALL reconcile on next load: stop the elapsed ticker, re-enable the idle timer, reset elapsed to zero, and return to `.ready` for the same text — or `.idle` when nothing was entered — instead of counting elapsed time forever.

#### Scenario: Successful stop
- **WHEN** the user activates Stop on a running timer
- **THEN** the app persists the completed entry, clears running state, emits a success haptic, briefly confirms the saved duration, and returns to the ready numeric timer for the same text

#### Scenario: Save failure
- **WHEN** the local store cannot save the completed entry
- **THEN** the app preserves recoverable running state and presents a localized non-field error without silently losing elapsed time

#### Scenario: External stop reconciles Track
- **WHEN** Track holds a running state whose persisted draft no longer exists (stopped from the compact timer elsewhere)
- **THEN** Track leaves the running state on next load: the ticker stops, elapsed resets to zero, and the screen shows the ready timer for the same text (or idle when empty)

#### Scenario: Stop after the activity was deleted elsewhere
- **WHEN** the user stops a timer (no deletable parent exists; entries and drafts cannot be deleted out from under a run)
- **THEN** the entry always saves normally; this scenario is retained as a no-op for archive continuity

## REMOVED Requirements

### Requirement: Activity chooser supports selection and creation
**Reason**: No activity catalog exists; capture is plain text plus recents chips.
**Migration**: Use the plain-text name field and recents chips; deletion removes `ActivitySearchResults`, the search sheet, and quick-create.

### Requirement: Search drafts do not mutate committed preparation
**Reason**: No search presentation exists to hold a draft.
**Migration**: Typing edits the name field directly; no separate committed preparation exists.

### Requirement: Activity name collisions preserve one identity
**Reason**: Normalized case-insensitive identity is replaced by trimmed exact identity (`Gym` ≠ `GYM`); there is no catalog identity to preserve.
**Migration**: Exact text match inherits categories; nothing merges or remaps.

### Requirement: First use is contextual
**Reason**: The search-and-quick-create first-run path no longer exists.
**Migration**: First launch directs the user to type a name and press Start; no catalog copy remains.

### Requirement: Preparation failures preserve user intent
**Reason**: Creation/refinement failure modes belonged to the catalog editor flow.
**Migration**: Name-field validation (non-empty trim, 60 chars) stays inline; store save failures keep the existing non-field error path.
