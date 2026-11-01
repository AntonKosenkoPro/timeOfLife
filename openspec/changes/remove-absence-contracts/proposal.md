## Why

PR #227 retired the in-app compact timer but left absence contracts behind: requirements that enumerate things which must *not* appear (a timer strip, a badge, a restore preference — features that never existed), scenarios retained explicitly as no-ops, a Mirror-reflection test asserting deleted property names stay deleted, and a code constant memorializing the removed timer's height. Specs should state what the system does, not what it doesn't do; tests should verify behavior, not the absence of deleted code.

## What Changes

- Remove the "History and Insights have no in-app running-timer surface" requirement and its scenarios from `app-shell` (the positive residue — Track shows the run, tab switches don't alter it — is already covered by `timer-capture-experience` and the Track requirement).
- Strip compact-timer tails from `history-entry-list` scenarios ("Final row reachable...", "Compact timer on History", "Running timer is not in History") and the "Removing the compact timer SHALL NOT prevent..." transitional sentences in `history-entry-list` and `insights-breakdown` (the refresh-on-return behavior they guard is covered positively by `EntryRefreshWiringTests`).
- Remove the admitted no-op "Stop after the activity was deleted elsewhere" scenario from `timer-capture-experience`.
- Remove "provenance labels" and "compact timer" from the intact-list in `history-search` ("Search composes with History lifecycle...") — both features are gone.
- Delete `TimerFreeShellCompositionTests` (Mirror-reflection absence test, the only `Mirror(` use in the tree).
- Rename `retiredCompactTimerSurface`/`timerAbsentClearance` to a neutral clearance name, drop the "No compact timer exists" comment, and reword `HistorySearchChromeTests` to assert clearance behavior positively.
- Fix the stale "compact timer's `refreshSignal`" doc reference in `EntryRefreshWiringTests` (suite logic itself is positive and stays).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-shell`: remove the timer-absence requirement; trim the transitional sentence in the accessibility requirement.
- `history-entry-list`: reword timer-absence scenarios to positive row/nav-bar behavior; drop the transitional sentence.
- `insights-breakdown`: drop the transitional sentence; trim the timer-absence tail from "Running timer excluded".
- `timer-capture-experience`: remove the admitted no-op scenario.
- `history-search`: drop the two removed features from the intact-list.

## Impact

- Baseline specs only (delta + archive sync); no behavior change, no API change, no migration.
- iOS tests: one file deleted, one test reworded, one doc comment fixed. No production code behavior change except the constant rename (value unchanged).
- Design docs (`COMPONENTS.md`, `SCREENS/History.md`, `SCREENS/Insights.md`) updated where they describe timer-free layout in negative terms.
- Must land **after** PR #231 (`remove-entry-integrations`) merges: that change touches `app-shell` and `history-entry-list` baselines via its own archive sync. Implement on a fresh `origin/main` rebase at apply time and re-check for delta conflicts.
- Research: ctx7 waived in full — pure removal of already-merged contracts with no new library, framework, SDK, API, or service behavior. No HIG lookup (no UI/grammar change), no Apple-API lookup (no ActivityKit/framework change), no best-practice lookup (no new pattern introduced; the change deletes a pattern). Reconfirm the waiver at apply time if scope grows beyond removal.
