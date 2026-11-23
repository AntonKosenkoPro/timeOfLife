## Context

See `proposal.md` for motivation and scope. Track already separates name selection from Start. Its toolbar is composed in `Features/AppShell/Views/AppShellView.swift`; `ShellToolbar` currently shows Profile on Track. `TrackContent` owns a carefully budgeted timer/Recents/category layout that this change does not alter.

`TrackViewModel.syncReadyFromDraft()` inherits exact-name categories. `select(_:)` carries Recents categories. Neither is suitable for Stage 1 planner selection. `start()` already preserves a matching prepared `.ready` draft, so a dedicated text-only selection can use that existing boundary.

The active account owns one database file. All mutations pass through `Core/Storage/LocalStore.swift`; database suspension, account changes, and deletion must retain their existing guarantees. The completed `preserve-running-notes-on-live-stop` change owns Stop/review serialization: the planner must not change that pipeline or attach itself to stop receipts.

## Goals / Non-Goals

**Goals:** Keep planning off Track's layout and launch critical path; make planner state durable but device-local; make name selection incapable of starting/switching timing or inheriting metadata; complete the matching task on Stop under a narrow exact-text rule; define daily cleanup without depending on background execution.

**Non-Goals:** No changes to sync, timer persistence, entry shapes, Stop entry-save/review serialization, undo supersession for entries/categories, or the widget extension. No speculative order/category fields for Stage 2.

## Decisions

### 1. A lazily loaded sheet, not an inline Track list

Add a checklist-symbol button immediately before Profile in the Track-root trailing toolbar, with a localized accessibility label. Present a sheet containing its own lightweight planner view model. Keep the existing shell tab/navigation paths and Track layout unchanged; do not add a pushed planner route or extend `TrackSnapshot`.

Use a system sheet with medium/large detents on iPhone, a visible grabber, a title such as “Today's tasks,” and a trailing Done action. Let the system adapt on iPad and in compact height. A scrollable list has no Recents-derived 12-item cap. Opening for browsing does not focus the keyboard. A plain add field and explicit Add action allow repeated additions; successful Add clears the field and keeps keyboard focus for the next task, failures preserve both text and focus. Only explicit Done or system dismissal dismisses the keyboard. Opening for browsing does not focus the keyboard. Use native keyboard dismissal and expand as needed for editing/large text. Swipe dismissal discards only unsubmitted field text; committed task changes are already saved.

Rows retain creation order, including checked rows, to avoid moving a checkbox target during interaction. A checkbox toggles completion; the separate text button selects the name. Completed rows remain selectable when timing is stopped. Keep checkbox and selection accessibility actions distinct.

Alternative: inline planner/Recents sections require new height budgets and scrolling contracts. Rejected by the owner's sheet decision. A pushed editor would add needless navigation for a short checklist.

### 2. A separate account-local task table

Add an additive migration in `LocalStore.migrator()` for `planner_tasks`: independent UUID identity, normalized `text`, `created_at`, and nullable `completed_at`. Completion is derived from the timestamp; there is no redundant done flag, task-to-entry reference, planned date, category list, or manual-order column. Sort by `created_at ASC, id ASC`; allow identical names as distinct tasks.

Reuse `ActivityName` normalization/validation (trimmed non-empty text, at most 60 characters), not an entry/Recents model. Provide LocalStore operations for loading/pruning, adding, toggling completion, and removing. Group cleanup plus the relevant read/mutation in the existing transaction primitive where consistency requires it. These operations never create outbox rows, sync cursors, tombstones, or undo-buffer snapshots.

Ordinary sign-out keeps planner rows with their dormant account file. Both `eraseAll()` and `eraseAccount(userID:)` remove the whole account file and its sidecars, so they already cover the new table; verify this with tests rather than adding a redundant per-table erase path. The sheet must close and clear its state on account loss/change. Capture the expected account identity, validate it inside each serialized LocalStore operation before choosing the active database, and reject stale operations; also discard stale UI completions. Do not rely on a pre-await UI identity check alone.

