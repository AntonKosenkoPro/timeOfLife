## Why

Users forget to start the timer. Today the only way to record time is the live Track timer, so a forgotten session is unrecoverable and the data is lost. A manual "log past time" path — pick an activity, set start/end, save — closes that gap, as anticipated by `docs/history-roadmap.md` §4 ("Manual entry addition").

## What Changes

- New **Log Time sheet** styled on the iOS Calendar add-event form, trimmed to three rows: **Activity** (= Calendar's "Calendar" row), **Starts**, **Ends**. Cancel/Add in the nav bar; Add is a validity gate (disabled until an activity is chosen and end > start).
- **Two entry points** sharing one sheet: a `[+]` button in the History toolbar, and a `Log time` action on the activity detail sheet (pre-fills the activity).
- **Activity picking** reuses Track's searchable sheet with quick-create (normalized-name collision rule); an empty catalog routes straight to quick-create with no dead end.
- **Starts/Ends rows** use date + time pills with inline expanding pickers (graphical month grid for dates, wheels for times, one open at a time); the active pill is tinted. Moving Start past End auto-pushes End to preserve duration (Calendar behavior).
- **Defaults on open**: Start = now floored to 5 minutes, End = Start + 1h.
- **Persistence** reuses `LocalStore.createEntry` with `source:"manual"` (+ transactional outbox, `last_used_at` recency bump); overlaps and future end-times are allowed, matching current store semantics. Create-only: no entry editing or deletion.
- Localized in EN + RU (`L10n`), `Theme` semantic colors only.

## Capabilities

### New Capabilities

- `manual-entry`: manual time-logging sheet — entry points, Activity/Starts/Ends rows, inline pickers, validation gate, defaults, duration preservation, quick-create, persistence via `createEntry`.

### Modified Capabilities

- `history-entry-list`: the History toolbar gains a `[+]` action opening the Log Time sheet; the persistent-nav-bar requirement extends to it.
- `activity-detail-sheet`: the sheet gains a `Log time` action opening the Log Time sheet pre-filled with the activity.

## Impact

- iOS app only (`Features/TimeTracking` or new `Features/ManualEntry`, `AppShell` History toolbar, `ActivityDetail` sheet). No database migration, no OpenAPI change, no backend change — `createEntry`, outbox drain, and sync already cover `manual` entries.
- New `L10n` strings (EN + RU), new SwiftTesting coverage for the sheet view-model (validation, defaults, duration preservation).
- `docs/history-roadmap.md` §4 resolves to this change; entry edit/delete stay deferred.

### Non-goals

- Entry editing, deletion, or an EntryDetail surface (remain deferred per `docs/history-roadmap.md`).
- Overlap/conflict policy, future-entry restrictions, all-day entries.
- Filtering, activity-detail entry-count scope choice, lock-screen Controls.
