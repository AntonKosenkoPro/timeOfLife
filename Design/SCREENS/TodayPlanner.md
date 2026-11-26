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
3. The user types in the inline composer and taps Return (or the
   composer's Add accessibility action — there is no visible Add
   button): one task prepends before the existing Today rows, the draft
   clears, and the field keeps focus with the keyboard open for the next
   task. A matching Recent tap fills the exact text for editing or
   submission — no task is created, no timer starts. A draft matching
   nothing shows the no-match placeholder in the chips line; the ×
   clears the draft without losing the keyboard.
4. The user toggles a task done (it stays in position through its
   completion day), renames it inline, drags it to a new position in edit
   mode (VoiceOver rotor included), or swipes a Mail-style
   delete/complete pill (shake-to-undo restores deletes via the system
   Undo confirmation).
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

1. Navigation title: `L10n.plannerTitle` (`Today`), `.inline` display mode,
   with the running-timer notice (`L10n.plannerTimerActive`, secondary
   caption) as a nav-bar subtitle under the title while a run is active
   (`accessibilityIdentifier`: `PlannerTimerSubtitle`) — never an inline
   caption in the list.
2. Checklist `List(.plain)` (`accessibilityIdentifier`: `PlannerTaskList`):
   open and completed-Today rows in the shared order, no section header.
   Empty projection shows the empty hint (`L10n.plannerEmptyHint`) instead.
3. Bottom-fixed composer card: the UIKit-backed inline field
   (`PlannerComposerField`, `L10n.plannerComposerPlaceholder`) wrapped in
   the shared `FieldCard` chrome (secondary background against the
   primary page, `minTapArea` minimum height). No visible Add button:
   Return submits, and the composer's Add accessibility action
   (`L10n.plannerAdd`) keeps the VoiceOver submit path. A trailing clear
   button (the Track × grammar — small dim trailing × while editing,
   `accessibilityIdentifier`: `PlannerComposerClear`) empties the draft
   without dismissing the keyboard or losing focus.
   `accessibilityIdentifier`s: `PlannerComposerField`.
   Return submits without ever resigning first responder (no
   dismiss/reopen cycle of any duration); the composer never unmounts, so
   submitting never moves it and the keyboard stays open across repeated
   Returns.
4. Chips line (`accessibilityIdentifier`: `PlannerChips`), only while the
   keyboard is open: a single horizontally scrollable row of at most
   `chipDisplayCap` newest-first Recents, prefix-filtered by the
   draft (empty draft shows the full capped strip; a draft matching
   nothing shows the localized no-match placeholder,
   `L10n.plannerNoMatch`, `accessibilityIdentifier`:
   `PlannerChipsNoMatch`, instead of an empty strip). Tapping one fills the
   exact text only — no task is created, no timer starts. A
   `spacingSmall` breathing gap sits between the line and the keyboard;
   the slot holds one chip-row height while mounted (hidden prototype
   for a blank filter), so filter changes never move the
   composer or the list. VoiceOver order is document order (list, then
   composer, then chips), matching the visual layout.

The composer sits outside the `List`, so its frame never moves; the
UIKit field declines the Return resign at dispatch, so store writes,
snapshot reloads, and the chips line mount/unmount never steal the
keyboard. Scroll position is the list's own. Track geometry is
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
- Swipes (Mail-style icon+text pills): trailing-side Delete
  (`L10n.entryDeleteConfirm`, `trash`, danger tint, full-swipe deletes)
  into the durable undo buffer (no outbox row yet); leading-side
  complete/reopen (`L10n.plannerMarkDone` / `L10n.plannerReopen`,
  `checkmark` / `arrow.uturn.backward`, accent tint) with the toggle
  semantics — position kept, timers and entries untouched. Edit-mode
  delete/reorder (`onDelete` / `onMove`) and shake-to-undo are unchanged:
  shake restores through the DEFAULT system Undo confirmation
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
never move. The launch gate preloads the projection, so the control shows
actual counts on first paint from warm local data (no 0/0 flash).
`accessibilityLabel`:
`L10n.plannerProgressLabel` (`%1$d of %2$d` per locale, no plurals by
construction). `accessibilityIdentifier`: `PlannerProgressControl`.

### Implementation checklist

- [x] `PlannerViewModel` serializes reloads (`loadIfNeeded` + `invalidate`,
  Track precedent); tab-return, foreground return, time-zone change, and
  sync-cycle exit all funnel through it; no-op reloads publish nothing.
- [x] Composer draft survives every reload; invalid/failed submissions
  add nothing and keep the draft.
- [x] New tasks prepend before the existing Today rows (allocate before
  the first visible key); visible-neighbor moves never rewrite other rows.
- [x] The launch gate preloads the Today projection and the shell adopts
  it, so Track shows actual counts on first paint from warm local data.
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
