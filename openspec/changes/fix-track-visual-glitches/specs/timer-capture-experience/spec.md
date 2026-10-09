## ADDED Requirements

### Requirement: Section headers carry a separator above their chips
The Categories header (running `TagSelector` branch) and the Recents header (idle branch) SHALL each render a `Divider` separator between the caption text and its chips, so the header and the chip flow read as separate visual groups.

#### Scenario: Recents header separator visible
- **WHEN** Track is idle and the Recents section shows its header plus chips (or the empty hint)
- **THEN** a separator renders between the `Recents` caption and the chips below it

#### Scenario: Running categories header separator visible
- **WHEN** a timer is running and the tag-selector section shows its `Categories` caption plus tags
- **THEN** a separator renders between the caption and the tag chips below it

#### Scenario: Separator uses theme tokens only
- **WHEN** either separator renders in light or dark appearance
- **THEN** it uses only existing `Theme` hairline/background tokens with no raw `Color` literals and no new strings

## MODIFIED Requirements

### Requirement: Recents present a capped wrapping chip flow
Track SHALL present its most-recently-used exact entry texts as a wrapping chip flow below the name field, ordered by each text's newest committed `started_at` first, and SHALL cap the flow at twelve chips. Identity SHALL be trimmed exact text (case-sensitive: `Gym` and `GYM` are distinct). There is no activity entity — chips represent entry texts, never activities. The chip area SHALL keep a fixed on-screen footprint equal to the current 6-chip layout budget: chips SHALL wrap onto additional rows inside that area as needed and SHALL NOT require horizontal scrolling; when twelve chips overflow the footprint the chip area SHALL scroll internally on its own axis and the Track page itself SHALL NOT grow or scroll for Recents overflow. A single tap on a chip SHALL fill the name plus that recent's full ordered categories without starting timing. Recents SHALL yield the below-button slot to the running TagSelector while a timer is running (inactive branch opacity-hidden with the slot keeping the taller branch's height). Returning to Track SHALL reload recents and categories — seeding the starter set first on a fresh install — so History edits and new categories are reflected immediately.

#### Scenario: More Activities than the cap
- **WHEN** the user has more than twelve distinct exact texts
- **THEN** Recents presents the twelve with the newest committed entries and omits the rest

#### Scenario: Six or fewer Activities
- **WHEN** the user has between one and six distinct exact texts
- **THEN** Recents presents all of them newest-first within the fixed chip-area footprint

#### Scenario: Seven to twelve Activities
- **WHEN** the user has between seven and twelve distinct exact texts
- **THEN** Recents presents all of them newest-first

#### Scenario: Chips wrap
- **WHEN** the Recents chips cannot fit on one row but fit within the fixed chip-area footprint
- **THEN** the chips flow onto additional rows inside the same footprint and every chip remains visible and reachable without horizontal scrolling and without growing the Track page

#### Scenario: Overflow scrolls inside the chip area
- **WHEN** twelve chips overflow the fixed chip-area footprint
- **THEN** the chip area scrolls internally on its own axis while the Track page frame, the main-action frame, and the below-button slot frame do not move or grow

#### Scenario: Tap a Recents chip
- **WHEN** the user taps a Recents chip
- **THEN** the name field fills with that exact text plus its newest entry's ordered categories, the ready numeric timer appears, and no timer starts and no entry is created

#### Scenario: Timing hides Recents
- **WHEN** a timer is running
- **THEN** Recents is not presented and its occupied height is preserved so the main action does not move

#### Scenario: Return refreshes Recents
- **WHEN** the user returns to Track from another tab or sheet
- **THEN** Recents and the category map reload (seeding first when needed), so entries edited in History are inherited and chip icons stay current

### Requirement: Plain-text name capture
Track SHALL capture the entry name as plain trimmed text with no catalog, no search sheet, and no quick-create. The idle screen SHALL show a plain-text name field plus the 12 exact-match recents chips. Start SHALL be enabled only when the trimmed text is non-empty. Typing a name that exactly matches a recent SHALL NOT start anything until Start is activated.

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
While a timer is running, Track SHALL show the shared ordered `TagSelector` (select-only from existing categories, zero allowed, order preserved) below the readout. The name SHALL be locked after Start; tags SHALL stay live until Stop. The locked name card SHALL align its text to the leading edge, matching the idle/ready name-row grammar (icon + text pushed leading, never centered). Toggles SHALL rewrite only the running draft (persisted `timer_state` snapshot) and SHALL never touch history. Stop SHALL save the entry with the final ordered categories.

#### Scenario: Toggle tags mid-run
- **WHEN** the user toggles a category while the timer runs
- **THEN** the draft selection updates, the persisted draft snapshot updates, and no entry or history row changes

#### Scenario: Name locked while running
- **WHEN** the timer is running
- **THEN** the name field is non-editable until Stop

#### Scenario: Locked name aligns leading
- **WHEN** the timer is running and the locked name card shows the draft text
- **THEN** the text renders leading-aligned inside the card, matching the idle/ready name row, regardless of live elapsed-time ticks

#### Scenario: Category-less run allowed
- **WHEN** the user deselects every category mid-run
- **THEN** the run stays valid and Stop saves a category-less entry

#### Scenario: Stop saves final tags
- **WHEN** the user activates Stop
- **THEN** the entry is created with the trimmed locked text, the final ordered categories, empty notes, and derived duration, plus a single outbox row
