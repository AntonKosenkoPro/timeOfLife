## 1. Foundation (VM + strings)

- [ ] 1.1 Add `LogTimeViewModel` (`Features/ManualEntry`): selected activity, `startsAt`/`endsAt` with Calendar-style duration preservation, `isAddEnabled` gate, 5-min-floor/+1h defaults, `save()` via `LocalStore.createEntry` (`source:"manual"`, UUID v7, derived duration)
- [ ] 1.2 Add EN + RU `L10n` strings for the sheet (Activity/Starts/Ends rows, Cancel/Add, Log time, `[+]` accessibility label, choose-activity placeholder)
- [ ] 1.3 SwiftTesting coverage for the VM: defaults, validity gate (no activity / end ≤ start), Start-past-End auto-push, Start-earlier keeps End, save payload shape (`source`, null `source_ref`, duration)

## 2. Sheet UI (Calendar grammar)

- [ ] 2.1 Build `LogTimeView`: nav-bar Cancel/Add, Activity row (title-over-value), Starts/Ends rows with date + time pills, `Theme` colors only
- [ ] 2.2 Inline single-open pickers: graphical month grid for dates, wheels for times, active-pill tint, device locale/calendar; sheet scrolls with a picker open
- [ ] 2.3 Wire save failure to a non-field error in the sheet (draft preserved, sheet stays open)

## 3. Activity picking reuse

- [ ] 3.1 Extract Track search + quick-create logic into a reusable picking unit without changing Track behavior (Track tests stay green)
- [ ] 3.2 Activity row opens the shared searchable sheet (browse/filter/quick-create, normalized-name collision rule); confirm selects, dismiss keeps prior; empty catalog routes straight to quick-create

## 4. Entry points + refresh

- [ ] 4.1 History toolbar `[+]` opens the sheet (persistent at all scroll positions); save refreshes the day-grouped list via `invalidate()` + reload
- [ ] 4.2 ActivityDetail `Log time` action opens the sheet pre-filled; Add/Cancel returns to the detail sheet; save refreshes its entry list and total
- [ ] 4.3 Sheet stacking verified: picker over Log Time sheet over History/detail, dismissal unwinds in reverse

## 5. Verification + docs (S5)

- [ ] 5.1 `swiftlint lint --strict` clean; `xcodebuild` build warning-free; `xcodebuild test` green (incl. new tests); manual smoke on iOS 15 simulator (graphical picker size) + 26 simulator, light/dark, EN/RU, Dynamic Type
- [ ] 5.2 Re-check `Requirements/FURPS/Timetracking.md` rows (F2/F10 provenance, no new policy) and `Common.md` (U4 locales, Theme); fix conflicts if any
- [ ] 5.3 Update `docs/history-roadmap.md` §4 (resolved by this change) and `docs/project-context.md` if surfaces changed; no OpenAPI/backend change to record
