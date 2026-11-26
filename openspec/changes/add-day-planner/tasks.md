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

- [x] 4.1 Exercise repeated Return with software/hardware keyboards, stable layout on compact screens and large Dynamic Type, VoiceOver reorder, and unchanged Start/Stop frames. Record cold-open Live Activity Stop acceptance from the Island/banner on a supported device.
- [x] 4.2 Update the relevant FURPS rows, `Design/README.md`, `Design/SCREENS/`, interaction/decision docs as applicable, `docs/project-context.md`, `README.md`, and the manual testing guidance; reconcile the shipped OpenAPI contract.
- [x] 4.3 Run backend format, vet, lint, build and full tests plus iOS project generation, strict lint, warning-free build and full simulator tests, in parallel on separate agents. Re-run affected checks after rebasing and run `openspec validate --all --strict`.

## 5. Device-feedback fixes

- [x] 5.1 Render the `checklist` system symbol beside the Track progress count; verify in all five locales, Dynamic Type, and VoiceOver.
- [x] 5.2 Retain composer focus across the submit round-trip (store write, snapshot reload, suggestions mount/unmount); add a regression test that fails when focus is lost and re-verify repeated Return with software/hardware keyboards.
- [x] 5.3 Preserve the Start affordance slot so completed and open rows share one exact height; add a regression test that toggling completion moves no sibling row.
- [x] 5.4 Move suggestions into the task list surface as a top section (no separate mounting region), with match highlight and stable composer frame; re-check Reduce Motion and VoiceOver ordering.
- [x] 5.5 Run `swiftlint lint --strict`, warning-free build, full simulator suite, and `openspec validate --all --strict` green.

## 6. Second device-feedback round

- [x] 6.1 Keep the keyboard and composer focus perfectly still across submit (no resign/reopen cycle of any duration); diagnose the actual first-responder resignation, fix, add a regression test that fails on any resign flicker, and re-verify repeated Return.
- [x] 6.2 Add localized `Suggestions` and `Tasks` section headers (Mail-style split) in all five locales + `L10n`; the `Tasks` header persists whenever the list is shown; re-check VoiceOver ordering and Reduce Motion.
- [ ] 6.3 Run `swiftlint lint --strict`, warning-free build, full simulator suite, and `openspec validate --all --strict` green (all green in-sim); rebuild Release, reinstall on the device, and verify still keyboard/focus plus headers — DEVICE BLOCKED 2026-11-25: Tony's iPhone 17 (UDID 00008150-0019185901E3401C) `unavailable`, last seen 21:43; Release device build is warning-free and ready to install on next unlock.

## 7. Prevent the Return resign

- [x] 7.1 Replace the composer with a UIKit-backed field that submits on Return while declining the default resign; keep Theme styling, VoiceOver, and all existing composer behaviors; add a regression test proving no keyboard-hide/first-responder loss across submit at any round-trip latency.
- [x] 7.2 Run `swiftlint lint --strict`, warning-free build, full simulator suite, and `openspec validate --all --strict` green; rebuild Release, reinstall on the device, and verify the keyboard stays perfectly still. DEVICE VERIFIED 2026-11-26: iPhone 17 (00008150-0019185901E3401C) — Release installed, relaunched, keyboard perfectly still across two repeated Return submits (3 consecutive keyboard-present samples each), Suggestions + Tasks headers both present, probe rows removed afterwards; full sim suite 1220 tests green, lint strict clean, validate strict green.

## 8. New on top, chips above the keyboard

- [x] 8.1 Prepend new tasks before existing Today rows with an expanding insertion (opacity-only under Reduce Motion); add a regression test for top placement and the animation contract.
- [x] 8.2 Replace the suggestions section with a single horizontally scrollable chips line pinned just above the keyboard (visible only while the keyboard is open, filtered by typing, tap fills the composer); remove the now-unused `Suggestions` header string across all five locales + `L10n`; keep the persistent `Tasks` header; re-check VoiceOver ordering.
- [x] 8.3 Run `swiftlint lint --strict`, warning-free build, full simulator suite, and `openspec validate --all --strict` green; rebuild Release, reinstall on the device, and verify order, animation, and chips. DEVICE VERIFIED 2026-11-26: iPhone 17 (00008150-0019185901E3401C) — Release installed (first attempt hit locked-device 4016, retry after 45s succeeded), relaunched, process confirmed running, screenshot shows Today with the chips line above the open keyboard, persistent Tasks header, no Suggestions section; full sim suite 1337 tests green, Hold chips/stillness/order probe green on a fresh iPhone 16 sim, lint strict clean, validate strict green.

## 9. Bottom entry, immediate Track

- [x] 9.1 Move the composer to a bottom-fixed position with the list above and the chips line between composer and keyboard; append new tasks at the end with the expanding insertion; regression tests for placement and end order. DONE 2026-11-26 (sim): `submit()` allocates after the last Today row (prepend path removed; `decrement` stays for move-to-top), `PlannerView` stacks list → caption → composer → chips, Hold probe asserts newest-at-end + composer-below-list, `PlannerViewModelTests` pin end order; full suite 1219 green.
- [x] 9.2 Fix Track presenting a stale idle state after a planner-initiated Start. Repro (owner report 2026-11-26, recorded): Start from planner returns to Track looking unstarted until leaving and returning. FAILS-FIRST: `PlannerTrackHandoffTests.plannerStartShowsRunningImmediately` failed pre-fix (`Track still .idle immediately after a planner Start`, 1219-run with exactly 1 issue) and passes post-fix. Fix: `onStartActive` runs the shell's serialized `reloadTrack()` after popping the planner route, so the settled snapshot reloads and the run presents at once. Ordinary Start/Stop, notes review, retry, and Live Activity Stop paths untouched (full suite green). Research waived with evidence: repo-internal NavigationStack + snapshot coordination, no external library/API behavior — ctx7 N/A.
- [x] 9.3 Run `swiftlint lint --strict`, warning-free build, full simulator suite, and `openspec validate --all --strict` green; rebuild Release, reinstall on the device, and verify bottom entry, end order, chips, and immediate running Track. SIM GREEN 2026-11-26: lint strict clean (285 files), Debug warning-free, full suite 1219/1219 green, Hold keyboard/stillness/order/placement probe green on iPhone 16 sim (19.9s; Duo sim unusable — broken AX per probe docs), `openspec validate --all --strict` 34/34, Release device build warning-free and reinstalled. DEVICE BLOCKED: Tony's iPhone 17 (00008150-0019185901E3401C) locked — launch denied twice (immediate + 45s retry, FBSOpenApplicationErrorDomain Locked); install succeeded, relaunch + on-device finger verification left for the owner.
