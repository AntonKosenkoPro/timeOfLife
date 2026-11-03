# evidence-ios (app-store-screenshot-pilot, iOS worker)

Owner: iOS implementer. Single-writer: ledger worker owns `tasks.md`/docs;
this file is the iOS worker's evidence ledger (authorized in the work order).

## Rebase / baseline (tasks 1.2)

- `opsx/app-store-screenshot-pilot` @ `c3e5911` == `origin/main` (fetch clean,
  tracked tree clean, untracked planning artifacts preserved, no stash).
- Toolchain: Xcode 27.1 (27A9275), XcodeGen 2.46.0, runtimes iOS 18.6 + 27.0.
- Baseline `build-for-testing` (Debug, pre-change tree): green.
- Post-change Debug `build-for-testing`: green (see Verification below).

## Toolchain note (Xcode 27.1 memberwise-init synthesis)

A `let` property of function type WITH a default value
(`let now: () -> Date = Date.init`) is **omitted** from the synthesized
memberwise initializer on this toolchain (reproduced in isolation with
`swiftc -typecheck`, View and non-View alike). `var` with a default is
included. `CompactTimer.now` is therefore `var` (plain, not `@State`).

## Failing clock tests first (tasks 1.3)

`TimeOfLifeTests/CaptureClockSeamTests.swift` (new, ungated): five tests
pinning the Tue 2026-10-20 09:41 reference through existing injection
points — History `load()` vs wall clock, Track `start()` anchor, Track
`stop()` endedAt/duration, adopted-draft elapsed seed, compact-stop save.
Four bind pre-existing `now:` seams; the compact-stop test binds the new
`AppShellViewModel(now:)` seam (assertions unchanged from the failing
version). All five fail on the pre-fix tree for the recorded bypass
reasons; re-run after the fixes below.

## Clock-forwarding fixes (tasks 3.3; production defaults unchanged)

- `TrackViewModel`: `calendar` param (default `.current`); all internal
  `Date()` (start/stop/endedAt/duration/ticker seed+tick/load/adopt
  fallbacks) replaced with `nowProvider()`; new `now` accessor and
  calendar-aware `timeText(for:)`.
- `HistoryViewModel`: `calendar` param; `load()` uses `nowProvider()` +
  stored calendar/locale; `timeframeText` and the Started caption path use
  an instance formatter (locale/time zone from the calendar); absolute
  `dayLabel` formatter pinned to the grouping calendar (identical output
  for `.current` in production).
- `AppShellViewModel`: `now:` param (default wall clock); `stopFromCompact`
  and the compact surface read it.
- `CompactTimer`: `now:` tick-date closure (default wall clock); the
  TimelineView still drives cadence.
- `TrackContent` → `RunningStartEditor(startedAt:now:calendar:timeText:)`
  from the running VM; `referenceNow` freezes from `now` (was `Date()`);
  sheet math (`floorToMinute`, `isYesterday`, `resolveForDay`,
  `wheelRange`, caption) threads the calendar.
- `HistoryView` / `InsightsView` / `AppShellView`: defaulted
  `clock: AppClock = .live` forwarded to their VMs
  (`AppClock` = explicit `{ now, calendar }` bundle, `.live` = wall clock +
  `.current`; never a global).
- `InsightsViewModel`: unchanged (already took `now:` + per-call
  `calendar:`); the view now passes both from the clock.
- `TimerService` / `LiveActivityService`: unchanged — callers pass explicit
  dates; the orphan-reap anchor stays wall-clock by design (real system
  timer, §4 waiver).

## Screenshot configuration (tasks 2.1/2.2)

- `project.yml`: `Screenshot: release` config + `Config.Screenshot.xcconfig`
  (unroutable API base `http://127.0.0.1:9`, empty Sentry DSN);
  per-target `Screenshot` overrides ONLY (research: exact-name `Release`
  overrides do not inherit): distinct app/extension bundle IDs
  (`…timeoflifeapp.screenshots`, `….screenshots.liveactivities`),
  capture-only entitlements (group
  `group.com.antonkosenko.timeoflifeapp.screenshots`; SIWA + associated
  domains deliberately omitted), `SCREENSHOT_CAPTURE` condition,
  `SUPPORTED_PLATFORMS=iphonesimulator` (device builds and
  device-destination archives fail at build time). Debug/Release
  schemes/signing/archive routing untouched. New non-distribution
  `TimeOfLife-Screenshot` scheme (run/test/profile/analyze/archive all on
  `Screenshot`; tests execute the gated capture paths).
