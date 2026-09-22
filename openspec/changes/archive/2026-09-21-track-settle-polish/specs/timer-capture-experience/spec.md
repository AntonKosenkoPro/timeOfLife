## MODIFIED Requirements

### Requirement: Starting always requires explicit confirmation
Selecting a recent or typing a name SHALL prepare it without starting a timer; the timer SHALL begin only after the user activates Start. Unconfirmed typed input SHALL NOT start a timer or create an entry. A focused Start tap SHALL resign the field immediately (selection haptic fires and `started_at` is captured at tap time) and delay the running swap until the keyboard finishes dismissing (real `didHide`, bounded fallback for hardware keyboards); the swap SHALL then render instantly with no animation of its own. Any field edit or chip tap before the swap fires SHALL cancel the deferred start.

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

#### Scenario: Focused Start waits for keyboard dismissal
- **WHEN** the user activates Start while the name field is focused
- **THEN** the field resigns at once with haptic feedback and tap-time `started_at`, and the running swap fires only after the keyboard finishes dismissing (bounded fallback when no dismissal notifies)

#### Scenario: Deferred start cancels on edit
- **WHEN** the user edits the field or taps a chip after a focused Start tap but before the swap fires
- **THEN** the deferred start is cancelled and no timer starts with the stale draft

#### Scenario: Running swap renders instantly
- **WHEN** the running swap fires
- **THEN** Stop appears in place with no fade, slide, or spring of its own; the keyboard's own slide moves the whole layout together

### Requirement: Main action holds one position across states
Track SHALL present the state-specific main action in one main-action region whose frame is identical across the idle, ready, running, saving, saved, and error states. The layout SHALL render the main action in a fixed-height slot equal to the tallest of its state titles at the active Dynamic Type size. The below-button slot SHALL keep both branches (Recents and the running TagSelector) mounted and hide the inactive branch via opacity, so the slot keeps the taller branch's height in every state and the main action never moves on state switch. When a wrapped error grows the reserved error region, the top adaptive spacing SHALL yield first, then the central separator, keeping the main action stationary; scrolling SHALL begin only when both are exhausted.

#### Scenario: Preparing an Activity preserves the main-action frame
- **WHEN** an Activity is prepared while Track is idle
- **THEN** the preparation row appears in its reserved slot and the main-action frame does not change

#### Scenario: Starting timing preserves the main-action frame
- **WHEN** the user starts timing from ready
- **THEN** Recents hides while its occupied height is preserved and the main-action frame does not change

#### Scenario: Saving preserves the main-action frame
- **WHEN** the user stops and the entry is being saved
- **THEN** Recents reappears in the preserved region and the main-action frame does not change

#### Scenario: Error within the reservation preserves the main-action frame
- **WHEN** a recoverable non-field error fits within the reserved error height
- **THEN** the main-action frame does not change

#### Scenario: Wrapped error keeps the main action stationary
- **WHEN** a recoverable non-field error wraps beyond the reserved height and the top adaptive spacing and central separator can absorb the growth
- **THEN** the main-action frame does not change; only when both are exhausted does the content scroll

### Requirement: Recents present a capped wrapping chip flow
Track SHALL present its most-recently-used exact entry texts as a wrapping chip flow below the name field, ordered by each text's newest committed `started_at` first, and SHALL cap the flow at six chips. Identity SHALL be trimmed exact text (case-sensitive: `Gym` and `GYM` are distinct). Chips SHALL wrap onto additional rows as needed and SHALL NOT require horizontal scrolling. A single tap on a chip SHALL fill the name plus that recent's full ordered categories without starting timing. Recents SHALL yield the below-button slot to the running TagSelector while a timer is running (inactive branch opacity-hidden with the slot keeping the taller branch's height). Returning to Track SHALL reload recents and categories — seeding the starter set first on a fresh install — so History edits and new categories are reflected immediately.

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

#### Scenario: Return refreshes Recents
- **WHEN** the user returns to Track from another tab or sheet
- **THEN** Recents and the category map reload (seeding first when needed), so entries edited in History are inherited and chip icons stay current
