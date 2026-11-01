## 1. Apply-time gates

- [x] 1.1 Rebase this worktree on fresh `origin/main` after PR #231 merges; re-check the `app-shell` and `history-entry-list` deltas against the merged baselines (requirement names may have moved) and resolve conflicts by folding into #231's merged names. (Done: rebased onto `origin/main` @ `7da2ac6c`; all five delta requirement names match the merged baselines verbatim — no conflicts, no folding needed.)
- [x] 1.2 Reconfirm the design D4 ctx7 waiver (removal-only scope unchanged) and record the fresh base commit in the tasks. (Done: scope is deletion/reword-only, no new library/framework/SDK/API behavior — waiver reconfirmed. Fresh base: `7da2ac6c`.)

## 2. Spec deltas and Design docs

- [x] 2.1 Sync the five delta files via archive; verify the two retired requirements disappear and the three renamed replacements land with all scenarios intact. (Done: deltas already written; re-verified names/scenarios against merged `7da2ac6c` baselines — all match, no edits needed. No archive run per 4.3.)
- [x] 2.2 Update `Design/SCREENS/History.md:83` checklist line to the renamed requirement; reword any `COMPONENTS.md` / `SCREENS/History.md` / `SCREENS/Insights.md` sentences that describe timer-free layout in negative terms. Leave class-B enumerations and class-C guards untouched. (Done: History.md lines 23/82/83/87/88 + Insights.md lines 20/35 reworded positively; COMPONENTS.md had no matches. AppShell.md/TimeTracking.md/DECISIONS.md negative lines left per proposal scope — reported in handoff.)
- [x] 2.3 Update `docs/project-context.md` only if it references the removed requirement names (check "Incomplete / deferred" and Track paragraphs); do not touch archives. (Done: checked — prose only, no removed requirement names cited; no change.)

## 3. Tests and code memorials

- [x] 3.1 Delete `ios/TimeOfLife/TimeOfLifeTests/TimerFreeShellCompositionTests.swift`; verify no other file references it and `Mirror(` is gone from the tree. (Done: only `Mirror(` use; zero remaining refs.)
- [x] 3.2 Rename `retiredCompactTimerSurface` to a neutral clearance name and `timerAbsentClearance` accordingly in `HistorySearchStates.swift`; drop the "No compact timer exists" comment in `HistoryView.swift` (keep layout values identical). (Done: `emptyStateSurface` = 62, `emptyStateClearance` = 70; values unchanged.)
- [x] 3.3 Reword `HistorySearchChromeTests` (`clearActionClearanceMatchesCompactTimer`, `== 62` pin) to assert clearance behavior positively against the renamed constant. (Done: `clearActionKeepsEmptyStateClearance`, same pins.)
- [x] 3.4 Fix the stale "compact timer's `refreshSignal`" doc reference in `EntryRefreshWiringTests.swift` header; change no test logic. (Done: header only.)

## 4. Verification and handoff

- [x] 4.1 Run `openspec validate remove-absence-contracts --strict` plus an in-memory merge check that the two retired requirements vanish and no scenario is lost. (Done: validate → "Change 'remove-absence-contracts' is valid"; scripted check: all REMOVED names present in baselines, all MODIFIED names in both, zero ADDED collisions, MODIFIED scenario lists identical; 3 renamed replacements keep every surviving scenario — 2 intentional D1 title renames verified body-identical modulo dropped absence tails.)
- [x] 4.2 Run affected iOS tests then the full `xcodebuild test` scheme on an available simulator per `docs/ios-test-loop.md`; run `swiftlint lint --strict` and the warning-as-error build. Backend suite unaffected but run `go test ./...` once for the S5 gate. (Done: affected HistorySearchChromeTests+EntryRefreshWiringTests green; full suite 1018 tests / 94 suites passed; swiftlint 0 violations / 235 files; build-for-testing EXIT=0; `go test ./...` all packages ok.)
- [x] 4.3 Re-check FURPS rows touching the edited requirements; confirm no behavior, API, or storage change (rollback = revert). Do not merge, tag, or archive without owner approval. (Done: only FURPS/Timetracking.md F16 touches the clearance prose — behavior (70pt clearance, values pinned) unchanged, no FURPS edit; production diff is 2 value-identical constant renames + 1 comment drop; nothing merged/tagged/archived.)
