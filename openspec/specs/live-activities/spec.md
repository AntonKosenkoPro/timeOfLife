# Live Activities Specification

## Purpose

A Live Activity mirrors the running timer outside the app — in the Dynamic Island, on the Lock Screen, and (via the system) on the user's Mac — with Stop and return-to-Track actions, so a run stays glanceable and stoppable without opening the app.
## Requirements
### Requirement: Live Activity follows the running timer
The system SHALL start a Live Activity when a timer starts and end it when the timer stops. The activity SHALL be requested only while the app is in the foreground and only when Live Activities are enabled; at most one activity SHALL exist at a time (the `timer_state` singleton). Starting SHALL NOT create an entry and stopping via the activity SHALL open the app and save through the same in-app Stop path (entry state and outbox row in the same transaction), without producer provenance or an independent extension writer. The activity content SHALL refresh the visible category chips when the running draft is retagged mid-run (same text keeps the singleton; chips update in place); the live icon SHALL follow the draft's first ordered category (timer fallback when the draft has no categories) without restart or time reset. The activity content SHALL re-anchor the system timer when the running draft's start time is edited mid-run (same singleton; the content's start anchor updates to the draft's new start, chips and icon unchanged); the elapsed readout SHALL tick from the new anchor on all faces with no restart and no Saved card.

#### Scenario: Start shows the activity
- **WHEN** the user starts a timer in the app while Live Activities are enabled
- **THEN** a Live Activity appears showing the exact entry text, the first-category icon (or timer fallback), and the live elapsed time

#### Scenario: Stop from the app ends the activity
- **WHEN** the user stops the timer in the app
- **THEN** the entry is saved and the Live Activity ends with the Saved card (see dismissal requirement)

#### Scenario: Second start replaces, never duplicates
- **WHEN** a timer starts while a Live Activity is already active
- **THEN** no second activity is created (the singleton is reused or the stale one is ended first)

#### Scenario: Activities disabled
- **WHEN** Live Activities are disabled for the app or device
- **THEN** starting a timer succeeds with no activity and no error shown

#### Scenario: Restore re-mirrors the run
- **WHEN** the app launches or Track loads with a persisted running draft and no fresh Start (cold start, upgrade install, relaunch)
- **THEN** the activity is requested for the draft; an already-live activity for the same text is reused untouched

#### Scenario: Mid-run retag refreshes category chips
- **WHEN** the user changes the running draft's categories while the timer runs
- **THEN** the Live Activity keeps its singleton identity (same text) and its visible category chips update to the draft's current ordered set; the live icon on all running faces (banner, compact, minimal) reflects the draft's first ordered category (timer fallback when empty); identical chips skip the update

#### Scenario: Mid-run reorder moves the live icon without restart
- **WHEN** the user reorders the running draft's categories while the timer runs
- **THEN** the live icon follows the new first ordered category with `startedAt` unchanged (no restart, no elapsed reset)

#### Scenario: Mid-run removal falls back to the timer icon
- **WHEN** the user removes all categories from the running draft while the timer runs
- **THEN** the live icon falls back to `timer` with `startedAt` unchanged (no restart, no elapsed reset)

#### Scenario: Mid-run start change re-anchors elapsed without restart
- **WHEN** the user confirms a new start time while the timer runs
- **THEN** the Live Activity keeps its singleton identity and its system timer re-anchors to the new start (elapsed jumps on all faces, chips and icon unchanged, no Saved card, no duplicate activity)

### Requirement: Island and banner presentations
The activity SHALL provide compact (icon + elapsed), minimal (icon only), expanded (big borderless elapsed top-left + Stop top-right + full-width name with category chips along the bottom), and Lock Screen banner (icon + exact name + elapsed + Stop as transparent content over the system card) presentations. Elapsed time SHALL tick via the system timer view (no per-second updates). The expanded face SHALL show the exact entry text verbatim (`Gym` ≠ `GYM`, one line) and the draft's ordered categories as icon chips (validated SF Symbol + name, cap 2 chips + `+n` overflow, never a half-clipped third chip); the expanded timer readout SHALL NOT truncate at width phase crossings (`9:59`→`10:00`, `59:59`→`1:00:00`). The Lock Screen banner SHALL render no custom container — on iOS 26+ the system Liquid Glass card (via a clear background tint), on older systems the default solid card. The Lock Screen banner content row SHALL be inset 12pt from the leading system-card edge (icon side) and 8pt from the trailing edge and vertically. Faces SHALL show only the exact entry text, the first-position category icon, chips, and the elapsed readout — never notes or started-at lines. All faces SHALL expose localized accessibility labels naming the text and running state.

#### Scenario: Single activity owns the pill
- **WHEN** this is the only active activity
- **THEN** the Island shows the compact face (icon + ticking elapsed)

#### Scenario: Competing activity squeezes to minimal
- **WHEN** another app's activity is also active
- **THEN** this activity renders its minimal face (icon only) without layout breakage

#### Scenario: Long-press expands
- **WHEN** the user long-presses the compact or minimal face
- **THEN** the expanded card shows the big ticking elapsed top-left, Stop top-right, and the exact name plus category chips full-width along the bottom

#### Scenario: Lock Screen banner
- **WHEN** the device is locked with the timer running
- **THEN** the banner shows the icon, exact name, and ticking elapsed plus Stop as transparent content over the system card (glass on iOS 26+, solid card below)

#### Scenario: Lock Screen banner leading inset
- **WHEN** the device is locked with the timer running
- **THEN** the icon sits 12pt inside the leading system-card edge while the trailing content edge and vertical insets stay 8pt, and the Dynamic Island faces are unchanged

