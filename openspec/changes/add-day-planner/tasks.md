## 1. Research and contracts

- [x] 1.1 Reconfirm the ctx7 topic, HIG, iOS 18 SwiftUI, and PostgreSQL 15 research in `design.md` against the implementation base; record any revised evidence or waiver before coding.
- [x] 1.2 Define the OpenAPI planner operation and paginated feed schemas, retry/terminal-delete responses, validation, and shared position-key fixtures before wiring the relay and the iOS client.

## 2. Relay and persistence

- [x] 2.1 Add PostgreSQL/SQLite planner state, per-account revision allocation, deduplication receipts, deletion markers, indexes, and account purge coverage; verify additive deploy and rollback compatibility.
- [x] 2.2 Implement authenticated planner write and change-feed handlers. Add contract and dual-store tests for same-account isolation, independent fields, conflicting reorders, lost responses, delayed create after delete, purge, and a writer racing page boundaries.
- [x] 2.3 Add account-file migration, planner CRUD and durable undo via `LocalStore`, a shared Today/progress projection, and ordered position allocation. Test duplicate names, rollover without writes, completed-row filtering/position, date changes, and account rebinding.
- [x] 2.4 Integrate planner cursor/outbox/pull/drain in the iOS client with pending field intent overlays, terminal deletes, and graceful behavior against an older relay. Test resumed pulls, offline edits from two devices, Stop vs remote delete, and unaffected entry/category sync.

## 3. Track, Today, and timer

- [x] 3.1 Add the Track toolbar progress control and Today route without changing the tab shell or timer geometry. Implement the inline composer, capped filtered Recents, stable keyboard and scroll position, accessible row edits and reorder, Reduce Motion support, and five locale updates plus `L10n`.
- [x] 3.2 Persist a linked task ID on successful one-tap Start, inherit ordered categories as before, and reject a second Start at the store boundary. Test relaunch, deleted/completed task guards, and duplicate names.
- [x] 3.3 Complete the exact task atomically in the shared Stop path without changing entry, notes-review, retry, or Live Activity behavior. Test success, rollback, replay after reopen, overnight/backdated Stop, task edits/deletion mid-run, and ordinary Stop.

## 4. Verification and documentation

- [ ] 4.1 Exercise repeated Return with software/hardware keyboards, stable layout on compact screens and large Dynamic Type, VoiceOver reorder, and unchanged Start/Stop frames. Record cold-open Live Activity Stop acceptance from the Island/banner on a supported device.
- [ ] 4.2 Update the relevant FURPS rows, `Design/README.md`, `Design/SCREENS/`, interaction/decision docs as applicable, `docs/project-context.md`, `README.md`, and the manual testing guidance; reconcile the shipped OpenAPI contract.
- [ ] 4.3 Run backend format, vet, lint, build and full tests plus iOS project generation, strict lint, warning-free build and full simulator tests, in parallel on separate agents. Re-run affected checks after rebasing and run `openspec validate --all --strict`.