- `LocalStore.appGroupID` is `#if SCREENSHOT_CAPTURE`-gated to the capture
  group, so extension/intent resolver paths in capture builds can never see
  production files (no intent code change needed — resolution fails closed
  to `.locked`/sandbox fallback).
- `TimeOfLifeApp`: `#if SCREENSHOT_CAPTURE` branch (simulator-only
  `fatalError` otherwise) building an inert placeholder container (unbound
  store, signed-out session, sync never activated) and mounting
  `ScreenshotCaptureRootView`; production/DEBUG paths untouched.

## Capture composition (tasks 2.3/2.5, 3.2/3.4, 4.3)

- Contract: launch argv/env token `SCREENSHOT_REQUEST` (+`SIMCTL_CHILD_`
  form) with filename `capture-request.json`; the app reads ONLY
  `Documents/capture-request.json` (never an argv path). Strict snake_case
  validation, fail-closed codes; pinned pilot inputs
  (`en-austin-1`, en/US/America-Chicago, gregorian, locale-native,
  `2026-10-20T09:41:00`, 754 s); frame/mode consistency enforced
  (live-activity ↔ realtime only). Cosmetic fields not decoded
  (runner-owned). SHA-256 over exact file bytes.
- `Documents/capture-state.json`: atomic writes, `preparing` → `ready` /
  `invalid` / `failure` with sha, deck, frame, mode, run id, entry count,
  computed + validated totals, build info, clock domains, realtime anchor
  block, and `{code, detail}` failures. `ready` = validated store +
  view-model agreement + mounted native view + measured settle grace.
- Fixture (`ScreenshotFixture`, gated): 7 stable-ID English starter
  categories in canonical icon order + 55 committed Austin entries over 21
  days (27 distinct texts, multi-category entries, one notes entry,
  `Coffee`/`coffee` exact-text pair, long workshop name) + separate running
  draft (`Morning run`, 754 s offset). All entries complete before the
  logical reference.
- Pipeline (`ScreenshotPreparation`, gated): fresh per-run session dir →
  isolated store → stable-ID seeding → draft → read-back validation
  (55-count, link resolution, totals, draft exclusion). Fatal on any
  `.invalid`/`.failure`/mismatch — no fallbacks.
- Composition (`ScreenshotApp`/`ScreenshotCaptureFlow`, gated): process
  locale applied pre-read; ephemeral keychain + capture prefs suite +
  fictional session; sync constructed but never activated (runtime-guarded);
  dead API client on the unroutable base URL; frame navigation on the REAL
  `AppShellView` (Track/Insights/History tabs, pushed name picker);
  realtime frame re-anchors to wall-now minus offset through the real
  TimerService/ActivityKit path with ack polling (timeout → failure, never
  a mock); stale fixture-text activities ended pre-run.
- Unsafe paths removed: no production App Group/keychain/suite access, no
  sync activation, no network calls, no overlays in exported images.

## Expected totals (fixture `en-austin-1`, for runner pinning)

```json
{"all_seconds":198600,"today_seconds":4500,"week_seconds":23100,
"category_seconds":{"shot-cat-education":8700,"shot-cat-entertainment":38700,
"shot-cat-hobby":20100,"shot-cat-relax":11700,"shot-cat-sport":42300,
"shot-cat-work":51000},
"text_seconds":{"ACL festival":5400,"BBQ":3600,"Barton Springs swim":8700,
"Breakfast tacos":2700,"Brunch":2700,"Code review":14100,"Coffee":3900,
"Deep work":27000,"Design sync":2700,"Evening walk":11700,
"Farmers market":6300,"Football night":9900,"Grocery run":7200,"Gym":6900,
"Inbox zero":1800,"Live music":18000,"Lunch break":8400,"Morning run":7500,
"Movie night":5400,"Quarterly planning workshop with the platform team":5400,
"Reading":8700,"Side project":8400,"Tacos":6000,"Team lunch":3600,
"Trail run":3900,"Yoga":5400,"coffee":3300}}
```