#### Scenario: Long timer never truncates
- **WHEN** the run crosses an elapsed-width boundary (e.g. 10 minutes, 1 hour)
- **THEN** the expanded timer readout keeps its full digits with no clipping into the Island curve

#### Scenario: Categories follow the draft
- **WHEN** the running draft carries ordered categories
- **THEN** the expanded face shows them as icon chips in draft order; drafts with no categories show no chip row

### Requirement: Stop and return actions
Tapping any face outside Stop SHALL deep-link to Track (`lifio://track`). The expanded Island and banner SHALL each offer Stop as a link to `lifio://track?stop=1`: tapping opens the app, which reloads its bound account's draft, stops and saves through the ordinary in-app path, and ends the activity with the Saved card. This SHALL work on the first tap after a terminated-app cold open; no draft means a graceful no-op. The normal Stop URL SHALL be available for shipped controls; there SHALL be no nil-URL intent fallback, independent extension entry writer, or external-stop signal needed to complete Stop. Compact and minimal faces SHALL offer no buttons (tap navigates only). Existing dimmed/inert rendering is unchanged.

#### Scenario: Tap returns to Track
- **WHEN** the user taps the compact, minimal, expanded, or banner surface (outside Stop)
- **THEN** the app opens to Track for the running timer

#### Scenario: Stop from the Island saves
- **WHEN** the user activates Stop in the expanded Island while running
- **THEN** the app opens to Track and the entry is saved with the draft's final categories through the in-app Stop path, the running draft is cleared, and the activity ends with the Saved card

#### Scenario: Stop from the expanded Island with a terminated app opens and stops
- **WHEN** the user activates Stop in the expanded Island while the app process is dead (swiped away or jetsammed) and a run is active
- **THEN** the app opens and reloads before stopping, saves one entry through the normal path, and shows `✓ Saved <duration>` with the tuned dismissal — no ticking orphan survives first contact and no second tap is needed

#### Scenario: Island Stop with nothing running is a no-op
- **WHEN** the stop link opens the app with no active run (double tap, stale face)
- **THEN** the app opens to Track, nothing is written, and no error surfaces

#### Scenario: Banner Stop with a terminated app opens and stops
- **WHEN** the user activates Stop in the banner while the app process is dead and a run is active
- **THEN** the app opens, reloads, and saves through the same in-app path — no ticking orphan survives first contact and no second tap is needed

#### Scenario: Stop fails gracefully
- **WHEN** Stop is activated with no active account file or an inaccessible database (e.g. cold boot before first unlock)
- **THEN** nothing is written, no anonymous file is created, and the failed stop does not fabricate a Saved card; the ordinary auth/account lifecycle remains authoritative

#### Scenario: Dimmed rendering hides the Stop control
- **WHEN** the activity renders outside full color (Always-on dim, StandBy accent modes)
- **THEN** faces show the same layout with the Stop control dimmed and inert instead of hidden (it is not interactive there and its saturated red is quieted); the control returns to full opacity in full color

#### Scenario: Dimmed banner masks the seconds
- **WHEN** the banner renders outside full color
- **THEN** the elapsed readout keeps ticking via the system timer view, which the dimmed renderer sustains itself (no coarse static masking)

#### Scenario: Stop is link-only
- **WHEN** either shipped Stop control is activated
- **THEN** it follows the valid stop deep link; no fallback intent executes or writes an entry outside the app

### Requirement: Saved card then dismissal
Ending the activity SHALL show a final `✓ Saved <duration>` banner and then remove it via a timed dismissal (`.after`, seconds tuned during testing) whenever the true duration is known; the Island SHALL collapse at once. The system default linger (hours) SHALL NOT be used. A terminated-app Stop SHALL reach the same Saved card by opening the app into the in-app stop path. Silent immediate dismissal is reserved for reaps with no known save. Recovery from a crash between save and activity end SHALL remain available without depending on the retired extension signal.

#### Scenario: Stop shows Saved then removes
- **WHEN** the timer stops from the app or from a Live Activity Stop link that opens the app
- **THEN** the banner shows the Saved card with the final duration and is removed after the tuned delay

#### Scenario: Terminated-app Island Stop shows Saved after opening
- **WHEN** an Island Stop opens the dead app (entry saved in-app on open, no prior app contact)
- **THEN** the banner shows the `✓ Saved <duration>` face with the true duration through the normal end path and is removed after the tuned dismissal — no double card, no invented duration, no lingering running face

#### Scenario: Terminated-app banner Stop ends the activity on opening
- **WHEN** a banner Stop opens the dead app (entry saved in-app on open, no prior app contact)
- **THEN** the activity ends through the normal end path — no lingering running face

#### Scenario: Stop with a terminated app dismisses silently
- **WHEN** an orphaned activity is reaped without a known saved duration after app interruption
- **THEN** it is dismissed immediately with its last content and no card — no duration is ever invented

#### Scenario: No hour-long linger
- **WHEN** the activity has ended
- **THEN** it is gone within seconds, never lingering for hours

### Requirement: Active-account only, no extension auth or sync
The Live Activity extension SHALL only render app-published content and open the supported links; it SHALL NOT open/write tracker databases, authenticate a user, refresh credentials, or run sync. A Stop link SHALL be handled through the main app's existing auth/account gate and bound-store mutation path, never by an extension writer or by opening a dormant account file. Signed-out or unavailable-account handling SHALL NOT create anonymous data. Normal foreground sync remains app-owned and unchanged.

#### Scenario: Dormant account never surfaces
- **WHEN** another account's file is dormant and this account's file is active
- **THEN** the app publishes only the active account's timer and Stop operates only through its bound store; the extension never opens either database

#### Scenario: Signed out shows nothing
- **WHEN** no active account file exists
- **THEN** no activity is started and Stop performs no write

