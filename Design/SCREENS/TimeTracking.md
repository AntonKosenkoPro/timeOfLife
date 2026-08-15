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

Wrap the screen in the app shell's navigation container. Content is a
scrollable column with horizontal `Theme.spacingLarge` padding and a dual-flow
vertical composition; the adaptive spacers collapse to zero before scrolling
engages.

Top-to-bottom order:

1. Navigation title: `L10n.timerTitle` (`Track`).
2. Top adaptive spacer (see adaptive spacing below).
3. Completion-mark region: the saved-state confirmation appears here, above
   the readout, without moving the timer content.
4. Numeric timer readout:
   - Elapsed time formatted as `MM:SS` or `H:MM:SS`.
   - Centered in the main content region.
   - Font: `.system(size: 78, weight: .ultraLight, design: .rounded)` or the
     approved Theme equivalent.
   - Uses `Theme.textPrimary` and `.monospacedDigit()`.
   - Keeps a stable frame across all timer states.
   - `accessibilityIdentifier`: `TimerDisplay`.
5. State label below the readout:
   - `READY`, `RUNNING`, `SAVING`, or `SAVED` as appropriate.
   - The exact elapsed value remains the primary state information.
6. Reserved non-field-error region, immediately above the central separator:
   - Preserves its reserved height when no error is shown, without exposing
     an empty accessibility element.
   - Error text wraps fully and is never cut: when the wrapped error is taller
     than the reservation, the region grows and the flexible spacing yields
     first.
   - `accessibilityIdentifier`: `TrackErrorBanner`.
7. Central separator: receives free space beyond twice the shared cap (see
   adaptive spacing below).
8. Activity search/refine row (the selected-Activity row):
   - Idle: the slot is reserved — the picker geometry is kept but invisible,
     non-interactive, and absent from the accessibility tree — so preparing
     an Activity never moves the main action below it.
   - Ready or saved: a full-width search-styled picker with a magnifier, the
     prepared Activity name, and identifier `TimerActivitySearchButton`.
   - Running, saving, or recoverable error: a non-interactive prepared Activity
     label with identifier `TimerActivityLabel`; search is unavailable while
     timing is active.
   - No state renders more than one preparation control.
   - No control shows a Category icon or Category name.
   - No editing affordance: the former beside-picker Refine and any "Edit
     activity" variant are removed; editing placement is deferred to a later
     change.
9. State-specific main action in one stable region:
   - `L10n.timerStart` with `play.fill` when ready, identifier
     `TimerStartButton`.
   - `L10n.timerStop` with `stop.fill` when running, identifier
     `TimerStopButton`.
   - Stop hint: `L10n.timerStopHint` - stops the timer and saves the entry.
   - The region changes between these controls without moving; it sits above
     Recents so Choose Activity / Start / Stop stays reachable without
     scrolling.
   - The action renders in a fixed-height slot equal to the tallest of its
     state titles (Choose an activity / Start / Stop) at the active Dynamic
     Type size, so the control's frame is identical in idle, ready, running,
     saving, saved, and error states.
10. Recents: the wrapping chip flow of the most-recently-used Activities (see
    Recents below); hidden while a timer is running while its occupied
    height is preserved, so the main action never moves.
11. Bottom adaptive spacer (see adaptive spacing below).
12. Tab bar.

Adaptive spacing:

- The top and bottom spacers share one maximum-height token: **48 pt**,
  selected from the 24/48/72/96 Pro Max spike comparison and validated on
  iPhone SE (default and Large Dynamic Type).
- With free space `slack = viewport - content`, each spacer resolves to
  `min(cap, slack / 2)` — the two are always equal.
- Surplus beyond twice the cap goes to the central separator between the
  error region and the search/refine flow.
- When space is constrained (short screens, large Dynamic Type), all three
  flexible regions collapse to zero and the ordered content scrolls.
- Main-action pinning (D10): the content height around the main action is
  state-invariant (reserved idle preparation slot, preserved Recents height
  while running, fixed-height action slot), so the equal split recomputes
  identically in every state. A wrapped error's growth beyond the reserved
  error height compresses the top spacer first, then the central separator —
  both above the main action, keeping it stationary — and the bottom spacer
  collapses only when both are exhausted, at which point the content
  scrolls.

The Track screen has no Dial, ring, sweep, goal, daily-total, or decorative
progress visualization.

### Recents

- Wrapping chip flow of the most-recently-used Activities, capped at six,
  most-recently-used first; no horizontal scrolling.
- Each chip shows the icon of the first assigned Category (first by assignment
  position) in a fixed symbol slot; categoryless Activities render name-only
  chips with no icon and no placeholder glyph. Category names are never shown.