Computed independently in Python from the deck definition AND asserted
verbatim by `ScreenshotCaptureTests.preparationTotals` (Swift
recomputation must agree at capture runtime before `ready`).
Reference = Tue 2026-10-20 09:41 America/Chicago (14:41 UTC); draft start
09:28:26 local. Locale-native week (en_US, Sunday start) = Oct 18–24.

## Verification (tasks 5.1, Debug side)

> NOTE (accuracy correction, 2026-10-30): the "all 5 fail pre-fix" claim in
> earlier drafts was bypass-line analysis, NOT executed proof. The executed
> red/green record is below; the isolated-baseline chronology follows in the
> next section. Do not cite analysis as reproduction.

### Red-proof runs (executed record)

- Oct-date probe (first attempt): all 6 passed — but the new calendar test
  passed VACUOUSLY through its guard: outside DST the one-day fold preserves
  the instant in every zone, so Chicago and host resolutions coincided.
  Flawed probe, discarded (never claimed as red).
- DST probe (verified first with a standalone Foundation script): Nov 1 2026
  12:00 CST `now` + Nov 2 00:30 UTC `picked` folds to Oct 31 23:30 UTC in
  Chicago vs Nov 1 00:30 UTC elsewhere (25 h vs 24 h day). Test rewritten to
  these dates with the vacuous-host guard retained.
- Executed RED (2026-10-30, session-owned sim `E915572B`, fix withheld):
  EXIT=65, 1 of 6 failed — `Started-at edit resolves in the model calendar`
  with `startedAt` = 2026-11-01 00:30:00 UTC vs `expectedChicago` =
  2026-10-31 23:30:00 UTC (exactly the predicted 1-hour DST gap); the other
  5 passed. Log: `screenshot-pilot-red-proof3.log`.
  One-line fix applied after: `updateDraftStartedAt` now passes
  `calendar: calendar` (production default `.current` unchanged).
- Executed GREEN (same sim, fix applied): EXIT=0, 6/6 pass in 0.050 s
  (`TEST SUCCEEDED`, log `screenshot-pilot-green-proof.log`). Red→green
  cycle closed for the calendar seam.

### Shared-sim contact (safety correction, 2026-10-30)

- The shared booted iPhone 17 (`C18365F5`, owned by another session) WAS
  touched by this worker's earlier filtered test runs: every `xcodebuild
  test -destination id=C18365F5` installs and launches the test host app on
  that simulator (the green runs at ~10:38 did so successfully; the hung run
  attempted install/launch and never established the runner connection).
  Earlier "untouched" wording is corrected: it was never booted, shut down,
  or erased by this worker, and no corrective manipulation of its apps,
  data, or state was or will be attempted — but install/launch contact
  happened, and whether the hung run left a stale test-host install there
  is UNKNOWN (deliberately not investigated — no touching to "fix" it).
- All future tests and captures run ONLY on the session-owned sim
  (`E915572B`, "SHOT iPhone 16 Pro Max", iOS 18.6, created+booted by this
  worker) or another session-created device. No shared-device actions.
- Post-change Debug `build-for-testing`: green (EXIT=0) after fixing three
  compile errors (`CompactTimer.now` memberwise-init synthesis — defaulted
  `let` closures are omitted on this toolchain, now `var`; one test-file
  bracket typo; missing `await` on actor-isolated store calls in the new
  seam tests).
- `swiftlint lint --strict`: 0 errors throughout (all findings in new
  files, fixed as filed).
- New suites, all passing post-fix (`TEST SUCCEEDED`): `CaptureClockSeamTests`
  (now 6 with the calendar test), `ScreenshotRequestTests` (7 with cleanup
  detection), `CaptureStateTests` (3 with cleanup round-trip).
  Failing-before status, honestly graded:
  * EXECUTED red: `Started-at edit resolves in the model calendar` (this
    run series — 1-hour DST gap, EXIT=65 pre-fix; green after the one-line
    fix, verified by rerun below).
  * Analysis-only (NOT executed pre-fix — superseded as repro, kept as
    rationale): the four older seam tests assert fixed-now outcomes the old
    `Date()` paths could not produce (10-day offset; preflight report).
    Their chronological proof comes from the isolated-baseline worktree run
    (next section), not from analysis.
- Isolated baseline (pristine `c3e5911`, detached scratch worktree in
  approved temp — main-tree edits untouched): `BaselineClockSeamTests.swift`
  (4 tests binding pre-existing seams only: History load, Track start/stop,
  adopted elapsed; verified the bypass line exists at
  `HistoryViewModel.swift:58` on the pristine tree). `xcodegen generate` +
  lint clean in scratch.
- Executed BASELINE-RED (pristine tree, owned sim): EXIT=65, 4/4 failed
  with 7 issues — History load (dayGroups mismatch + label), Track start
  (anchor), Track stop (duration + endedAt + durationSeconds), adopted
  elapsed. Log: `screenshot-pilot-baseline-repro.log`. The identical
  assertions pass on the fixed tree (filtered + full Debug suite). The
  1.3 chronological proof is complete: red on pristine, green on fixed.
  Scratch worktree removed after the run.
  * New-seam (not a pre-existing repro): the compact-stop test binds the new
    `AppShellViewModel(now:)` seam, which has no baseline counterpart —
    labeled as such, assertions otherwise identical.
- `TrackSyncReloadTests`: the two `stopGate`-held tests + helper gated
  `#if DEBUG` (`stopGate` is a DEBUG-only hook, absent from Screenshot).