Alternative: a second file/UserDefaults store complicates account isolation and erasure. Syncing a new resource is expressly deferred. A position column buys no current behavior; add a migration when Stage 2 needs ordering.

### 3. Text-only preparation with no task-to-timer link

Introduce a small synchronous MainActor planner-selection operation alongside the existing selection methods. Recheck running/saving/account/presentation validity at execution time, then prepare the exact normalized name with empty categories and notes. On success dismiss the sheet. Never call `syncReadyFromDraft()` to select the task: that would accidentally ship category prefill. Preserve the existing `start()` matching-draft behavior.

Disable only task-name selection while running/saving; allow add/check/uncheck/removal during a run. Disable all task actions while their required load/write is unresolved or the account/store is unavailable; serialize writes to avoid duplicate taps. Follow the existing Recents behavior for a settled saved-confirmation state. Do not steal a pending notes-review presentation or alter its continuation.

Starting a run never checks a task. Stopping a run completes at most the oldest unfinished task whose normalized text exactly equals the stopped run's text (timestamped with the stop); Stop with no unfinished exact-text match changes no task and still saves its entry through the unchanged Stop receipt path. Removing, checking, or overnight-pruning a task never modifies a prepared name, running draft, saved entry, or Live Activity. There is no inferred link by matching text except this single Stop-completes-match rule.

Alternative: reusing Recents selection leaks categories; queue-next/stop-and-switch adds a new timer state machine. Both are outside Stage 1. Completing all duplicates per Stop was rejected (one-by-one preserves user control); completing only planner-started runs was rejected (manual entry of the same name should still close the loop).

### 4. “Overnight” means an idempotent local-day cutoff

Inject `now` and the device-local calendar/time zone for deterministic tests. At each reconciliation compute the start of the current local day and delete only rows with non-null `completed_at` strictly earlier than that boundary. Unfinished rows never expire. Unchecking clears `completed_at`; checking again records a new completion time.

Reconcile on planner open, on active-account foreground/resume after the database is resumed, and at a local-day change while the sheet is open and active. Re-evaluate after system clock/time-zone changes; use the calendar's next day boundary, not a fixed 24-hour interval. App suspension may defer physical cleanup until the next safe opportunity. A suspended/failed write never publishes successful cleanup; keep the last successful snapshot with a retry path and retry after resume. This is a small foreground lifecycle hook, not an extension writer or new background task.

Use the device's current local boundary at reconciliation; travel can advance or delay eligibility. A clock change never restores already deleted completed rows. A completed task exactly at today's boundary is retained. After multiple inactive days, one reconciliation removes all eligible completed rows. No archive, cleanup watermark, per-day task buckets, or background midnight guarantee is needed.

Alternative: scheduled background cleanup cannot guarantee midnight execution. Date-partitioned lists conflict with carry-forward simplicity and introduce an unrequested archive.

### 5. Minimal removal, independent of time-entry Undo

Provide a per-task Remove action with one destructive confirmation naming the task verbatim with proper locale quotes and no escape sequences; visual truncation for layout keeps the full name in the accessibility label. Cancel makes no changes. Successful removal is permanent locally, with no relay operation or shared undo-buffer participation. This avoids new cross-resource supersession semantics for an unsynced checklist; document the distinction in the sheet/design and preserve entry/category Undo unchanged. Renaming/editing tasks is deferred; remove and add corrects text in Stage 1.

This is a proposal default for human review, alongside creation order and duplicate allowance. Completion itself is immediately reversible by unchecking before overnight cleanup.

### 6. Existing accessibility, localization, and failure grammar

Use `Theme`, the established 44pt minimum targets, Dynamic Type layouts, non-color completion feedback, stable per-ID automation identifiers, and VoiceOver names/state/actions. All new labels, validation, loading, confirmation, and error copy go through `L10n` and all five locales.

