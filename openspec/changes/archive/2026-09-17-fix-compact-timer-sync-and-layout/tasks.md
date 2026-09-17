## 1. Track reconciles external stops (bug 1)

- [x] 1.1 Reconcile in `TrackViewModel.load()`: when state is `.running` but the persisted timer is gone (or its activity unresolvable), stop the ticker, re-enable the idle timer, reset `elapsed` to zero, and set `.ready(activity)` (activity still exists) or `.idle`; leave `.saving`/`.error` untouched.
- [x] 1.2 SwiftTesting coverage in `TrackViewModelTests` (temp store + `TimerService`, established pattern): running→ready with elapsed reset after an external stop (stop via a second service/VM path or direct `stopTimer` + deleted `timer_state`); running→idle when the activity was deleted; no-op when the persisted timer still exists; `.saving` never clobbered by a re-`load()`.
- [x] 1.3 Manual simulator pass: start on Track → switch to History → Stop on the compact timer → return to Track → ready timer for the same activity at zero, no ghost counting; lock the simulator to confirm the idle timer re-enabled.

## 2. Entry-form picker containment on 320 pt screens (bug 2)

- [x] 2.1 Bound the expanded inline `DatePicker`s in `LogTimeView` to the card width (both `.graphical` and `.wheel`), keeping `Theme` margins in CREATE, EDIT, and LOCKED modes; no new strings, no grammar changes.
- [x] 2.2 Simulator pass on a 320 pt device (iPhone SE 1st-gen class, iOS 15): expand each of the four pills (start/end × date/time) in CREATE and EDIT modes and confirm cards keep horizontal margins with nothing clipped at the edges; re-check a large phone for regressions.

## 3. Compact-timer bottom spacing (bug 3)

- [x] 3.1 Add bottom padding inside `CompactTimer` (mirroring the existing top pad, `Theme` token only) so the surface floats above the tab bar on History and Insights.
- [x] 3.2 Simulator pass on History and Insights while running: visible daylight between compact timer and tab bar, no overlap at 1× scale.

## 4. Verification and docs

- [x] 4.1 `swiftlint lint --strict` clean; `xcodebuild -scheme TimeOfLife -destination '<available simulator>'` warning-free build; `xcodebuild test` green.
- [x] 4.2 Re-check `Requirements/FURPS/Timetracking.md` + `Common.md` rows for conflicts; fix or reconcile (expected: none — read-path reconciliation, layout-only changes, no API/contract touch).
- [x] 4.3 Update `docs/project-context.md` only if architecture/contract/run steps changed (expected: no doc changes beyond the change's own artifacts).