- The prepared Activity's chip uses a filled accent presentation (accent
  background, on-accent text, accent border) and keeps its icon; no checkmark.
- Minimum 44 pt tap targets; a tap prepares the Activity without starting
  timing.
- Recents are hidden while a timer is running; their occupied height is
  preserved so the main action does not move.
- Empty catalog: a dedicated localized hint (`timer.recentsEmptyHint`,
  "Activities you track will appear here." / «Здесь появятся активности,
  которые вы отслеживаете.»), not the search sheet's empty-catalog copy.

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
layout. Search follows `Design/INTERACTIONS.md` -> **Keyboard and primary
input placement**. The native search field stays above the keyboard; the
editor's Save action is pinned with `.safeAreaInset(edge: .bottom)`.

### Layout stability rule

- The numeric readout, state-specific preparation control, and main action
  keep their interaction regions across idle, ready, running, saving, and
  saved states.
- The main-action control's frame is identical in every state: the layout
  reserves the preparation-row slot while idle, preserves Recents' occupied
  height while running, renders the action in a fixed-height slot, and lets
  wrapped-error growth yield from the top spacer before the central
  separator.
- Only the Activity state, readout value, label, button title/icon, and tint
  change.
- No dial, ring, or progress card appears or disappears around the readout.
- The main action remains visible above the tab bar; adaptive spacing yields
  before any content clips, overlaps, or becomes unreachable.

### Behaviors

- Open Activity search from the state-specific preparation control above
  Recents.
- Selecting a recent Activity prepares it without creating an entry.
- Quick-creating an unmatched Activity prepares it locally without Categories.
- Start revalidates the prepared Activity by identifier; a prepared Activity
  that no longer exists clears preparation and returns to idle with a
  localized error (it is never silently recreated).
- Start persists the running timer immediately, begins periodic readout refresh,
  emits selection feedback, and keeps the screen awake.
- Stop calculates elapsed time, saves the entry locally, emits success feedback,
  and returns to the ready state for the same Activity.
- Save errors preserve recoverable running state and appear in the reserved
  non-field-error region without a blocking loader; error text wraps fully and
  is never cut.
- A running timer remains visible above the tab bar on History and Insights;
  its Stop action saves in place.
- Profile owns sign-out and account/sync controls rather than the Track toolbar.
- Dynamic Type keeps the readout, Activity name, and Start/Stop action readable;
  the adaptive spacers and central separator collapse before any content is
  clipped or unreachable.
- Reduce Motion uses fades or immediate state changes rather than custom motion.

### States

| State | Visual |
|---|---|
| Idle | No Activity selected; centered readout shows `00:00`; choose Activity prompt and Start are shown or Start is disabled according to validation policy. |
| Ready | Selected Activity name; centered readout shows `00:00`; Start button shown. |
| Search active | Searchable sheet with a native field; content area shows browse/filtered results, create or restore actions, empty-catalog guidance, or validation/error states; committed timer state unchanged. |
| Running | Prepared Activity label remains visible; readout updates live; Stop button shown with destructive tint; Recents hidden with its height preserved. |
| Saving | Readout remains stable; Stop action shows progress while the save completes. |
| Saved | Brief saved confirmation in the completion-mark region above the readout; the same Activity remains prepared with `00:00` and Start, and the timer stays in its prior position. |
| Error | Localized non-field error in the reserved region above the central separator; text wraps fully and the region grows past the reservation when needed, with the top spacer yielding first and then the central separator so the main action stays stationary; recoverable running state is preserved. |

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
- [ ] Recents chips show the first assigned Category's icon only; no names.
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
"timer.chooserRecent" = "Recent";
"timer.recentsEmptyHint" = "Activities you track will appear here.";
"timer.selectActivity" = "Select %@";
"timer.quickAdd" = "New activity";
"timer.manageActivities" = "Manage activities";
```

## Catalog behavior

Recents are computed on-device from the local catalog and ranked by
`last_used_at`, capped at six, most-recently-used first. Each chip contains the
Activity name and, when the Activity has Categories, the icon of the first
assigned Category — never a Category name. Category icons belong in Manage
Activities, Manage Categories, Activity Editor, and Insights; on Track they
appear only in Recents chips. The search sheet and the selected-Activity row
remain category-free.

The search sheet offers a single full-width quick-create row that saves an
Activity with no Categories. Starting with a new name still auto-creates a
categoryless Activity, reuses a case-insensitive match, and never forces the
user into category management.

Manage Activities and Manage Categories are separate destinations/sheets. Both
remain available offline and use the existing sync-conflict and 30-second
undo rules.
