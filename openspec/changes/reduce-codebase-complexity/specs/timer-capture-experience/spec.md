## MODIFIED Requirements

### Requirement: Recents present a capped wrapping chip flow
Track SHALL present its most-recently-used exact entry texts as a wrapping chip flow below the name field, ordered by each text's newest committed `started_at` first, and SHALL cap the flow at six chips. Identity SHALL be trimmed exact text (case-sensitive: `Gym` and `GYM` are distinct). There is no activity entity — chips represent entry texts, never activities. Chips SHALL wrap onto additional rows as needed and SHALL NOT require horizontal scrolling. A single tap on a chip SHALL fill the name plus that recent's full ordered categories without starting timing. Recents SHALL yield the below-button slot to the running TagSelector while a timer is running (inactive branch opacity-hidden with the slot keeping the taller branch's height). Returning to Track SHALL reload recents and categories — seeding the starter set first on a fresh install — so History edits and new categories are reflected immediately.

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