Load lazily with a loading/empty/error distinction. Await durable writes before displaying success (or roll back any optimistic update); keep the sheet open with retryable feedback on failure. A failed name-selection guard does not dismiss as if selection succeeded. Do not log task text or add task analytics.

## Research and applicability

Fetched 2026-11-20 through `npx ctx7@latest library` then `docs`; HIG/SwiftUI lookups were performed during the preceding explore, GRDB during propose. Re-confirm applicability at apply time. Platform target: iOS 18 SDK via Xcode 16+; indexed Apple docs are current, not a versioned SDK snapshot.

| Bundle item | Context7 ID and exact docs query | Constraint / source |
|---|---|---|
| Topic: distinguish row selection from completion | `/websites/developer_apple_design_human-interface-guidelines` — `Lists and tables on iOS: row selection, inline editing, swipe actions and accessory buttons` | Keep rows scannable and give selection/state feedback. [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables). |
| HIG: sheet presentation | `/websites/developer_apple_design_human-interface-guidelines` — `Sheets on iPhone and iPad: half-height expandable sheets, dismiss controls, and keyboard entry` | Support medium/large disclosure and swipe dismissal; explicit trailing Done. [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets). |
| Apple API | `/websites/developer_apple_swiftui` — `iOS 18 SDK via Xcode 16+: sheet presentationDetents medium large and presentationContentInteraction scroll for editable lists` | Native detents and content gestures; default upward scrolling expands before scrolling. Do not add custom gesture interception. [presentationDetents](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)), [presentationContentInteraction](https://developer.apple.com/documentation/swiftui/view/presentationcontentinteraction(_:)). |
| Persistence best practice | `/groue/grdb.swift` — `DatabaseQueue write operations run in a transaction and roll back together on error, for inserting and pruning local checklist records` | Atomicity/rollback within `write`; existing LocalStore owns the boundary. [DatabaseQueue](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Extension/DatabaseQueue.md). Query used current indexed docs; verify against the repo-resolved GRDB version before coding. |

No cloud/service setup research is applicable: there is no backend, network, dependency, entitlement, or deployment addition. No ActivityKit research is applicable: planning never changes Live Activities. Calendar policy is product logic with injected clock/calendar; confirm any new Foundation notification/lifecycle API against current docs during apply before using it.

## Risks / Trade-offs

- [Local-only data is not restored by relay sync] → State this in planner/account documentation; retain ordinary sign-out data, but explicit local deletion permanently removes tasks.
- [Day change or travel surprises] → Specify current-device cutoff, no task archive, no background promise; test DST, offsets, midnight, and multi-day absence.
- [Stale sheet writes cross an account switch] → Store-level expected-account checks plus UI generation invalidation; test switches during pending operations.
- [Cleanup while suspended] → Use existing suspension errors/resume retry; never wake or resume the database merely for the planner.
- [Category inheritance or Stop/review regression] → Dedicated preparation path and exact-name-with-existing-categories regression; Stop entry-save/review serialization unchanged, planner completion attached as a narrow post-save side effect with oldest-match tests; no Stop-pipeline changes or task linkage beyond this rule.
- [Removal confirmation misrendering] → Interpolate the task name through localized format strings (no manual `\u` escapes); regression-test quotes/emoji/long names in all five locales with layout truncation plus full-name accessibility labels.
- [Plain removal has no shared shake Undo] → Confirm it explicitly and document the planner exception; leave existing entry/category Undo behavior unchanged.

## Migration Plan

1. After human proposal approval, rebase and re-confirm research, then add the local table and tests through the normal XcodeGen-managed app workflow.
2. Existing account files migrate additively on safe open; fresh accounts get an empty checklist. No seeding, entry backfill, network bootstrap, or legacy Codable branch.
3. Older app builds can ignore the additive table; do not promise application downgrade compatibility without testing the repository's migration checks. No backend rollback or schema change is involved; do not delete account files as a rollback workaround.
4. Verify account-local erase helpers and privacy copy. Future sync/reorder/category support needs a separate change and migration; no speculative fields now.
