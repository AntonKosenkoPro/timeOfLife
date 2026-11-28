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
   task. While editing, a trailing dismiss control offers explicit
   keyboard dismissal without submitting; Return on an empty draft
   dismisses too — the only submit-path resign allowed. A matching Recent tap fills the exact text for editing or
   submission and stages that Recent's full category set for the created
   task — no task is created, no timer starts (the tap plays the
   selection haptic); the line then shows only the selected chip in the
   filled-accent selected presentation until typing resumes, and
   submitting creates the task with the staged set (the save plays the
   success haptic). A draft matching
   nothing shows the no-match placeholder in the chips line; the ×
   clears the draft (and any staged set) without losing the keyboard.
4. The user toggles a task done (it stays in position through its
   completion day), taps an open task to edit it in the sheet (name plus
   ordered categories plus notes — the manual entry form minus Start/End;
   editing the running task shows the `In progress` subheader), reorders
   through the dedicated reorder control (no Edit button, no edit-mode
   deletion UI — drag handles plus the VoiceOver rotor), deletes the
   sheet's task at the bottom of the sheet (disabled for the running task:
   the tap shakes the subheader and plays the reject haptic instead), or
   swipes a Mail-style delete/complete pill (shake-to-undo restores
   deletes via the system Undo confirmation). Completed taps are a no-op
   and the running task offers no row delete affordance. Rows show their ordered
   categories as small icon+name chips under the name and a notes
   indicator trailing the chips (VoiceOver announces name, then
   categories, then notes); the running task reads the accent-colored
   `In progress` label instead of Start; a non-planner run names itself
   in the Today nav-bar subheader (`<name> is in progress now`) instead
   — no other timer-running subtitle exists.
5. The user taps Start on an open task when no timer is active: a task
   holding categories starts with exactly those; a task without
   categories falls back to the ordinary exact-text Recents inheritance.
   The task's notes ride the draft too. The run starts on Track with
   that task linked. While linked, category and notes edits converge
   live in both directions (Track retag/notes reach the task; sheet
   saves on the running task reach the draft; the locked name never
   moves) with each screen refreshing in place — no navigation needed.
   Stopping saves the entry and completes exactly that task;
   the Track counts refresh in place with no further navigation.

## Screen: PlannerView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Planner/Views/PlannerView.swift`
- **Route**: `ShellRoute.planner` on the Track path (pushed from the
  toolbar progress control; pops back to Track after a successful Start)
- **ViewModel**: `PlannerViewModel` (owned by `AppShellView`, shared by the
  toolbar control and this page — one snapshot, one serialized reload)

### Layout

Top-to-bottom order:

1. Navigation title: `L10n.plannerTitle` (`My Day`), `.inline` display
   mode, with no subtitle — the running indicator lives on the row: a
   planner-linked run reads the accent-colored `In progress` row label,
   and a Start tapped while any run is active shows the row's inline red
   error (`L10n.plannerBlockedStart`) instead of starting.
2. Checklist `List(.plain)` (`accessibilityIdentifier`: `PlannerTaskList`):
   open and completed-Today rows in the shared order, no section header.
   Empty projection shows the empty hint (`L10n.plannerEmptyHint`) instead.
3. Bottom-fixed composer card: the UIKit-backed inline field
   (`PlannerComposerField`, `L10n.plannerComposerPlaceholder`) wrapped in
   the shared `FieldCard` chrome (secondary background against the
   primary page, `minTapArea` minimum height, contrasting hairline
   border in both appearances). A persistent leading plus (decorative,
   hidden from assistive tech) names the purpose with and without typed
   text. No visible Add button:
   Return submits, and the composer's Add accessibility action
   (`L10n.plannerAdd`) keeps the VoiceOver submit path. A trailing clear
   button (the Track × grammar — small dim trailing × while editing,
   `accessibilityIdentifier`: `PlannerComposerClear`) empties the draft
   without dismissing the keyboard or losing focus. While editing, a
   detached circular × button beside the card (Mail search-clear grammar:
   dark filled circle with an xmark, `xmark.circle.fill`,
   `L10n.plannerDismissKeyboard`, `PlannerComposerDismiss`) resigns
   without submitting; Return on an empty draft dismisses too — the
   only submit-path resign allowed.
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
   `PlannerChipsNoMatch`, instead of an empty strip). Each chip shows its
   Recent's first category icon plus the exact text. Tapping one fills
   the composer and stages the Recent's full ordered set for the created
   task — no task is created, no timer starts; chip taps play the
   selection haptic, and the line then shows only the selected chip in
   the filled-accent selected presentation (Track Recents parity) until
   typing resumes, the set surviving until the
   draft clears or another chip is tapped. A
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

