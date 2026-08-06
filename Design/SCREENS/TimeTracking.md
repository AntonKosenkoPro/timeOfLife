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

## Screen: TimerView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/TimeTracking/Views/TimerView.swift`
- **Route**: `.timer` during the shell migration
- **ViewModel**: `TimerViewModel`

### Layout

Wrap the screen in the app shell's navigation container. Use a scrollable
content column with horizontal `Theme.spacingLarge` padding and a pinned bottom
action bar.

1. `OfflineBanner()` is rendered at the top by the root shell.
2. Navigation title: `L10n.timerTitle` (`Track`).
3. Selected Activity button:
   - `accessibilityIdentifier`: `TimerActivityPicker`.
   - Minimum tap area: `Theme.minTapArea`.
   - Shows the concrete Activity name or a choose-an-Activity prompt.
   - Does not show a Category icon or Category name.
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

### Activity picker

Tapping `TimerActivityPicker` presents a searchable native sheet:

- Recent Activity names appear before search, ordered by `last_used_at`.
- Search matches Activity names case-insensitively.
- Unmatched valid input offers `Create "Name"`.
- Selecting or creating an Activity prepares it and dismisses the sheet.
- The sheet never requires a Category and never shows Category metadata.
- A Manage Activities entry point is available as a secondary action.
- An Activity created here is valid with zero Categories.

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

The Track screen does not keep a free-text field in the primary capture layout.
Search and Activity editing follow `Design/INTERACTIONS.md` -> **Keyboard and
primary input placement**. The search/name field stays above the keyboard and
the sheet's Save action is pinned with `.safeAreaInset(edge: .bottom)`.

### Layout stability rule

- The Activity affordance, numeric readout, state label, and primary action keep
  their interaction regions across ready, running, saving, and saved states.
- Only the Activity state, readout value, label, button title/icon, and tint
  change.
- No dial, ring, or progress card appears or disappears around the readout.
- The primary action remains visible above the keyboard and safe-area inset.

### Behaviors

- Open the Activity picker from the selected Activity affordance.
- Selecting a recent Activity prepares it without creating an entry.
- Creating an unmatched Activity prepares it locally without Categories.
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
| Running | Activity affordance remains visible; readout updates live; Stop button shown with destructive tint. |
| Saving | Readout remains stable; Stop action shows progress while the save completes. |
| Saved | Brief saved confirmation; same Activity remains prepared with `00:00` and Start. |
| Error | Localized non-field error appears above the primary action; recoverable running state is preserved. |

### Data model

```swift
struct TimeEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let activityId: UUID
    let startedAt: Date
    let endedAt: Date
    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var synced: Bool
}
```

Activity name and Categories are resolved from the local catalog by
`activityId`; they are not denormalized onto the entry.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys in English and Russian.
- [ ] Activity picker, readout, and Start/Stop controls have stable identifiers.
- [ ] Numeric readout is centered, fixed, and `.monospacedDigit()`.
- [ ] Suggestions and picker rows expose Activity names only.
- [ ] Start follows explicit selection and persists running state.
- [ ] Stop saves locally and preserves recoverable state on failure.
- [ ] Compact timer is available above History and Insights navigation.
- [ ] VoiceOver, Dynamic Type, Reduce Motion, light/dark, and iOS 15 are tested.
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

## Epic 1 behavior

Suggestions are computed on-device from the local catalog and ranked by
`last_used_at`. Each row contains the Activity name and recency only. Category
icons and names belong in Manage Activities, Manage Categories, Activity Editor,
and Insights, not in the capture chooser.

Quick-add presents the shared Activity Editor as a sheet. The user may save an
Activity with no Categories and assign Categories later. Starting with a new
name still auto-creates a categoryless Activity, reuses a case-insensitive
match, and never forces the user into category management.

Manage Activities and Manage Categories are separate destinations/sheets. Both
remain available offline and use the existing sync-conflict and 30-second
undo rules.
