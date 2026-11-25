## 1. Research and recorded reproduction gates

- [x] 1.1 Fetch/rebase this worktree onto fresh `origin/main`; reconfirm the ctx7 topic/SwiftUI and HIG sources, exact queries, iOS 18 SDK via Xcode 16+ availability, and external-library waiver recorded in `design.md` before implementation.
- [x] 1.2 Reproduce #247's Recents/page scroll conflict on the current tree with deterministic committed names on compact and roomy viewports; record device/text-size/data/gesture steps and evidence outside git. Add a failing regression where automatable. If unreproducible, stop and report rather than implement speculatively. Tasks 2–3 depend on both 1.1 and 1.2.

## 2. Candidate and fit policy

- [x] 2.1 Limit Track's exact-text Recents candidates to 10 without changing ordering/tiebreaks, inherited categories, the uncapped name-picker source, or storage schema.
- [x] 2.2 Reuse/extract actual wrapping measurements into a pure newest-prefix fit calculation; cover spacing, width clamping, variable row heights, current text size and border clearance without changing category packing.
- [x] 2.3 Add policy regressions for candidate counts 0–12; fits of 0/1/4/5/7/9/10; small all-fit sets; fewer-than-five overflow; and ten-candidate selection exposing exactly five when fewer than five fit.
- [x] 2.4 Add packing tests for long newer chips, variable-height rows, icons/selected chips, exact-fit boundaries, width/text-size invalidation, and nil/zero/negative/nonfinite geometry. Verify there is no recency skipping or invisible interactive/accessibility overflow.

## 3. Recents-only integration

- [x] 3.1 Integrate fitting-prefix non-scrolling presentation and newest-five internal overflow scrolling into `RecentActivitiesChips`; preserve dividers, stable identifiers, selection, empty state and tap inheritance.
- [x] 3.2 Reconcile finite Track height deductions, wrapped errors, caption/clearance and the explicit one-usable-row accessibility floor; additional Recents rows must not cause page growth. Preserve the dual-mounted lower slot, fixed action slot, and running TagSelector behavior.
- [x] 3.3 Cover transitions and first geometry convergence: stationary Start/Stop across idle/ready/running/saving/error, hidden-category floor, scroll-offset clamping/reset, 44 pt targets, VoiceOver omission/selection, and no post-settle layout jump.

## 4. Documentation and full verification

- [x] 4.1 Update `Design/COMPONENTS.md` Recents policy (including stale three-row wording), `Design/SCREENS/TimeTracking.md` plus its implementation checklist, relevant `Design/DECISIONS.md`/`INTERACTIONS.md`, and `docs/project-context.md`; keep the running-category contract unchanged.
- [x] 4.2 Recheck FURPS Common U1–U5/S2–S7/+2, Activity Catalog F1/F3–F5/U3/U8/U9/P1, and Timetracking F13; revise the conflicting F5/U3 12-cap/fixed-scroll rows. Keep Theme and five-locale compliance; if any new copy is unavoidable, add all five locales plus `L10n` and localization tests.
- [x] 4.3 On an iOS verification agent, run strict SwiftLint, warning-as-error build and the complete iOS suite per `docs/ios-test-loop.md`; serialize XcodeGen/project edits, xcodebuild and the owned simulator. Record actual results.
- [x] 4.4 In parallel on a separate backend verification agent, confirm `gofmt -l .` is empty and run `go vet ./...`, `golangci-lint run`, `go build ./...`, and `go test ./...`; record actual results even though no backend changes are planned.
- [x] 4.5 Re-run the identical 1.2 repro after the fix; capture compact/roomy/iPad widths, standard and accessibility text sizes (including less than one remaining row), five locales, wrapped errors, name-picker return and Start/Stop transitions. Verify running categories are unchanged. Keep binaries outside git; reference truthful evidence.
- [x] 4.6 Run `openspec validate --all --strict`, confirm baselines remain untouched, then fetch/rebase again before the implementation PR handoff and re-run affected checks. Reuse this proposal PR; keep #247 open for categories, and do not merge/archive without the later human approval gates.