Each row: completion toggle → name with the ordered set as small
icon+name chips under it (Live Activity chip grammar: cap 2 + `+n`
overflow) and the notes indicator trailing the chips → Start affordance
slot (always mounted in every state — completed rows and the running row
hide the button via `PlannerStartSlot`, preserving the exact row height
so toggling completion moves no sibling; the running row layers the
localized `In progress` label in the accent color over the same footprint
instead of Start). VoiceOver order is name → chips → indicator →
actions, announced through the name control's combined label.

- Toggle: `circle` / `checkmark.circle.fill` (accent when done),
  `accessibilityLabel` `L10n.plannerMarkDone` / `L10n.plannerReopen`,
  `PlannerToggle-<id>`. Completed names render secondary + strikethrough
  and stay in position through their completion day.
- Name: tap opens the task editor sheet — the manual entry form with the
  Start and End cards omitted (the shared `EntryNameCard` push row into
  `NamePicker`, the same Categories card with the shared `TagSelector`,
  the same Notes presenter pushing the shared `NotesEditorPage` with
  copy-on-open X/✓ semantics; same order, same validation, same save
  gate). The running task's Name is read-only — a locked label in the
  same card chrome (no chevron, no push) — while its Categories and
  Notes stay editable and converge live. Completed taps are a no-op — a
  completed task is edited only after reopening. Editing the running
  task shows the `In progress` subheader under the title
  (`PlannerEditorSubheader`). The sheet saves the name, the set, and
  the notes as independent field intents, so a name-only edit sends no
  categories and a notes-only edit sends no name; the 2000-trimmed-rune
  notes bound gates Save like the Log Time form. A bottom delete (the
  shared red destructive `Delete` control, `L10n.entryDeleteConfirm`,
  `PlannerEditorDeleteButton` — identical to the entry editing form)
  removes the sheet's task into the durable undo buffer and pops the
  sheet — except for the running task, whose delete renders dimmed but
  stays tappable: the tap shows an explicit red error under it
  (`L10n.plannerDeleteRunning`, `PlannerEditorDeleteError`), shakes it,
  and plays the reject haptic instead of deleting.
  (`PlannerName-<id>`; sheet: `PlannerEditorNameRow`,
  `PlannerEditorCategories`, `PlannerEditorNotesRow`,
  `PlannerEditorDeleteButton`, `PlannerEditorSaveButton`). The name control's VoiceOver label folds
  in the ordered category names and the notes presence
  (`L10n.historyHasNotes`); chips and the indicator are decorative.
- Categories/notes affordances: the task's ordered set as small icon+name
  chips under the task name (the catalog display symbol per id, unknown
  ids drop; at most two chips plus a `+n` overflow) and, when the trimmed
  notes are non-empty, a `note.text` indicator trailing the chips — both
  depend only on the set and notes (never on completion or the run), so
  toggling keeps the row's exact height and no sibling moves. VoiceOver
  announces name, then categories, then notes through the name control's
  label.
- Start: bordered `L10n.timerStart` (the ordinary Start string — there is
  no separate Track completion control), `PlannerStart-<id>`. Hidden for
  completed rows. While the task carries the active linked run the slot
  shows the localized `In progress` label in the accent color
  (`L10n.plannerInProgress`, `PlannerInProgress-<id>`) instead — same
  footprint, no Start button. A visible Start under an active run renders
  dimmed but stays tappable: the tap shows a short red error in the row
  (`L10n.plannerBlockedStart`, `PlannerBlockedStartError` — wrapping,
  never truncated), shakes it, and plays the reject haptic instead of
  starting (a truly disabled control would swallow the tap).
