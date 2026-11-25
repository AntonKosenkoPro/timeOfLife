## Why

Lifio can tell users what they tracked, but they have to keep today's priorities somewhere else. [Issue #254](https://github.com/AntonKosenkoPro/timeOfLife/issues/254) brings a short, ordered checklist into Track's workflow without turning the timer screen into a task manager.

## What Changes

- Add a dedicated Today planner reachable from a compact progress control on Track. Keep the three tabs and the existing Start/Stop presentation.
- Let users add, rename, reorder, complete, reopen, and delete name-only tasks. Return appends and keeps the keyboard open; matching Recents fill the input without submitting it.
- Show unfinished tasks automatically on every subsequent day until completed or deleted. Completed tasks stay in position through their completion day. There is no tomorrow view, manual rollover, or midnight write.
- Start an open task in one tap when the device has no active timer. A successful Stop from Track or its Live Activity saves time and completes that exact task; ordinary timers are unchanged. Defer a separate Track completion control.
- Make planner tasks account-bound, usable offline, and synced between devices without making them History entries, categories, or synced timer drafts.
- **Non-goals:** estimates, subtasks, recurrence, task details beyond a name, planning other dates, integrations, and cross-device ownership of a running timer.

## Capabilities

### New Capabilities

- `day-planner`: Today projection, task management, fast input, progress, and the planner-to-timer workflow.

### Modified Capabilities

- `timer-capture-experience`: Track progress/entry point and unchanged Start/Stop presentation for linked runs.
- `live-activities`: the existing Stop route completes a linked task with the saved entry.
- `local-first-store`: independent planner persistence and an atomic linked Stop.
- `sync-client`: per-task synchronization, ordering, and delete-wins behavior.

## Impact

- iOS: Track navigation and layout, planner UI, all five locales and `L10n`, account database, timer draft, and sync client.
- Backend: additive PostgreSQL/SQLite storage, account-scoped planner routes and deletion propagation; `backend/api/openapi.yaml` stays authoritative. No changes to the entry API shape.
- Implementation updates the relevant FURPS rows, Track/planner design, project context, and manual testing guidance. External research and version pins are recorded in `design.md`.
