# Track Screen

This is the first non-auth screen described for the app. The local-first Track
experience lets the user choose a concrete Activity, start a timer, see exact
elapsed time, stop, and save the entry. Categories are optional Activity
metadata for management and Insights; they are not part of capture selection.

## Use case

1. The user launches locally and lands on Track.
2. The user sees the selected Activity affordance, a centered numeric timer,
   and an explicit Start action.
3. The user selects a recent Activity, searches for one, or creates a new one.
4. The user taps Start; selection alone never starts timing.
5. The numeric timer counts up from `00:00`.
6. The user taps Stop to finish the session.
7. The app saves the elapsed entry locally and syncs it when online.

## Screen: TrackView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/TimeTracking/Views/TrackView.swift`
- **Route**: Track tab in the app shell
- **ViewModel**: `TrackViewModel`

### Layout

Wrap the screen in the app shell's navigation container. Use a scrollable
content column with horizontal `Theme.spacingLarge` padding and a pinned bottom
action bar.

1. `OfflineBanner()` is rendered at the top by the root shell.
2. Navigation title: `L10n.timerTitle` (`Track`).
3. State-specific Activity preparation control below the numeric readout and
   above Recents:
   - Idle: the filled `+` button with `L10n.timerChooseActivity`, identifier
     `TimerChooseActivityButton`, and minimum height 54 pt.
   - Ready or saved: a search-styled picker with a magnifier, the prepared
     Activity name, and identifier `TimerActivitySearchButton`.
   - Running, saving, or recoverable error: a non-interactive prepared Activity
     label with identifier `TimerActivityLabel`; search is unavailable while
     timing is active.
   - No state renders more than one preparation control.
   - No control shows a Category icon or Category name.
   - The selected-Activity row is an `HStack`: the state-specific control
     (picker or label) takes flexible width, with a trailing Refine button
     (`TimerActivityRefineButton`, localized visible label, minimum 44 pt
     interaction area). Refine is visible in all non-idle states (ready,
     running, saving, saved, error) and is disabled only while saving. The
     search picker itself remains disabled outside ready/saved.
4. Numeric timer readout:
   - Elapsed time formatted as `MM:SS` or `H:MM:SS`.
   - Centered in the main content region.
   - Font: `.system(size: 78, weight: .ultraLight, design: .rounded)` or the
     approved Theme equivalent.
   - Uses `Theme.textPrimary` and `.monospacedDigit()`.
   - Keeps a stable frame across all timer states.
   - The saved-state blue checkmark is layered above the readout without
     participating in layout, so its appearance does not move the timer.
   - `accessibilityIdentifier`: `TimerDisplay`.
5. State label below the readout:
   - `READY`, `RUNNING`, `SAVING`, or `SAVED` as appropriate.
   - The exact elapsed value remains the primary state information.
6. Reserve space for the pinned bottom action bar.

Pinned bottom action bar via `.safeAreaInset(edge: .bottom)`:

- Non-field error banner, when needed, above the primary action.
- Primary control in one stable position:
  - `L10n.timerStart` with `play.fill` when ready.
  - `L10n.timerStop` with `stop.fill` when running.
  - `TimerStartButton` / `TimerStopButton` identifiers.
  - Stop hint: `L10n.timerStopHint` - stops the timer and saves the entry.
- Offline hint below the primary control when appropriate.

The Track screen has no Dial, ring, sweep, goal, daily-total, or decorative
progress visualization.

### Activity search sheet

Tapping the idle `TimerChooseActivityButton` or the ready/saved
`TimerActivitySearchButton` is the single Activity-search entry point for that
state. It presents a full-height sheet containing a native, always-visible
search field and ordinary result content. The operating system owns field
placement, focus, keyboard, activation animation, and Cancel; the sheet owns
its presentation and dismissal:

- Empty query: the complete Activity catalog in recency order
  (`last_used_at`), with the prepared Activity marked.
- Non-empty query: case-insensitive containment matches in recency order.
- Exact normalized match (trimmed, case-insensitive): identified first; no
  create action is offered for that name.
- Valid unmatched input: a single full-width quick-create row (categoryless)
  that prepares the Activity directly.
- Invalid input: existing search results stay available, creation is
  suppressed, and localized validation guidance is shown.
- A non-expired pending-deletion identity matching the query offers explicit
  restoration instead of creation.
- Empty catalog: the content area explains the empty state and prompts the
  user to enter a name in the native search field — no separate alert.
- The search content never requires a Category and never shows Category
  metadata.

Search input is a temporary draft: it never changes the committed prepared
Activity. Native Cancel and swipe-down dismissal close the sheet and restore
the prior ready or idle timer state exactly. Selecting, quick-creating, or
restoring is the only commit boundary — it prepares the Activity and
dismisses the sheet.

Selection changes the ready state only. The timer starts only after the user
activates Start.

### Activity and Category relationship

- **Activity** is the concrete task being timed and is required for an entry.
- **Category** is optional analytics metadata; an Activity may have zero or more
  Categories.
