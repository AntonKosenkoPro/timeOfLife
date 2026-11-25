# Today Planner Screen

The day-planner checklist (add-day-planner): one ordered backlog per
account, projected onto a single Today view — unfinished tasks plus
completions on the viewing device's current local civil date, in the
shared `(position_key, id)` order, with done/total counts from the same
snapshot. There is no tomorrow view, manual rollover, or carry-forward
button: carry-forward is automatic and needs no mutation or sync write.
Planner rows never feed History, Insights, or Recents.

## Use case

1. The user sees the compact progress control (`done/total`) in Track's
   navigation chrome and taps it.
2. Today pushes onto the Track navigation stack (no new tab).
3. The user types in the inline composer and taps Return (or the Add
   affordance): one task appends after the existing Today rows, the draft
   clears, and the field keeps focus with the keyboard open for the next
   task. A matching Recent tap fills the exact text for editing or
   submission — no task is created, no timer starts.
4. The user toggles a task done (it stays in position through its
   completion day), renames it inline, drags it to a new position in edit
   mode (VoiceOver rotor included), or swipes to delete (shake-to-undo
   restores via the system Undo confirmation).
5. The user taps Start on an open task when no timer is active: the exact
   text goes through the ordinary category-inheritance rule and the run
   starts on Track with that task linked. Stopping saves the entry and
   completes exactly that task.

## Screen: PlannerView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Planner/Views/PlannerView.swift`
- **Route**: `ShellRoute.planner` on the Track path (pushed from the
  toolbar progress control; pops back to Track after a successful Start)
- **ViewModel**: `PlannerViewModel` (owned by `AppShellView`, shared by the
  toolbar control and this page — one snapshot, one serialized reload)

### Layout

Top-to-bottom order:

1. Navigation title: `L10n.plannerTitle` (`Today`), `.inline` display mode.
2. Inline composer (fixed slot above the list, so submitting never moves
   it): a `TextField` (`L10n.plannerComposerPlaceholder`, `.submitLabel(.done)`,
   `onSubmit` → submit) plus an Add button (`L10n.plannerAdd`, disabled for
   blank drafts). `accessibilityIdentifier`s: `PlannerComposerField`,
   `PlannerAddButton`.
3. Suggestions section at the top of the same `List` (only while the
   draft is non-empty, never a separate mounting region): at most
   `suggestionDisplayCap` (5) newest-first Recents filtered by
   case-insensitive prefix, each row rendering the matched prefix bold.
   Tapping one fills the exact text only. `accessibilityIdentifier`:
   `PlannerSuggestions` on the section (`PlannerSuggestion-<text>` per
   row); VoiceOver order is document order (suggestions, then tasks).
4. Timer-active caption (`L10n.plannerTimerActive`, secondary, caption
   case) while a run is active — Start buttons disable but the checklist
   stays fully usable.
5. Empty hint (`L10n.plannerEmptyHint`) when the projection is empty and
   there are no suggestions, or the single checklist `List(.plain)`
   otherwise (`accessibilityIdentifier`: `PlannerTaskList`).

The composer sits outside the `List`, so its frame never moves; every
successful submit bumps `composerFocusRequests` and the view re-asserts
input focus, so reloads and the suggestions section mount/unmount never
steal the keyboard. Scroll position is the list's own. Track geometry is
untouched: the only Track change is the toolbar progress item.

### Rows

Each row: completion toggle → name → Start affordance slot (always
mounted in both states — completed rows hide it via
`PlannerStartSlot.hiddenPreservingLayout`, preserving the exact row
height so toggling completion moves no sibling; open-task taps Start
unless a run is active).

- Toggle: `circle` / `checkmark.circle.fill` (accent when done),
  `accessibilityLabel` `L10n.plannerMarkDone` / `L10n.plannerReopen`,
  `PlannerToggle-<id>`. Completed names render secondary + strikethrough
  and stay in position through their completion day.
- Name: tap renames inline (a `TextField` bound to the edit draft, Return
  commits, × cancels per the Track clear-button grammar, focus loss
  commits). Empty commits revert with no write.
  (`PlannerRenameField-<id>`, `PlannerName-<id>`).
- Start: bordered `L10n.timerStart` (the ordinary Start string — there is
  no separate Track completion control), `PlannerStart-<id>`. Hidden for
  completed rows.
- Delete: swipe-to-delete into the durable undo buffer (no outbox row
  yet); shake restores through the DEFAULT system Undo confirmation
  (entry/category precedent, `L10n.entryDeleteConfirm` action name).
- Reorder: the list's `onMove` in visible coordinates (EditButton in the
  trailing toolbar; VoiceOver rotor reorder, never drag-only). Moves
  allocate a key between the new visible neighbors — no other row is
  rewritten — and respect Reduce Motion (no explicit animations anywhere
  on this page).

### Progress control

`PlannerProgressControl` (same file): a toolbar button with a list icon
and `done/total` numerals. Reports the shared Today projection, offers an
entry point even when the list is empty, stays usable while timing, and
lives in the navigation chrome so the numeric readout and Start/Stop
never move. `accessibilityLabel`:
`L10n.plannerProgressLabel` (`%1$d of %2$d` per locale, no plurals by
construction). `accessibilityIdentifier`: `PlannerProgressControl`.

### Implementation checklist

- [x] `PlannerViewModel` serializes reloads (`loadIfNeeded` + `invalidate`,
  Track precedent); tab-return, foreground return, time-zone change, and
  sync-cycle exit all funnel through it; no-op reloads publish nothing.
- [x] Composer draft survives every reload; invalid/failed submissions
  append nothing and keep the draft.
- [x] New tasks append after the existing Today rows (allocate after the
  last visible key); visible-neighbor moves never rewrite other rows.
- [x] Completing/reopening keeps position and never touches timers or
  entries; identical names stay independent.
- [x] Start copies the name with exact-text category inheritance, persists
  the task id via the claim-guarded draft, and pops to Track; a second
  Start returns false with no replacement.
- [x] Live Activity Stop uses the same store path (linked completion
  unchanged, cold open included).
- [x] Strings in all five locales (`en`, `ru`, `zh-Hans`, `es-419`,
  `pt-BR`) + `L10n`; `Theme` colors only; no raw `Color` literals.
- [x] `PlannerViewModelTests` (composer, suggestions, edits, moves,
  delete/undo, Start guards, inheritance) plus focus-request generations
  (successful submits bump, invalid ones don't) and `PlannerRowLayoutTests`
  (Start slot mounted-but-hidden when done; suggestion highlight split).
