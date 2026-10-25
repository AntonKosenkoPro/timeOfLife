## ADDED Requirements

### Requirement: Running start time is editable via Started caption
While a timer is running, Track SHALL show a tappable `Started HH:MM` caption under the numeric timer (caption case, secondary color). Tapping it SHALL open the chosen start editor (one of: inline expanding hourAndMinute wheel, presets half-sheet, native compact popover — spike winner, default inline wheel). The editor SHALL offer only the start time (no End, no date UI); presets SHALL be bidirectional minute steppers (`-30/-15/+15/+30`) that move the wheel from its current position without applying (cumulative taps accumulate; forward steps clamp at now) and the wheel SHALL be minute precision (floored, LogTime precedent) with an explicit Today | Yesterday day segment (no silent day folds). Confirming a new start SHALL rewrite only the running draft's `started_at`, restart the elapsed ticker from the new anchor, and recompute derived duration at Stop as `endedAt - newStart`. The gate SHALL be `newStart <= now`: future times SHALL be rejected (confirm disabled, no error text — LogTime gate grammar). Overlap with existing entries SHALL be allowed (manual-entry precedent). The caption slot SHALL be reserved in all Track states (empty in idle/ready/saving/saved) so the Start/Stop action never moves (D10). The caption SHALL show `Started yesterday HH:MM` (localized) when the draft start falls on a prior calendar day; the picker itself stays time-only. Strings SHALL be localized in `en` + `ru` via `L10n` (U4); colors SHALL use `Theme` semantics only.

#### Scenario: Open the start editor
- **WHEN** the user taps the `Started HH:MM` caption while running
- **THEN** the chosen editor opens (wheel expands in place / half-sheet presents / system popover anchors) without moving the Stop action

#### Scenario: Backdate via preset
- **WHEN** the user picks a `-15` preset for a run started 2 minutes ago and confirms
- **THEN** the draft `started_at` moves 15 minutes earlier, elapsed jumps by 15 minutes, and Stop saves the entry with the earlier start plus a single outbox row

#### Scenario: Future start rejected
- **WHEN** the user wheels to a time later than now
- **THEN** confirm stays disabled and no draft write occurs

#### Scenario: Slot reserved across states
- **WHEN** Track is idle, ready, saving, or saved
- **THEN** the caption slot holds its height empty and the primary action keeps its exact frame

#### Scenario: Overnight run labels the day
- **WHEN** the running draft start falls on a prior calendar day
- **THEN** the caption reads the localized yesterday form and the picker still edits time-only

## MODIFIED Requirements

### Requirement: Running timer hosts the category TagSelector
While a timer is running, Track SHALL show the shared ordered `TagSelector` (zero allowed, order preserved) below the readout, ending with the inline-creation chip defined by the category-management capability. Category options remain the existing catalog (select from existing); only the trailing creation chip is new. The chip region SHALL hug content and clamp at up to 4 visible rows bounded by the finite available height, scrolling internally beyond the visible rows; the timer/name/Stop frames SHALL be preserved with no tab-bar overlap, and entire-page scroll SHALL engage only as an accessibility fallback. The name SHALL be locked after Start; tags SHALL stay live until Stop. The locked name card SHALL align its text to the leading edge, matching the idle/ready name-row grammar (icon + text pushed leading, never centered). Toggles SHALL rewrite only the running draft (persisted `timer_state` snapshot) and SHALL never touch history. Notes edits SHALL rewrite only the running draft notes snapshot the same way. Start-time edits SHALL rewrite only the running draft `started_at` field the same way (text, categories, and notes untouched). Stop SHALL save the entry with the final ordered categories, the final draft notes, the final draft start, and derived duration, plus a single outbox row. The running selector SHALL render selection ordinals exactly as defined by the category-management capability (single selection shows a checkmark, multiple selections show 1-based ordinals with fade-animated renumbering) without moving the main action above it.

#### Scenario: Toggle tags mid-run
- **WHEN** the user toggles a category while the timer runs
- **THEN** the draft selection updates, the persisted draft snapshot updates, and no entry or history row changes

#### Scenario: Selection order is visible mid-run
- **WHEN** the user selects a second category while the timer runs
- **THEN** the selected chips show their 1-based ordinals with a fade and the Start/Stop action above keeps its exact frame

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
- **THEN** the entry is created with the trimmed locked text, the final ordered categories, the final draft notes, and derived duration, plus a single outbox row

#### Scenario: Create a category mid-run
- **WHEN** the user activates the creation chip while the timer runs, saves a unique valid name with an icon
- **THEN** the editor pops back to Track and the running draft gains the new category in tap order with the draft snapshot updated

#### Scenario: Duplicate name mid-run keeps the editor open
- **WHEN** the user attempts to save a duplicate category name from the running-tag row
- **THEN** no category is created, the editor stays open with the draft intact and a localized duplicate-name error, and the running timer and its draft are unaffected

#### Scenario: Backdate rewrites only the start field
- **WHEN** the user confirms a new start time while running
- **THEN** only the draft `started_at` field updates in the same chokepoint transaction; text, categories, and notes are untouched, and the ticker restarts from the new anchor
