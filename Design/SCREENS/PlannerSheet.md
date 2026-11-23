# Planner Sheet

The Stage 1 day-planner (day-planner spec, `add-track-planner` change): a
separate resizable bottom sheet opened from the Track root toolbar. Users keep
a lightweight account-local checklist for the day and tap a task's name to
prepare it as the Track name — without recording time, inheriting
categories, or changing the running timer.

## Use case

1. The user taps the checklist button in the Track toolbar (present only on
   the Track root, beside Profile; disabled until the account's Track state
   is ready).
2. The sheet opens (medium/large detents, grabber, `Today's tasks` title,
   trailing Done) and lazily loads the account's checklist — no planner
   reads ride the launch-gate `TrackSnapshot`.
3. The user adds plain-text tasks (explicit Add; duplicates allowed as
   independent rows), checks/unchecks them manually, and removes them with
   one destructive confirmation naming the task.
4. The user taps a task's name: the sheet dismisses and Track holds the exact
   normalized text with **empty** categories and notes. Start stays a
   separate explicit action — nothing starts, switches, or queues timing.
5. Checklist management (add/check/uncheck/remove) stays available while a
   timer runs; only name selection locks during running/saving/error states.
6. Unfinished tasks carry forward. Prior-day completed tasks disappear at the
   next open, foreground/resume, or local-day change while the sheet is
   open. No background wake-up is promised and no archive exists.

## Screen: PlannerSheet

- **File**: `ios/TimeOfLife/TimeOfLife/Features/TimeTracking/Views/PlannerSheet.swift`
- **Route**: `.sheet` from the Track root only (no pushed route, no tab, no
  History/Insights entry point)
- **ViewModels**: `PlannerViewModel` (sheet-owned, `@StateObject`, created on
  open) + the owning tab's `TrackViewModel` (observed, for selection guards
  and preparation)

### Layout

- `NavigationStack` with `.inline` title (`L10n.plannerTitle`), trailing
  Done (`L10n.plannerDone`, `PlannerDoneButton`), system swipe dismissal.
  Swipe dismissal discards only unsubmitted field text; committed task
  changes are already saved.
- `.presentationDetents([.medium, .large])` on iPhone with a visible drag
  indicator; the system adapts on iPad and in compact height.
- Add row (pinned above the list): plain `TextField`
  (`L10n.plannerAddPlaceholder`, `PlannerAddField`) + explicit Add button
  (`L10n.plannerAddButton`, `PlannerAddButton`). Opening for browsing does
  not focus the keyboard. Successful Add clears the field; failed Add
  preserves the input with an accessible explanation. Native keyboard
  dismissal; the content expands for editing/large text.
- Checklist (`List(.plain)`, `PlannerTaskList`, no Recents-derived item
  cap): one `ChecklistRow` per task (see `COMPONENTS.md`), creation order
  including checked rows.
- States: loading spinner (`PlannerLoadingIndicator`) on first open;
  populated list; empty state (`PlannerEmptyTitle`/`PlannerEmptySubtitle`);
  load-failure message with `Try Again` (`PlannerLoadErrorMessage`/
  `PlannerRetryButton`). Failure never presents a cleared list as success;
  the sheet stays open for retry with the last snapshot intact.

### Reconciliation triggers (foreground-only)

- `open()` on every sheet open (captures the bound account, bumps the
  generation, prunes + loads atomically).
- `reconcileActive()` on `DatabaseSuspension.didResumeNotification`
  (foreground/resume implies access is safe again), on
  `.NSCalendarDayChanged`, and on `.NSSystemTimeZoneDidChange` — only while
  the sheet is open and active. No background task, no hidden-sheet midnight
  timer, no extension writer.
- Uses the device's current local day boundary at execution time
  (`PlannerDayCutoff`); unfinished rows never expire; completion exactly at
  today's start is retained (strict `<`).

### Selection contract (text-only)

- The sheet rechecks running/saving state AND the bound account immediately
  before preparing: a stale sheet never overwrites another account's name.
- `TrackViewModel.selectPlannerTask(_:)` fills the exact normalized text
  with empty categories/notes and returns success; the sheet dismisses only
  on success. Never calls `syncReadyFromDraft` (that would inherit the exact
  recents match's categories). No timer/entry writes before Start; no
  completion linkage on Start/Stop; the pending notes-review session is never
  stolen or altered.

### Removal contract (outside shared Undo)

- Per-task Remove (swipe action + context menu, never full-swipe) stages
  `pendingRemoval`; one destructive confirmation (`L10n.plannerRemoveTitle`)
  names the task text (`String(format: plannerRemoveMessage, text)`);
  Cancel preserves it. Confirmed removal is permanent-local: no relay
  operation, no outbox row, no entry/category undo-buffer participation.
  Document the distinction wherever removal copy appears.

### Implementation checklist

- [x] All colors use `Theme.*` tokens; no raw `Color` literals.
- [x] All strings use `L10n.planner.*` keys in all five locales (`en`, `ru`,
  `zh-Hans`, `es-419`, `pt-BR`).
- [x] 44 pt minimum targets on checkbox, text, Add, Done, retry; Dynamic
  Type layouts; completion is struck-through text + announced state, never
  color-only.
- [x] Checkbox and name-selection are independent VoiceOver actions with
  independent state; stable per-task identifiers
  (`PlannerTaskToggle_<id>`, `PlannerTaskSelect_<id>`,
  `PlannerTaskRemove_<id>`).
- [x] No Track layout changes; no `TrackSnapshot` planner reads; no pushed
  route; no History/Insights entry point.
- [x] Selection disabled while running/saving/error; management usable while
  running; no category prefill, suggestions, reorder, queued-next, or
  completion linkage.
- [x] Local-day cleanup is injectable-calendar/idempotent; suspension keeps
  the last snapshot with retry; account switches fence at the store
  (`expectedUserID`) and VM generation levels.
- [x] SwiftLint and warning-as-error builds pass.