- Full Debug suite: `TEST SUCCEEDED`, 865 tests / 83 suites, EXIT=0
  (no regressions from the clock seams).
- Full Debug suite FINAL (all edits in, owned sim): `TEST SUCCEEDED`,
  EXIT=0, 868 tests / 83 suites, zero failures (+3: calendar seam test,
  cleanup detection, cleanup round-trip; includes the backdated
  LWW-timing test green under -Onone too).
- Note: `origin/main` has since advanced to `479a998` (observability
  Stage-1 merge); this work stays based at `c3e5911` (rebase is PR-phase
  work, no commits made here). Docs/runner files in this worktree belong to
  parallel workers — untouched.
- Screenshot suite chronology (owned sim unless noted):
  * Attempt 1: `Unable to resolve Swift module dependency` — release-type
    config builds the app without `-enable-testing`, so `@testable import`
    failed. Fix: `ENABLE_TESTABILITY: YES` on the app target's Screenshot
    config only (optimization stays Release-class).
  * Attempt 1b: test host crashed at launch in `captureSuite()` —
    `UserDefaults(suiteName:)` returned nil on a first-launch test host
    (domain machinery itself verified working via a `simctl spawn defaults`
    round-trip). Launch-time `fatalError` removed: fallback chain through
    per-launch domains, safe because `SessionCache.save` has no capture
    call site (object never written; never production `.standard`).
  * Attempt 2: 877/84 with the 2 diagnosed issues below; gated suite
    already executed green here (test-target flag works, no vacuous pass).
- Screenshot full suite FINAL (owned sim `E915572B`): `TEST SUCCEEDED`,
  EXIT=0, 877 tests / 84 suites, gated `Screenshot capture` suite executed
  and green (preparation 55/links/totals/draft-exclusion/restart, week
  rule, isolation, container, all cleanup paths; plus the config-aware
  route proof that the test-target flag is live). Resolves attempt 2's two
  issues: config-aware AppConfig port assertion (Screenshot asserts the
  discard port 9 — fail-closed proof) and the backdated creation stamp for
  the LWW-timing test (filtered green in both configs' logic; confirmed in
  this full run).
- Release-negative (ordinary Release, `TimeOfLife` scheme, Release config):
  `BUILD SUCCEEDED`, EXIT=0 (signing fine for simulator). Binary proof —
  Release binary contains ZERO of: `capture-request.json`,
  `capture-state.json`, `capture-cleanup.json`, `SCREENSHOT_REQUEST`,
  `SCREENSHOT_CLEANUP`, `en-austin-1`, `shot-cat-work`, `shot-e01`,
  `Barton Springs swim`, `Quarterly planning workshop`,
  `screenshot-capture`; bundle ID is production
  `com.antonkosenko.timeoflifeapp`. Only `AppClock` type-name symbols
  remain (2 hits — the declared production default seam, no payload).
  Contrast: the Screenshot binary contains all of them (6/4/24/4 hits).
  Strict 2.4 exclusion proven at the binary level.