- Swipes (Mail-style icon+text pills): trailing-side Delete
  (`L10n.entryDeleteConfirm`, `trash`, danger tint, full-swipe deletes)
  into the durable undo buffer (no outbox row yet) — never for the
  running task (no trailing swipe button, handler skips the linked id);
  leading-side
  complete/reopen (`L10n.plannerMarkDone` / `L10n.plannerReopen`,
  `checkmark` / `arrow.uturn.backward`, accent tint) with the toggle
  semantics — position kept, timers and entries untouched. There is
  no Edit button and no edit-mode deletion UI anywhere on this page.
  Shake-to-undo is unchanged: shake restores through the DEFAULT system
  Undo confirmation (entry/category precedent,
  `L10n.entryDeleteConfirm` action name).
- Reorder: the list's `onMove` in visible coordinates through the dedicated
  reorder control (`L10n.plannerReorder`, `arrow.up.arrow.down` while idle
  and `checkmark` while active, `PlannerReorderButton`) — no delete
  affordances appear in reorder mode (the list carries no `.onDelete`, so
  only drag handles surface). The VoiceOver rotor reorder path is included,
  never drag-only. Moves allocate a key between the new visible neighbors
  — no other row is rewritten — and respect Reduce Motion (no
  explicit animations anywhere on this page).

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
- [x] The editor sheet is the manual entry form minus Start/End (the
  shared Name entry card into `NamePicker`, same Categories card, same
  Notes presenter, same order/cards/validation/save gate) and edits the
  name, the ordered category set, and the notes as independent field
  intents; invalid and over-limit saves keep the sheet open with the
  draft intact. Chips stage their Recent's full set for the created task
  (selected-only display until typing resumes; survives typing until
  draft clear or retap); Track-side convergence posts refresh the
  planner in place and sheet saves refresh Track in place.
- [x] Start uses the task's categories when non-empty, else exact-text
  Recents inheritance, and copies the task notes into the draft;
  persists the task id via the claim-guarded draft, and pops to Track;
  a second Start returns false with no replacement. While linked, Track
  retag/notes edits write through to the task and sheet saves on the
  running task write through to the draft, each in the same chokepoint
  transaction (locked name untouched); pending-notes review, retry,
  backdate, and Live Activity Stop paths are preserved.
- [x] Rows show ordered category chips under the name with the notes
  indicator trailing them (VoiceOver announces name, then categories,
  then notes) and read the accent-colored localized `In progress` label
  over the preserved Start slot while the task carries the run; a Start
  tapped while any run is active shows the row's inline red error
  (`L10n.plannerBlockedStart`, shaking + reject haptic) instead of
  starting — the nav bar carries no timer-running subtitle at all. Open,
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
- [x] The isolated staged chip renders in the filled-accent selected
  presentation (Track Recents parity: accent fill, on-accent content,
  `.isSelected` trait), pinned via `isSelectedChip`.
- [x] Completed taps never open the editor (`beginEdit` no-op); the
  running linked task offers no row delete affordance (no trailing swipe
  button, handler skips the linked id), and there is no Edit button and no
  edit-mode deletion UI anywhere — reordering runs through the
  dedicated reorder control (`PlannerReorderButton`) with `onMove` handles
  only.
- [x] Valid submits play the success haptic and chip taps the selection
  haptic through the injected `playHaptic` seam (test double; generators
  never fire headless).
- [x] The page title is `My Day` (all five locales + `L10n`); the composer
  carries a persistent leading plus with the contrasting `FieldCard`
  hairline border in both appearances.
- [x] The editor sheet shows the `In progress` subheader for the running
  task and offers the shared red destructive `Delete` (entry-form parity);
  the running task's Name is read-only (locked label) while its
  Categories and Notes stay editable, and its delete shows an explicit
  red error with shake + reject haptic on tap, durable undo otherwise
  (pinned via `isEditingRunningTask` / `attemptDeleteEditingTask` /
  `deleteBlockedMessage`).
- [x] The composer row offers an editing-only detached circular ×
  keyboard-dismiss control beside the card (Mail search-clear grammar)
  and Return on an empty draft dismisses (the only submit-path resign
  allowed); valid submits never resign (pinned via
  `shouldResignOnReturn` / `ComposerDismissVisibility`).
- [x] Tapping a Start while a run is active shows the row's inline red
  error (`L10n.plannerBlockedStart`, shaking + reject haptic) instead of
  starting — no nav-bar subtitle, `planner.outsideRun` removed (pinned
  via `blockedStartTaskID` / `startShouldReject` /
  `rejectDisabledStart(for:)`).
