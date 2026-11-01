## Context

See `proposal.md` for motivation. Planning base is `origin/main` @ `6eae0ed5` (PR #227 merged). PR #231 (`remove-entry-integrations`) is open as a draft against the same baselines (`app-shell`, `history-entry-list`); this change must be implemented on a fresh rebase after #231 merges, and its `app-shell`/`history-entry-list` deltas re-checked for requirement-name conflicts at that point.

## Goals / Non-Goals

**Goals:**
- Delete absence contracts while preserving every positive behavior they shadowed (refresh-on-return, nav-bar persistence, glass/inset layout, save/reconcile).
- Replace reflection-based absence tests with behavioral equivalents or delete them where behavior is already covered.
- Neutralize code memorials without changing layout values.

**Non-Goals:**
- No behavior change, no API change, no migration, no new tests for new behavior.
- Not touching class-B enumerations (insights judging-language ban, search capability exclusions, category delete affordance) or class-C load-bearing guards — recorded as deliberate non-goals in the proposal.
- Not trimming the negative requirements in the unmerged #231 deltas — that trim is a separate in-review edit owned by PR #231, not this change.

## Decisions

### D1. REMOVED + renamed ADDED instead of editing in place
Two requirements lose scenarios ("Compact timer on History", "Final row reachable with and without the compact timer") and one loses an admitted no-op scenario. The OpenSpec validator/archive treats a MODIFIED block as replacing the whole block, so dropping scenarios from MODIFIED fails validation. The established pattern (used in `remove-entry-integrations` for the LOCKED-mode requirements) is REMOVED with Reason/Migration plus a renamed ADDED replacement carrying the full surviving contract. Renames chosen: "Final row clears the tab bar", "History nav bar stays visible", "Stop saves with stable local feedback".

Alternative rejected: keeping the old scenario titles with neutralized bodies — leaves the giraffe reference in the contract's table of contents.

### D2. Delete the Mirror test outright; keep EntryRefreshWiringTests
`TimerFreeShellCompositionTests` asserts stored-property names via reflection — white-box, breaks on any future property whose name merely contains `refreshSignal`/`runningTimer`/`service`, and proves nothing about rendering. The behaviors it shadows (History/Insights show committed data; shell owns navigation state) are covered positively by `EntryRefreshWiringTests` (544 lines, event-driven refresh contract) and `AppShellViewModelTests`. Only the stale "compact timer's `refreshSignal`" doc comment in `EntryRefreshWiringTests` is fixed.

Alternative rejected: rewriting the Mirror test against behavioral probes — that duplicates `EntryRefreshWiringTests` coverage for no gain.

### D3. Rename, don't remove, the clearance constant
`retiredCompactTimerSurface = 62` encodes a real layout value (clearance for the History empty-state clear action) also pinned by `HistorySearchChromeTests`. The value stays; only the memorial name goes (`emptyStateClearance`), with the test reworded to assert clearance behavior positively. Zero layout change, so no snapshot updates.

### D4. Research and policy basis
Context7: waived in full — pure deletion of already-merged contracts; no new library, framework, SDK, API, or service behavior. No HIG lookup (no UI or interaction grammar changes — faces, gestures, and navigation are untouched), no Apple-API lookup (no ActivityKit or framework change), no best-practice lookup (no new pattern introduced; the change deletes one). Reconfirm the waiver at apply time if scope grows beyond removal. Pre-release local-format policy is unaffected (no store changes). This is cleanup, not a bugfix: no repro involved; the regression baseline is the current green suites plus `openspec validate --strict`.

## Risks / Trade-offs

- [Requirement renames break unknown references] → Grep shows one Design checklist line (`SCREENS/History.md:83`) referencing an old name; tasks update it. Archive proposals referencing old names are history and stay.
- [Deleting the no-op scenario loses "continuity"] → The scenario's own text admits it exists only for archive continuity; archives are immutable history and unaffected.
- [#231 merges first and renames the same requirements] → Apply-time rebase + delta re-check is a gating task; on conflict, prefer #231's merged requirement names and fold this change's edits into them.
- [Mirror-test deletion hides a real regression] → Mitigated by D2: every behavior the Mirror test shadowed has a named positive test that fails on regression.

## Migration Plan

1. Rebase on fresh `origin/main` after PR #231 merges; re-check `app-shell`/`history-entry-list` deltas against the merged baselines.
2. Apply spec deltas, test/code edits, and doc updates together; run `openspec validate --strict`.
3. Run affected suites then full suites (`go test ./...` is unaffected but run for the gate; `xcodebuild test` full scheme).
4. No rollout concerns: no behavior, API, or storage change. No rollback plan beyond revert.
