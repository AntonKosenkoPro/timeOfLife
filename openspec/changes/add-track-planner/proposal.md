## Why

[Issue #254](https://github.com/AntonKosenkoPro/timeOfLife/issues/254) asks for a lightweight way to plan the day's work and select a task on Track. Stage 1 should remove repeated name entry without turning plans into recorded time or expanding the backend.

## What Changes

- Add a Track top-bar planner button opening a separate, resizable bottom sheet; leave the timer layout, Recents, and running category selector unchanged.
- Support plain-text task creation, manual check/uncheck, and confirmed removal. Task-text selection dismisses the sheet and prepares the Track name only; Start remains a separate action and categories are empty. Enter in the add field submits the task, clears the field, and keeps keyboard focus ready for the next task.
- Keep checklist management available during a run, but disable name selection while running or saving. Stopping a run completes the oldest unfinished task whose normalized text exactly equals the stopped run's name (one task per Stop); Start never changes completion.
- Keep checklist management available during a run, but disable name selection while running or saving.
- Carry unfinished tasks forward. Remove tasks completed before the current device-local day at the next active/open opportunity, and reconcile an open sheet when the day changes. Do not promise a background wake-up at midnight.
- Persist tasks in the active account's existing local database through `LocalStore`, without planner outbox rows, relay endpoints, or cross-device sync.
- Ship accessible controls and localized strings in all five supported locales.

### Non-goals

Stage 2 autocomplete from Recents, category prefill, and manual reordering are deferred. Also excluded: automatic timer start/switching, queued next tasks, completion on Start, task-to-entry links, scheduled dates/times, reminders, daily archives, a new tab, and Live Activity changes. Tasks are not activities or time entries. Stop-completion is narrowly included (oldest exact-text unfinished match only); no broader timing-to-checklist linkage is in scope.

## Capabilities

### New Capabilities

- `day-planner`: Account-local task checklist, bottom-sheet behavior, manual and Stop-triggered completion, carry-forward, overnight completed-task cleanup, Enter-to-add with retained focus, verbatim removal confirmation, and error/accessibility rules.

### Modified Capabilities

- `app-shell`: Add the planner entry point to the Track root toolbar without changing pushed navigation or other tabs.
- `timer-capture-experience`: Add explicit text-only planner selection with the existing separate Start gate and running/saving guards.
- `local-first-store`: Scope the transactional outbox to relayed category/entry mutations and explicitly exclude local-only planner mutations.

## Impact

- iOS: Track toolbar/presentation, a lazily loaded planner feature, a small prepared-draft selection path, and additive account-local storage migration/CRUD/cleanup.
- Preserve account isolation, database suspension handling, sign-out retention, and account-file deletion. No planner reads are added to the launch-gate `TrackSnapshot`.
- No backend, OpenAPI, sync protocol, new dependency, entitlement, or deployment change.
- Implementation must update `Design/COMPONENTS.md`, the planner/Track/AppShell screen documentation, relevant FURPS rows, `docs/project-context.md`, and the manual testing checklist. Baseline specs stay untouched during proposal.
- Proposal defaults: creation-order rows, duplicate text allowed with independent IDs, a plain add field with Enter-keeps-focus, Stop completes the oldest unfinished exact-text match (one per Stop; Start never completes), and confirmed local removal rendering the task name verbatim without joining the entry/category undo buffer. These are reviewable design choices, not new Stage 2 scope.

### Research

Research fetched on 2026-11-20; full queries, source links, applicability, and implementation re-confirmation are recorded in `design.md`.

- Topic/list actions + HIG: `/websites/developer_apple_design_human-interface-guidelines` — task-list row selection/controls, lists and tables, and resizable sheets.
- Apple API: `/websites/developer_apple_swiftui` — sheet detents and content interaction; target iOS 18 SDK via Xcode 16+ (current indexed docs, not a historical SDK snapshot).
- Persistence best practice: `/groue/grdb.swift` — atomic `DatabaseQueue.write` transactions; verify against the repository's resolved GRDB version before implementation.
