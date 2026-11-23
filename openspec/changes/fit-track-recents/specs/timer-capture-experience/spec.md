## MODIFIED Requirements

### Requirement: Recents present a capped wrapping chip flow
Track SHALL present its most-recently-used exact entry texts as a wrapping chip flow below the name field and main action, ordered by each text's newest committed `started_at` first, and SHALL consider at most the ten newest distinct texts as Recents candidates. Identity SHALL be trimmed exact text (case-sensitive: `Gym` and `GYM` are distinct). There is no activity entity — chips represent entry texts, never activities.

The available Recents chip area SHALL be the finite remaining space above the tab bar after accounting for the main action, section caption, required spacing, border clearance, safe areas, and the active text size. A fitting count SHALL mean the largest newest-first candidate prefix whose wrapping layout fits completely inside that area, with full chip tap targets; it SHALL count chips, not rows, and SHALL NOT skip a newer chip to fit an older one.

If all candidates fit, Recents SHALL show all of them without scrolling, even when fewer than five candidates exist. Otherwise, if five or more candidates fit, Recents SHALL render only that fitting prefix, capped at ten, without internal scrolling. If fewer than five candidates fit, Recents SHALL offer only the newest five candidates, or all available candidates when fewer than five exist, and SHALL enable internal vertical scrolling only when that offered set actually overflows. Names omitted from Recents SHALL remain available through the unchanged, uncapped name picker. Omitted chips SHALL NOT remain invisible interactive or accessibility elements.

The chip area SHALL hug its offered content when it fits and SHALL NOT reserve empty chip rows. It SHALL NOT require horizontal scrolling, and the Track page itself SHALL NOT grow or scroll for Recents overflow except as an accessibility fallback when the core controls plus one usable chip row cannot fit after adaptive spacing yields. When Recents is nonempty, that minimum row SHALL retain its full tap-target height at the active text size plus border clearance; Recents SHALL NOT disappear to avoid this fallback. Additional Recents rows SHALL NOT cause page growth. Changing which Recents chips fit SHALL NOT move the main action merely because timing starts or stops. Running categories SHALL retain their existing viewport and scrolling behavior; this policy SHALL NOT replace the running-category row clamp.

Both chip groups SHALL carry the same border clearance: 1 pt top/bottom content padding and 2 pt included in the matching viewport height budget. The viewport SHALL carry edge-aware hairline dividers shared with the tag selector: a divider fades in above the viewport once chips scroll under it and below it while content remains, the bottom divider fades out at the content end, and both stay hidden when everything fits. A single tap on a chip SHALL fill the name plus that recent's full ordered categories without starting timing. Recents SHALL yield the below-button slot to the running TagSelector while a timer is running (inactive branch opacity-hidden with the slot keeping the taller branch's height). Returning to Track SHALL reload recents and categories — seeding the starter set first on a fresh install — so History edits and new categories are reflected immediately. Track SHALL also reload recents, the full name list, and the category map when a sync cycle exits (idle or error), so relay-pulled entries and categories converge without requiring a tab switch; a failed cycle MAY have applied partial merges before throwing and still triggers the reload.

#### Scenario: More Activities than the cap
- **WHEN** the user has more than ten distinct exact texts
- **THEN** only the ten with the newest committed entries are eligible for Recents, the fit policy determines which eligible chips are offered, and all other names remain available in the name picker

#### Scenario: Six or fewer Activities
- **WHEN** the user has between one and six distinct exact texts
- **THEN** all are candidates, all appear when they fit, and otherwise the chip-fit policy offers either the fitting prefix of at least five or the newest five (all available when fewer exist), scrolling only an overflowing fallback set

#### Scenario: Seven to twelve Activities
- **WHEN** the user has between seven and twelve distinct exact texts
- **THEN** at most the newest ten become candidates and the chip-fit policy determines the offered prefix and whether the newest-five fallback actually needs internal scrolling

#### Scenario: Five to nine chips fit
- **WHEN** ten candidates exist and the newest seven form the largest prefix fitting completely in the available area
- **THEN** Recents shows exactly those seven without scrolling, omits the remaining three, and does not grow or scroll the Track page

#### Scenario: At least ten chips fit
- **WHEN** the available area could fit more than ten recent chips
- **THEN** Recents shows only the ten newest candidates without scrolling

#### Scenario: Fewer than five chips fit
- **WHEN** ten candidates exist but only the newest four fit completely in the available area
- **THEN** Recents offers only the newest five through an internally scrolling viewport, the sixth through tenth are omitted, and scrolling Recents leaves the page, main action, and below-button slot frames unchanged

#### Scenario: Fewer available candidates still overflow
- **WHEN** only three candidates exist and their wrapping layout overflows the available area
- **THEN** Recents offers all three through internal scrolling without inventing additional items

