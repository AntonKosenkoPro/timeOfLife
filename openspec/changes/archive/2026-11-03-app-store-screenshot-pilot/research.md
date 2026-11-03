# Screenshot pilot — research refresh (2026-10-30)

Reconfirms the proposal/design research bundle before code changes (tasks.md 1.1).
ctx7 budget: 3/3 commands used by specs-docs researcher on 2026-10-30. No quota
error. No further ctx7 calls may be made for this question by any agent.

## ctx7 (library `/websites/developer_apple_xcode`, Xcode 16+ SDK pin)

1. `library Xcode "Taking screenshots ... localization UI tests"` → resolved
   `/websites/developer_apple_xcode` (exact name match, High reputation, 4350 snippets).
2. `docs /websites/developer_apple_xcode "Taking screenshots and recording movies
   in Simulator for App Store using simctl io screenshot status_bar override launch
   arguments localization UI tests"` → confirms: Device Hub captures at full device
   resolution to Desktop; localization screenshots via per-locale test-plan
   configurations (Application Language + Region, Localization Screenshots On) or
   Test-scheme language/region + "Gather screenshots for localization".
3. `docs /websites/developer_apple_xcode "Creating build configurations and setting
   Swift active compilation conditions per configuration to isolate development
   features from Release archive"` → confirms: `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
   per-config conditions; xcconfig layering (project → config file → target);
   Debug/Release scheme mapping (Run vs Archive); `<Multiple values>` inspection
   for config-divergent settings.

## Official sources read directly (documented route waivers, no extra ctx7)

- Live Activities HIG (`developer.apple.com/design/human-interface-guidelines/live-activities`)
  and ActivityKit (`.../activitykit/displaying-live-data-with-live-activities`):
  URLs verified live 2026-10-30 (DocC JSON tutorial endpoints return empty shells;
  canonical pages resolve). Constraints unchanged from design §5/§7: genuine
  platform presentations, readable content, foreground requests; no new SDK API.
- XcodeGen ProjectSpec (raw GitHub master, read full 2026-10-30): `configs`
  (`Debug: debug`, `Beta/AppStore: release` pattern — a third release-type config
  gets Release-class defaults but does NOT inherit exact-name `Release` overrides),
  per-config `settings.configs` (case-insensitive substring match, exact match is
  exclusive), `configFiles`, schemes. Installed version 2.46.0 — reconfirm at apply;
  exact-name Release overrides must be audited, not assumed, for `Screenshot`.
- App Store screenshot specifications + localization reference
  (`help/app-store-connect/reference/app-information/...`): URLs verified live;
  pages render nav-heavy via fetch, substance already captured in #198/proposal
  (6.9" 1320×2868 + 6.5" 1242×2688 retained, 13" iPad 2064×2752 actual layout,
  es-419 app captures → Spanish (Mexico) Store listing).
- Review guidelines 2.3.3/2.3.9 (read full text 2026-10-30): screenshots must show
  the app in use (not title art/login/splash; overlays allowed); display fictional
  account info, never real-person data.

## Installed runtime versions (read-only, 2026-10-30)

- Xcode 27.1 (build 27A9275) — matches proposal's research host; product floor
  remains iOS/iPadOS 18 SDK via Xcode 16+.
- XcodeGen 2.46.0.
- Simulator runtimes: iOS 18.6 (22G86), iOS 27.0 (24A434).
- `simctl help status_bar`: `--time` ISO override, dataNetwork/wifi/cellular modes,
  batteryState/Level — cosmetic chrome only, NOT an app-clock freeze.
- `simctl help io`: `screenshot [--type png...] [--display] [--mask]` native-res
  PNG export; `recordVideo`; `enumerate`.
- `simctl help ui`: `appearance [light|dark]`, `content_size` (incl. accessibility
  sizes), `increase_contrast` — no frozen application clock.
- No device booted/controlled; no `xcodebuild` build/test/generate run (iOS
  implementer owns that lease).

## FURPS/context read for 1.2 (no checkbox — rebase evidence owned by iOS worker)

Common U1/U2/U4/U5, S2/S5/S6; Timetracking F4/F15/R2; supported-devices +2;
`docs/ios-test-loop.md` pointer noted. Capture limitations restated, no
screenshots claimed verified.

## #198 wording (read 2026-10-30, no edit made)

Issue #198 (OPEN, `enhancement`) already records the 2026-10-29 owner decisions
(iPad in scope, story order, English pilot first, montage scope) with agent
attribution footer intact. Its "Preparation" section still carries the literal
"requests Release builds ... DEBUG-only" wording; the owner-selected separate
Screenshot configuration (proposal §"What Changes", design §1) resolves this.
Reconciliation comment deferred to tasks.md 8.4 handoff (actual-scope update),
not needed at research stage.

## Status

- Task 1.1 fulfilled by this file; nothing here pins the text capture manifest
  (no runner source exists yet) — pilot inputs stay proposed defaults subject to
  task 5.4 visual approval.
- Backend/API/HIG-redesign items N/A: no server contract or product-layout change.

## Docs pass (2026-10-30, specs-docs)

- Task 1.2 marked done on relayed iOS-preflight evidence (fetch clean, rebase
  no-op @ c3e5911 == origin/main; FURPS + ios-test-loop read); baseline xcode
  failure is missing-pbxproj setup, core runs xcodegen next. Backend green
  (go1.27.3, 12 packages) noted — 8.1 stays unchecked until iOS verification.
- Owner storage decision recorded: `/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`
  (design Open Questions Q1 resolved; STOP 5.4 retained, location ≠ approval).
- `docs/screenshot-capture.md` initial runbook draft added from the agreed
  runner interface (BID `...app.screenshots`, `capture-request.json` +
  `SCREENSHOT_REQUEST` argv, atomic `capture-state.json`
  preparing/ready/invalid/failure); every unverified item labeled PLANNED.
- 1.3/1.4 left unchecked (no failing seam tests, no runner manifest yet). No new
  ctx7 calls (budget exhausted). No app/scripts code touched.

## Docs pass 2 (2026-10-30, specs-docs)

- Task 1.4 marked done: `scripts/screenshots/pilot_manifest.json` read directly
  — all owner pins present (`2026-10-20T09:41:00` Tuesday, `app_elapsed_s 754`,
  `light`/`large`, en/US/America/Chicago, Screenshot config + screenshots BID);
  #198 reconciliation comment posted earlier this session. `expected_totals`
  null/`pending-ios-owner` does not block the parameter pin; fixture totals NOT
  claimed done; 5.4 still gates.
- Runbook corrected: first-pass runner source exists (`capture.py` is the actual
  CLI, not `capture_pilot.py`) but UNVERIFIED — executor missing, 4.1/4.2/4.4/4.5
  NOT complete, negative-validation fixes in flight, CLI not stable until second
  pass. xcodegen guidance fixed for fresh worktrees (first generate required;
  preflight baseline failure is setup, not a bug).
- 1.3/8.2 left unchecked (no seam-test or implemented-state evidence). No
  research calls, no code edits, all worker files preserved.

## Docs pass 3 (2026-10-30, specs-docs)

- Task 1.4 note refreshed: totals PINNED and directly re-verified
  (`expected_totals.json`: 27 texts, text-sum 198600 == all_seconds, today 4500,
  week 23100, Coffee 3900/coffee 3300, Morning run 7500) — stale null/pending
  wording removed.
- Task 3.1 marked done: `ScreenshotFixture.swift` definition verified
  (`entryCount 55`, daysAgo 0–20, Coffee/coffee pair, multi-category, notes,
  long text, separate Morning-run draft; independent review count/time/order,
  all past logical now). No runtime preparation claimed (3.2 open).
- Task 4.5 marked done (pure code/tests): `approval.py` + negative gate tests
  read directly (`ipad_blocked_without_approval`,
  `test_non_approved_decision_blocked`, `test_tests_do_not_imply_approval`,
  `tampered_frame_invalidates`, `check_approval_gates`); runner suite 115/115
  green by direct run. Validates-only, never approves — NOT asset approval.
- Held unchecked: 1.3 (historical fail-before was analysis, not executed —
  core doing the actual failing run), 2.4/2.5/5.1/8.1 (Screenshot flag fix +
  rerun pending), 4.1/4.2/4.4 (no runtime proof, teardown partial), 5.4 never.
  Runbook revised to executable-CLI-vs-unverified-runtime. No research calls,
  no code edits, no commits, no GitHub comments.

## Docs pass 4 (2026-10-30, specs-docs — core final verification, docs only)

- Read `evidence-ios.md` head + 140–293 directly. Marked DONE with
  source-verified evidence: 2.2 (per-target Screenshot overrides, base-level
  versions, config-agnostic Cloud scripts, serialized generate + binary/route
  proof), 2.3 (gated composition: ephemeral creds, isolated store/marker,
  dead API client, atomic state signals; isolation + cleanup tests green),
  2.4 (Release binary ZERO payload strings + production BID; Screenshot
  binary holds them; AppClock type-names only), 2.5 (`sessionIsolation`,
  `containerIsolation`, fail-closed + scoped-cleanup paths),
  3.2 (`preparationCounts/Totals`, `localeNativeWeek`, `draftAnchor`,
  `cleanRestart`), 3.3 (`AppClock` threading verified in Track/History/Shell/
  Compact/views; DST 6/6 + baseline assertions + full suites rerun green),
  5.1 (Debug 868/83, Screenshot 877/84, Release build + binary proof,
  SwiftLint 0 errors, binaries/logs outside git).
- 1.3 LEFT OPEN with deviation note: only the DST seam has genuine pre-fix
  red; 4/5 seam reds are retrospective-baseline (pristine c3e5911 4/4) —
  user waiver pending via main, history not rewritten.
- 2.1 LEFT OPEN with residual note: device rejection two-layer verified;
  scheme archive action unguarded for simulator destination.
  3.4 genuinely pending (QA keyboard proof). 4.1/4.2/4.4 + 5.2/5.3/5.4
  unchecked (no runtime captures; user 'SO?' ≠ approval).
- Recorded: QA sim `E915572B-…-62CA2EA0` BOOTED handoff, no frames yet;
  shared `C18365F5` contact truthful (state UNKNOWN, never touch);
  base `c3e5911`, `origin/main` @ `479a998`, rebase PR-phase pending.
- Runbook: core verification actuals section added, cleanup contract schema
  (`SCREENSHOT_CLEANUP`/`_SHA` → `capture-cleanup.json`
  cleaned/mismatch/failure) from `ScreenshotCleanup.swift` source,
  2.4 binary-proof method noted, lease-release + missing-list refreshed.
  Storyboard done-list updated. No research calls, no app/scripts edits,
  no commits, no GitHub comments.

## Docs pass 5 (2026-10-30, specs-docs — human disposition on 1.3 + QA sim)

- Human said 'Ok, record this' after plain explanation of the 1.3 deviation.
  Created `execution-notes.md`: exact chronology (test-first NOT followed for
  4/5; retrospective pristine-c3e5911 red 4/4 + same-assertions-green-fixed;
  DST seam genuine red-before-fix 6-case cycle), core-log + evidence-ios
  links, human disposition, future bugfix rule explicitly UNCHANGED, no
  'originally followed' wording anywhere.
- Task 1.3 revised to a recording task (original requirement quoted in-note)
  and marked DONE — retrospective evidence + deviation + acknowledgment all
  recorded, evidence links directly verified. 5.4 untouched (no approval
  inferred). No baseline spec / prod behavior change, no GitHub entity.
- QA moved to FRESH sim `DC79DF29-708B-4928-91A9-8CD5B6352671` (screenshots
  BID only); `E915…` demoted to test-only history in tasks 5.2 + runbook.
  No PNGs claimed until QA returns. 2.1 stays open (core fixes archive guard
  separately). Runner 131/131 by direct re-run (cleanup-wiring tests added);
  cleanup contract runner-side stable, runtime 4.x pending on-device proof.

## Docs pass 6 (2026-10-30, specs-docs — pilot CAPTURED DRAFT)

- Read `capture-QAevidence.md` (all 160 lines incl. 11:53 addendum),
  `runs/pilot-r2/run-manifest.json` (full, direct), r1 manifest status/frames
  (direct), and `contact-pilot-r2-review.jpg` (direct read).
- Marked DONE: 4.1 (explicit IDs, validation, native export, repo-guard +
  reusable Argent flow, 2 PASS/PASS on DC79), 4.2 (overrides applied +
  restored, genuine docked en-US keyboard verified both runs, 10/10 teardowns,
  scoped shutdown), 4.3 (real anchors, genuine Lock Screen, tz-aware stamps,
  |diff| 1 s both runs, verify-la passes, error paths tested), 4.4 (per-run
  manifests + external review sheets incl. r2-review.jpg sha `e39c2287…b5a9a70`;
  131-test coverage of negatives), 5.2 (two full runs in order, native dims,
  finalize complete + pending[] both, stable content, chrome restored).
- 3.4 + 5.3 OPEN with recorded MAIN-review blockers: History frame shows NO
  notes glyph in 9 visible rows (independently corroborated; QA line-57 claim
  disputed — correction owned by QA worker, their file untouched; scrolled
  recapture needs no fixture change — user decides, no app edits from docs).
  Also: Jan-1 lock date (disclosed side effect; full-ISO path needs repro +
  approval), history 29.6kpx/0.78% shimmer (never quote superseded
  675px/2701B), LA numeric-only variance, RU globe is owner treatment call.
- 2.1 stays open (core archive-guard probe ongoing). 5.4 open (approval NONE;
  draft review ≠ approval). No non-English/iPad/montage, no pushes/deploys,
  no GitHub entities, no app/script/device actions.

## Docs pass 7 (2026-10-30, specs-docs — history CORRECTED, ISO dead end)

## Docs pass 8 (2026-10-30, specs-docs — localized 6.9in capture record)

- Tasks.md 6.3 marked PARTIAL with directly verified evidence: 8 external run
  manifests (ru/zh-Hans/es-419/pt-BR × r1+r2) all `complete`/`pending []`, 7
  native 1320×2868 PNGs each with matching sha256, iPhone 16 Pro Max iOS 27.0
  (`DCBAD85B`), Food `shot-cat-food 41400` live everywhere, ru week 12300 vs
  23100 (locale-native), deck totals match manifests. 6.5in pending; 5.4
  untouched (still done). Runbook "still missing" refreshed. No code, no
  commits, no GitHub entities, no device actions, no new ctx7 (budget still
  exhausted).

- Task 3.4 marked DONE (docs-verified, no app edits): reusable scenario
  `.argent/flows/history-notes-viewport.yaml` exists; History recaptured r1+r2
  at the notes viewport — r1 `b4cc904f…26df2` / r2 `d2da6b4c…af0e3`, native
  1320×2868, `history.json` shas match, read directly (Deep-work glyph
  visible, day totals present, Today labels out of frame by design).
- ISO-date probe is a DEAD END on this toolchain: `probes/lock-iso-probe.png`
  (`28b9c6b7…e311f`) still shows "Saturday, 1 January" on a bare lock screen;
  Jan-1 stays disclosed unless the owner accepts it or scopes a toolchain
  change. 5.3 stays OPEN for owner review of the corrected frames. Runbook +
  storyboard updated briefly. No code, no commits, no GitHub entities, no
  device actions, no new ctx7 (budget still exhausted).
