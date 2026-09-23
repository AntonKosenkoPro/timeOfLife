## 1. Sync join semantics

- [x] 1.1 `SyncController.syncNow` joins the in-flight `cycleTask` (await its result) instead of running a concurrent `runCycle`; keep `trigger()` early-return guard.
- [x] 1.2 `SyncControllerTests`: pull/profile trigger arriving mid-cycle joins (one drain+pull, both callers resolve); boundary race (cycle ends at check time) degrades to a cheap fresh cycle.

## 2. History pull gesture (sync-only)

- [x] 2.1 Attach `.refreshable` to the populated `historyList` branch only (empty state excluded); closure runs the verdict flow and never calls `vm.load()` explicitly (cycle-exit observer stays the sole reload).
- [x] 2.2 Pre-check order in the closure: signed-out → signed-out banner; offline (`Connectivity`) → offline banner; else await fresh-or-joined cycle.
- [x] 2.3 History UI tests: pull while signed out/offline starts no cycle and shows the right banner; pull while syncing joins (no second cycle).

## 3. Banners + sign-in link

- [x] 3.1 Shared inline banner below the nav bar (one at a time, newest pull wins): signed-out copy with sign-in link, offline copy without; `Theme` colors only.
- [x] 3.2 5s auto-dismiss task with cancel-before-replace, cancel on disappear/tab leave, early dismiss on sign-in flip.
- [x] 3.3 Banner link opens the existing Enable Sync sheet (`EnableSyncPresenter.enableSync` + `AuthFlowView` sheet, same as Profile): hoist or share presenter ownership so History can present it.
- [x] 3.4 `L10n` EN+RU strings for both banners + link (`L10n.allCases` updated if enumerated).

## 4. Error dialog (OK only)

- [x] 4.1 Pull-in-flight flag: `.alert` with localized title + secret-free message body + single OK, presented only when a pull-awaited cycle ends `.error`; background failures with no pull in flight stay dialog-free.
- [x] 4.2 Mid-cycle connectivity flap routes to the dialog (not the offline banner).

## 5. Verification + docs

- [x] 5.1 `swiftlint lint --strict` clean; iOS build green (warnings are errors on app/test targets; GRDB `-suppress-warnings` untouched).
- [x] 5.2 iOS test suite green (`xcodebuild test -scheme TimeOfLife`): new join/banner/dialog tests plus existing History/Sync suites.
- [x] 5.3 Re-check `Requirements/FURPS/*.md` rows for History/sync; reconcile conflicts.
- [x] 5.4 Update `docs/project-context.md` if the sync-trigger list or History behavior description changed; confirm `backend/api/openapi.yaml` untouched.
- [x] 5.5 `openspec validate --all --strict` green.