#### Scenario: A small available set fits completely
- **WHEN** one through four candidates exist and all fit completely in the available area
- **THEN** Recents shows all of them newest-first without scrolling or reserved empty chip rows

#### Scenario: Chips wrap
- **WHEN** chip widths require multiple rows and a newer long chip prevents the next prefix from fitting
- **THEN** fitting uses the actual wrapped chip sizes at the current width and text size, preserves newest-first order, and does not substitute an older shorter chip or use horizontal scrolling

#### Scenario: Overflow scrolls inside the chip area
- **WHEN** fewer than five candidates fit and the offered newest-five set (or all available candidates when fewer exist) overflows its viewport
- **THEN** only that offered set scrolls internally while the page, main-action, and below-button slot frames stay unchanged, except for the explicit one-row accessibility fallback when required content cannot fit

#### Scenario: Geometry or text size changes the fit
- **WHEN** the viewport width, available height, or Dynamic Type size changes
- **THEN** Recents recalculates its fitting prefix and scrolling mode using the new geometry, keeps tap targets at least 44 by 44 points, and does not expose partially clipped chips in the non-scrolling mode

#### Scenario: Core controls require the accessibility fallback
- **WHEN** required core controls plus one usable chip row cannot fit after adaptive spacing yields in a constrained accessibility layout
- **THEN** the existing page-scroll fallback keeps them reachable instead of shrinking tap targets or clipping essential controls; ordinary Recents overflow alone does not activate this fallback

#### Scenario: Less than one usable chip row remains
- **WHEN** required timer and primary controls fit but leave less than one full chip row at the active text size, including border clearance, after adaptive spacing yields
- **THEN** Recents keeps one usable row, offers the newest five candidates or all available candidates when fewer exist, internally scrolls that set only when it overflows, and permits the accessibility page-scroll fallback rather than hiding Recents or shrinking chip tap targets

#### Scenario: Dividers follow the scroll edges
- **WHEN** the Recents chip area is scrolled down from the top
- **THEN** a hairline divider fades in above the viewport, marking content hidden above

#### Scenario: Bottom divider hides at the content end
- **WHEN** the Recents chip area is scrolled to its end
- **THEN** the bottom divider fades out

#### Scenario: No dividers when everything fits
- **WHEN** the recents fit in the viewport without scrolling
- **THEN** neither divider appears

#### Scenario: Tap a Recents chip
- **WHEN** the user taps a Recents chip
- **THEN** the name field fills with that exact text plus its newest entry's ordered categories, the ready numeric timer appears, and no timer starts and no entry is created

#### Scenario: Typed exact match beyond the cap inherits
- **WHEN** the user types a name that exactly matches a committed entry ranked beyond the ten Recents candidates (suggested by the uncapped name picker, confirmed via the keyboard)
- **THEN** the ready draft inherits that entry's ordered categories, exactly as a chip tap would — the candidate cap limits only chip display, never category inheritance

#### Scenario: Timing hides Recents
- **WHEN** a timer is running
- **THEN** Recents is not presented and its occupied height is preserved so the main action does not move

#### Scenario: Return refreshes Recents
- **WHEN** the user returns to Track from another tab or sheet
- **THEN** Recents and the category map reload (seeding first when needed), so entries edited in History are inherited and chip icons stay current

#### Scenario: Sync exit refreshes Track
- **WHEN** a background sync cycle finishes (idle) or fails after partial merges (error) while Track is mounted
- **THEN** Track reloads recents, the full name list, and the category map once, so first-sync data appears without leaving the tab and a transient failure never blanks the last good snapshot

#### Scenario: Fresh reinstall shows categories on first paint
- **WHEN** the user signs in on a reinstall with an empty account file and the shell mounts after seeding
- **THEN** the first Track paint already carries the starter categories and the name picker suggests seeded names, with recents filling in as the first sync lands

### Requirement: Plain-text name capture
Track SHALL capture the entry name as plain trimmed text with no catalog, no search sheet, and no quick-create. The idle screen SHALL show a plain-text name field plus the exact-match recents chips (the candidate cap is governed by the capped wrapping chip flow requirement above, not restated here). Start SHALL be enabled only when the trimmed text is non-empty. Typing a name that exactly matches a recent SHALL NOT start anything until Start is activated.

#### Scenario: Type a new name
- **WHEN** the user types a trimmed non-empty name with no exact recent match
- **THEN** Start becomes enabled and no catalog record is created

#### Scenario: Empty text cannot start
- **WHEN** the name field holds only whitespace
- **THEN** Start stays disabled with no error text

#### Scenario: Exact text identity
- **WHEN** the trimmed text differs from an existing recent only by letter case (e.g. `Gym` vs `GYM`)
- **THEN** the two are treated as different names with separate recents and separate inherited categories
