## MODIFIED Requirements

### Requirement: Stop and return actions
Tapping any face outside Stop SHALL deep-link to Track (`lifio://track`). The expanded Island and banner SHALL each offer Stop as a link to `lifio://track?stop=1`: tapping opens the app, which reloads its bound account's draft, stops and saves through the ordinary in-app path, and ends the activity with the Saved card. The app SHALL preserve existing Stop timing and SHALL NOT defer stopping or change the completed entry's end time while awaiting notes review or resolution. This SHALL work on the first tap after a terminated-app cold open; no draft means a graceful no-op. The normal Stop URL SHALL be available for shipped controls; there SHALL be no nil-URL intent fallback, independent extension entry writer, or external-stop signal needed to complete Stop. Compact and minimal faces SHALL offer no buttons (tap navigates only). Existing dimmed/inert rendering is unchanged.

When Track's running-notes editor holds unconfirmed changes, Stop SHALL first complete with the confirmed notes, clear the running draft, and show the ordinary Saved result. Only after successful completion SHALL the main app offer Review Notes or Discard Changes for the retained text, as defined by `timer-capture-experience`. Review SHALL open the text without writing; only the review editor's ✓ SHALL validate and save notes to that exact completed entry. This flow SHALL NOT block the Live Activity's normal ending/dismissal, create a second entry, restart the activity, or change the recorded duration. Clean/already-confirmed notes, terminated-app Stop without an in-memory editor, no-run no-ops, and failed/gated stops SHALL NOT produce this decision. Repeated delivery during one Stop/resolution operation SHALL NOT duplicate the entry or decision.

#### Scenario: Tap returns to Track
- **WHEN** the user taps the compact, minimal, expanded, or banner surface (outside Stop)
- **THEN** the app opens to Track for the running timer

#### Scenario: Stop from the Island saves
- **WHEN** the user activates Stop in the expanded Island while running
- **THEN** the app opens to Track and the entry is saved with the draft's final categories and confirmed notes through the in-app Stop path, the running draft is cleared, and the activity ends with the Saved card

#### Scenario: Stop from the expanded Island with a terminated app opens and stops
- **WHEN** the user activates Stop in the expanded Island while the app process is dead (swiped away or jetsammed) and a run is active
- **THEN** the app opens and reloads before stopping, saves one entry through the normal path, and shows `✓ Saved <duration>` with the tuned dismissal — no ticking orphan survives first contact and no second tap is needed
- **AND** no unsaved-notes prompt is invented without an in-memory running-notes editing session

#### Scenario: Island Stop with nothing running is a no-op
- **WHEN** the stop link opens the app with no active run (double tap, stale face)
- **THEN** the app opens to Track, nothing is written, and no error surfaces

#### Scenario: Banner Stop with a terminated app opens and stops
- **WHEN** the user activates Stop in the banner while the app process is dead and a run is active
- **THEN** the app opens, reloads, and saves through the same in-app path — no ticking orphan survives first contact and no second tap is needed
- **AND** the lack of an in-memory notes editor does not introduce a notes decision

#### Scenario: Stop fails gracefully
- **WHEN** Stop is activated with no active account file or an inaccessible database (e.g. cold boot before first unlock)
- **THEN** nothing is written, no anonymous file is created, and the failed stop does not fabricate a Saved card or post-stop notes decision; the ordinary auth/account lifecycle remains authoritative

#### Scenario: Dimmed rendering hides the Stop control
- **WHEN** the activity renders outside full color (Always-on dim, StandBy accent modes)
- **THEN** faces show the same layout with the Stop control dimmed and inert instead of hidden (it is not interactive there and its saturated red is quieted); the control returns to full opacity in full color

#### Scenario: Dimmed banner masks the seconds
- **WHEN** the banner renders outside full color
- **THEN** the elapsed readout keeps ticking via the system timer view, which the dimmed renderer sustains itself (no coarse static masking)

#### Scenario: Stop is link-only
- **WHEN** either shipped Stop control is activated
- **THEN** it follows the valid stop deep link; no fallback intent executes or writes an entry outside the app

#### Scenario: Dirty notes never defer Stop or the Saved card
- **WHEN** an expanded-Island or banner Stop is handled with unconfirmed running-note changes and the user waits before reviewing or resolving those changes
- **THEN** the initial entry is already saved using the existing Stop timing, its end time does not change with the review/decision delay, and the activity shows its normal Saved card and timed dismissal without waiting for resolution

#### Scenario: Notes resolution does not end the activity again
- **WHEN** the user later reviews notes, saves via ✓, discards via the prompt or X/back, or retries a failed notes update
- **THEN** no timer restarts, no second activity-ending event or Saved card is emitted, and the completed entry's end time and duration stay unchanged

#### Scenario: Repeated Stop preserves one pending decision
- **WHEN** the same Stop flow receives another stop link while completion or its notes decision is pending
- **THEN** there is at most one completed entry and one pending notes decision, and repeated delivery neither overwrites the retained text nor creates another completion