- Manage Activities and Manage Categories are separate surfaces.
- The full Activity Editor may assign or remove Categories.
- Category assignment is not required to start a timer.
- Entries reference `activity_id` and resolve the Activity's current Categories
  at query time. Editing an Activity's Categories therefore reclassifies its
  existing history in Insights.

### Keyboard handling

The Track screen does not keep a free-text field in the primary capture
layout. Search and Activity editing follow `Design/INTERACTIONS.md` ->
**Keyboard and primary input placement**. The native search field stays
above the keyboard; the editor's Save action is pinned with
`.safeAreaInset(edge: .bottom)`.

### Layout stability rule

- The numeric readout and state-specific preparation/primary controls keep
  their interaction regions across idle, ready, running, saving, and saved
  states.
- Only the Activity state, readout value, label, button title/icon, and tint
  change.
- No dial, ring, or progress card appears or disappears around the readout.
- The primary action remains visible above the keyboard and safe-area inset.

### Behaviors

- Open Activity search from the state-specific preparation control below the
  timer.
- Selecting a recent Activity prepares it without creating an entry.
- Quick-creating an unmatched Activity prepares it locally without Categories.
- Refine (visible in every non-idle state, disabled only while saving) opens
  the shared Activity Editor prefilled with the selected Activity's name,
  notes, and Categories. Saving replaces the Activity in place in the current
  TrackState — no transition — preserving startedAt, duration, and the
  ticker; cancelling or failing leaves the selected Activity and timer state
  unchanged.
- Start revalidates the prepared Activity by identifier; a prepared Activity
  that no longer exists clears preparation and returns to idle with a
  localized error (it is never silently recreated).
- Start persists the running timer immediately, begins periodic readout refresh,
  emits selection feedback, and keeps the screen awake.
- Stop calculates elapsed time, saves the entry locally, emits success feedback,
  and returns to the ready state for the same Activity.
- Save errors preserve recoverable running state and appear above the primary
  action without a blocking loader.
- A running timer remains visible above the tab bar on History and Insights;
  its Stop action saves in place.
- Profile owns sign-out and account/sync controls rather than the Track toolbar.
- Dynamic Type keeps the readout, Activity name, and Start/Stop action readable.
- Reduce Motion uses fades or immediate state changes rather than custom motion.

### States

| State | Visual |
|---|---|
| Idle | No Activity selected; centered readout shows `00:00`; choose Activity prompt and Start are shown or Start is disabled according to validation policy. |
| Ready | Selected Activity name; centered readout shows `00:00`; Start button shown. |
| Search active | Searchable sheet with a native field; content area shows browse/filtered results, create or restore actions, empty-catalog guidance, or validation/error states; committed timer state unchanged. |
| Running | Prepared Activity label remains visible; readout updates live; Stop button shown with destructive tint. |
| Saving | Readout remains stable; Stop action shows progress while the save completes. |
| Saved | Brief saved confirmation above the readout; the same Activity remains prepared with `00:00` and Start, and the timer stays in its prior position. |
| Error | Localized non-field error appears above the primary action; recoverable running state is preserved. |

### Data model

```swift
struct TimeEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let activityId: UUID
    let startedAt: Date
    let endedAt: Date?
    var duration: TimeInterval { endedAt.map { $0.timeIntervalSince(startedAt) } ?? 0 }
    var source: String
    var sourceRef: String?
}
```

Activity name and Categories are resolved from the local catalog by
`activityId`; they are not denormalized onto the entry. There is no `synced`
flag on the model: sync is outbox-driven (every mutation writes a transactional
outbox row; the relay is the transport, not a per-record state).

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys in English and Russian.
- [ ] Activity search, readout, and Start/Stop controls have stable identifiers.
- [ ] Numeric readout is centered, fixed, and `.monospacedDigit()`.
- [ ] Suggestions and search rows expose Activity names only.
- [ ] Start follows explicit selection and persists running state.
- [ ] Stop saves locally and preserves recoverable state on failure.
- [ ] Compact timer is available above History and Insights navigation.
- [x] VoiceOver, Dynamic Type, Reduce Motion, light/dark, and iOS 15 are tested.
- [ ] SwiftLint and warning-as-error builds pass.

## Localization keys

Add English and Russian values, then add corresponding `L10n` cases:

```text
"timer.title" = "Track";
"timer.chooseActivity" = "Choose an activity";
"timer.start" = "Start";
"timer.stop" = "Stop";
"timer.stopHint" = "Stops the timer and saves the entry";
"timer.saved" = "Saved";
"timer.suggestionsHeader" = "Recent activities";
"timer.quickAdd" = "New activity";
"timer.manageActivities" = "Manage activities";
```

## Catalog behavior

Suggestions are computed on-device from the local catalog and ranked by
`last_used_at`. Each row contains the Activity name and recency only. Category
icons and names belong in Manage Activities, Manage Categories, Activity Editor,
and Insights, not in the capture search.

The search sheet offers a single full-width quick-create row that saves an
Activity with no Categories. Starting with a new name still auto-creates a
categoryless Activity, reuses a case-insensitive match, and never forces the
user into category management.

Manage Activities and Manage Categories are separate destinations/sheets. Both
remain available offline and use the existing sync-conflict and 30-second
undo rules.