- Retention root confirmed present and empty:
  `/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`.

## Guard: Screenshot install/archive denial (tasks 2.1)

- Gap (review finding): `SUPPORTED_PLATFORMS=iphonesimulator` rejects
  device builds but a simulator-destination `xcodebuild archive`/`install`
  would still succeed — no explicit denial existed.
- Red FIRST (executed): new matrix test
  `ios/TimeOfLife/scripts/deny-screenshot-install.test.sh` run against the
  missing guard → 8 failures (absent script + absent wiring).
- Guard: `ios/TimeOfLife/scripts/deny-screenshot-install.sh` — denies
  `ACTION=install` ONLY when `CONFIGURATION=Screenshot` with an explicit
  `error:` message; every other combination allowed. Matrix after script:
  7/7 behavior green, wiring still red.
- Wiring: `preBuildScripts` on the TimeOfLife app target (`project.yml`),
  first phase position verified in generated pbxproj (before Sources);
  `.sh` files correctly absent from Compile Sources. Matrix fully green
  (0 failures) after `xcodegen generate`.
- Real archive probe (external derivedData+archive paths, QA artifact
  untouched): `xcodebuild archive -scheme TimeOfLife-Screenshot
  -destination 'generic/platform=iOS Simulator'` → EXIT=65,
  `** ARCHIVE FAILED **` with exactly `error: Screenshot configuration
  forbids the 'install' action (capture builds are simulator-run only;
  archives stay on the Debug/Release scheme)`; no `.xcarchive` produced
  (only the external DerivedData dir). Log: `shot-guard-probe.log`.
  Follow-up: `basedOnDependencyAnalysis: false` added to the phase (a gate
  must run every build; silences the Xcode warning like the Stamp phase) +
  regenerate + matrix re-green. The probe ran one phase-generation earlier;
  the change is caching-only (identical script/env check), so the denial
  result stands.
- Debug/Release restriction check: matrix asserts Debug+install and
  Release+install stay allowed (exit 0); the guard script tests only
  `CONFIGURATION=Screenshot`; ordinary schemes' builds/tests ran green
  throughout (868 Debug / 877 Screenshot suites).

## Residual / handoff notes

- **Leases RELEASED**: exclusive xcodebuild lease AND generic-build lease
  are both released with this report. No builds running, no simulators
  touched beyond the session-owned one, nothing held.

- **Lease RELEASED**: the exclusive xcodebuild/simulator-test lease is
  released with this report. No xcodebuild running; nothing held.
- Session-owned sim for capture/QA (left BOOTED for handoff):
  `E915572B-E7CA-469A-9211-EE0A62CA2EA0` ("SHOT iPhone 16 Pro Max",
  iOS 18.6, 1320×2868 portrait). Test-host installs from verification
  remain on it (harmless — the runner installs per frame). The shared
  iPhone 17 (`C18365F5`) is left exactly as found apart from the
  disclosed test-host contact; never touch it.
- Screenshot app build (current): `~/Library/Developer/Xcode/DerivedData/TimeOfLife-*/Build/Products/Screenshot-iphonesimulator/TimeOfLife.app`,
  bundle ID `com.antonkosenko.timeoflifeapp.screenshots`. Launch per frame
  with `SCREENSHOT_REQUEST capture-request.json` (request file at the
  app's `Documents/capture-request.json`); cleanup with
  `SCREENSHOT_CLEANUP=<run_id> SCREENSHOT_CLEANUP_SHA=<sha>`.
- Capture runtime (5.2+) is NOT done here: runner contracts, sim setup,
  and actual captures belong to later tasks; stop is before 5.4 (no
  non-English/iPad/montage).
- Live Activities left live by the realtime frame are the runner's to end
  (activity id is in the state file); pinned runs pre-end fixture-text
  activities defensively.
- `UserDefaults(suiteName: …screenshots)` persists a capture prefs file in
  the session-owned simulator only; production prefs untouched.
