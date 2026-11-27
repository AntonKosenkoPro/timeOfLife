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
   completion day), taps a task to edit it in the sheet (name plus
   ordered categories plus notes), drags it to a new position in edit
   mode (VoiceOver rotor included), or swipes a Mail-style
   delete/complete pill (shake-to-undo restores deletes via the system
   Undo confirmation). Rows show their ordered category icons and a
   notes indicator when non-empty (VoiceOver announces both); the
   running task reads `In progress` instead of Start.
5. The user taps Start on an open task when no timer is active: a task
   holding categories starts with exactly those; a task without
   categories falls back to the ordinary exact-text Recents inheritance.
   The task's notes ride the draft too. The run starts on Track with
   that task linked. While linked, category and notes edits converge
   live in both directions (Track retag/notes reach the task; sheet
   saves on the running task reach the draft; the locked name never
   moves). Stopping saves the entry and completes exactly that task;
   the Track counts refresh in place with no further navigation.

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

Each row: completion toggle → name (with ordered category icons and the
notes indicator inline) → Start affordance slot (always mounted in every
state — completed rows and the running row hide the button via
`PlannerStartSlot`, preserving the exact row height so toggling
completion moves no sibling; the running row layers the localized
`In progress` label over the same footprint instead of Start).

- Toggle: `circle` / `checkmark.circle.fill` (accent when done),
  `accessibilityLabel` `L10n.plannerMarkDone` / `L10n.plannerReopen`,
  `PlannerToggle-<id>`. Completed names render secondary + strikethrough
  and stay in position through their completion day.
- Name: tap opens the task editor sheet (Name + ordered Categories +
  Notes in Log Time sheet grammar, reduced to those three fields in that
  order; the notes row is a presenter pushing the shared
  `NotesEditorPage` with copy-on-open X/✓ semantics. The sheet saves the
  name, the set, and the notes as independent field intents, so a
  name-only edit sends no categories and a notes-only edit sends no
  name; the 2000-trimmed-rune notes bound gates Save like the Log Time
  form.
  (`PlannerName-<id>`; sheet: `PlannerEditorNameField`,
  `PlannerEditorCategories`, `PlannerEditorNotesField`,
  `PlannerEditorSaveButton`). The name control's VoiceOver label folds
  in the ordered category names and the notes presence
  (`L10n.historyHasNotes`); icons and the indicator are decorative.
- Categories/notes affordances: ordered category icons (the catalog
  display symbol per id, unknown ids drop) and, when the trimmed notes
  are non-empty, a `note.text` indicator — both inline after the name in
  the single-line layout, so no state changes the row height. VoiceOver
  announces both through the name control's label.
- Start: bordered `L10n.timerStart` (the ordinary Start string — there is
  no separate Track completion control), `PlannerStart-<id>`. Hidden for
  completed rows. While the task carries the active linked run the slot
  shows the localized `In progress` label (`L10n.plannerInProgress`,
  `PlannerInProgress-<id>`) instead — same footprint, no Start button.
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

`PlannerProgressControl` (same file): a toolbar button with a dynamic
checklist icon and `done/total` numerals. The icon follows completion:
`checklist.unchecked` at 0 done (including the empty list),
`checklist` while partially done, `checklist.checked` at N/N with N > 0
(a runtime test resolves all three symbols — a missing symbol renders
nothing). Reports the shared Today projection, offers an
entry point even when the list is empty, stays usable while timing, and
lives in the navigation chrome so the numeric readout and Start/Stop
never move. The launch gate preloads the projection, so the control shows
actual counts on first paint from warm local data (no 0/0 flash). A
linked Stop invalidates the projection, so the control refreshes in
place with no further navigation.
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
- [x] The editor sheet edits the name, the ordered category set, and the
  notes as independent field intents (Log Time sheet grammar, same field
  order/cards/validation — Name, then Categories, then a presenter
  pushing the shared notes editor); invalid and over-limit saves keep
  the sheet open with the draft intact.
- [x] Start uses the task's categories when non-empty, else exact-text
  Recents inheritance, and copies the task notes into the draft;
  persists the task id via the claim-guarded draft, and pops to Track;
  a second Start returns false with no replacement. While linked, Track
  retag/notes edits write through to the task and sheet saves on the
  running task write through to the draft, each in the same chokepoint
  transaction (locked name untouched); pending-notes review, retry,
  backdate, and Live Activity Stop paths are preserved.
- [x] Rows show ordered category icons and the notes indicator inline
  (VoiceOver announces both) and read the localized `In progress` label
  over the preserved Start slot while the task carries the run; open,
  completed, and running rows share one exact height (Reduce Motion
  respected).
- [x] A linked Stop invalidates the planner projection, so the Track
  counts refresh in place; ordinary Stop posts nothing and is unchanged.
- [x] The progress icon follows completion (`checklist.unchecked` /
  `checklist` / `checklist.checked`), resolved at runtime by test.
- [x] Live Activity Stop uses the same store path (linked completion
  unchanged, cold open included).
- [x] Strings in all five locales (`en`, `ru`, `zh-Hans`, `es-419`,
  `pt-BR`) + `L10n`; `Theme` colors only; no raw `Color` literals.
- [x] `PlannerViewModelTests` (composer, suggestions, edits, moves,
  delete/undo, Start guards, inheritance) plus focus-request generations
  (successful submits bump, invalid ones don't) and `PlannerRowLayoutTests`
  (Start slot mounted-but-hidden when done; suggestion highlight split).
