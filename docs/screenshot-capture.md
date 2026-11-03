# Screenshot capture runbook (2026-10-30 — English pilot 5.4-APPROVED; 6.6 pending)

Initial draft from agreed interfaces, revised as implementation landed. The runner
has an executable CLI (`scripts/screenshots/capture.py`) proven through the
7-frame iOS 27 pilot27 runs plus the iPhone/iPad expansion captures — raw PNGs
retained, teardowns complete — and the English pilot is OWNER-APPROVED (task
5.4, `runs/pilot27-r2`); expansion sets are captured-draft pending final
acceptance (6.6), the montage is deferred. Sections marked **AGREED** record
owner/spec decisions that are stable. Do not treat captured-but-unaccepted
sets as approved — see `openspec/changes/app-store-screenshot-pilot/` for the
authoritative proposal/design/tasks/specs.

## AGREED decisions (stable)

- **External retention root:** `/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`
  (owner decision 2026-10-30; holds pilot raw PNGs, text manifest copies, review
  sheets). Resolving location is NOT approval of any asset — task 5.4 approved
  the English 7-frame set only; task 6.6 still gates final acceptance.
- **Capture build:** separate Release-optimized, simulator-only `Screenshot`
  configuration (owner-selected 2026-10-29). Normal Debug/Release and archive
  routing stay unchanged; capture on a physical device or archive fails explicitly.
- **Pilot scope:** English iPhone 1320 × 2868 on the iOS 27 runtime, seven frames
  in story order (Track running → Insights → History top → Add entry →
  genuine Live Activity Lock banner + Island compact + Island expanded),
  **two consecutive full runs** (`runs/pilot27-r1` + `runs/pilot27-r2`).
  Owner pilot approval (task 5.4) is GRANTED for this set (Jan-1 date +
  device-local times accepted as disclosed; contact template approved) and
  gated the expansion captures; final fifteen-set acceptance (6.6) still
  pending, and the landing montage is deferred (built, external, not approved).
- **Review rules:** App Store 2.3.3 (app in use, not splash/login) and 2.3.9
  (fictional account info only); binaries never in git.

## Runner interface (PROVEN through pilot27 + expansion captures — see evidence below)

First-pass runner source landed 2026-10-30 under `scripts/screenshots/`:
`capture.py` (actual CLI — **not** `capture_pilot.py`; do not document the CLI
surface as stable until the second pass), `executor.py` (lease-gated verbs,
`LIFIO_CAPTURE_LEASE=1` required for mutating calls), `request_schema.py`,
`pilot_manifest.json`, `expected_totals.json`, `approval.py`, `inspection.py`,
`output_guard.py`, `preflight.py`, `run_manifest.py`, `state_check.py`,
`evidence-runner.md`, plus `tests/` (FINAL 149 green 2026-10-30 — 149 test
methods in-tree, corroborated by count; was 131 at the first interim).
All verbs are fake-adapter tested; the runner has since driven the real
pilot27 7-frame runs plus the iPhone/iPad expansion captures (teardowns
complete, manifests read directly — see evidence below). Tasks 4.1/4.2/4.4
stay open until the 7-frame/iOS 27 flow + evidence-sheet work lands per
tasks.md; teardown records gate `finalize-run` before complete. The
interface below is proven-in-use, not provisional — but captured never
implies approved (5.4 granted English only; 6.6 pending).

- **Capture app identity:** bundle ID `com.antonkosenko.timeoflifeapp.screenshots`,
  capture-only shared-storage namespace; ephemeral credentials; no production
  network/sync/crash/background services (attempts fail closed).
- **Request:** `Documents/capture-request.json` in the capture container, plus
  launch argument `SCREENSHOT_REQUEST capture-request.json`. Request carries
  schema/deck version, locale/region/timezone/calendar, reference date, state,
  expected totals/counts, treatment. Unknown or inconsistent input fails with a
  diagnostic — never silent fallback.
- **State:** atomic `capture-state.json` with statuses
  `preparing` / `ready` / `invalid` / `failure`, recording SHA, frame list,
  entry counts (~55 committed + separate running draft), expected totals, and
  real Live Activity metadata anchor (request ack, real start, capture
  timestamps, observed elapsed vs 2s tolerance).
- **Required tests (proven):** Release ignores capture arguments and keeps the
  sign-in gate (Release-negative); capture cannot read/write production Keychain,
  App Group state, or network (isolation); runner rejects repository output
  paths, wrong geometry, missing frames; partial-run cleanup is scoped.
  2.4 proven at binary level 2026-10-30: ordinary-Release binary holds ZERO
  capture payload strings with the production BID; only `AppClock` type-name
  symbols remain (declared production default seam).
- **Cleanup contract (proven through pilot27 + expansion teardowns):**
  launch with `SCREENSHOT_CLEANUP=<run_id> SCREENSHOT_CLEANUP_SHA=<sha>`
  (values from the last `capture-state.json`); the app verifies both against
  that state, ends ONLY fixture-text activities, removes ONLY the named run's
  session dir + capture prefs, and writes `Documents/capture-cleanup.json`
  (`cleaned`/`mismatch`/`failure` — ack always written, runner never waits on
  silence). Verified in `ScreenshotCleanup.swift` 2026-10-30; runner-side wiring
  of the contract is now stable (exact ack, all phases fail-closed) — proven
  through the pilot27 + expansion teardowns (10/10 complete on the English
  draft runs; expansion per-run teardowns recorded in tasks 6.3/6.4 with two
  r1 teardown flags + one 6.5 partial pending clearance at 6.6).
  Current checks FINAL 2026-10-30: 901 Debug / 914 Screenshot / 149 runner, all green
  (interim: 868 / 877 / 131; Screenshot 884 after the chrome-locale fix, 892
  after the appex Stop-language fix).

## Pilot inputs (PINNED in text manifest — English approved 5.4; expansion pending 6.6)

Pinned 2026-10-30 in `scripts/screenshots/pilot_manifest.json` (task 1.4,
verified field-by-field): Tuesday 2026-10-20 09:41 local · app-owned elapsed
12:34 (`app_elapsed_s 754`) · light appearance · standard Large Dynamic Type ·
en / US / America/Chicago. Live Activity frame uses a separate real-time anchor
(wall time minus elapsed offset), validated numerically, never pixel-compared.
Fixture totals are PINNED and cross-verified 2026-10-30 (`expected_totals.json`:
27 texts, text-sum 198600 == all_seconds, today 4500, week 23100) against
`ScreenshotFixture.swift` (task 3.1 definition done); the runtime app must
still compute + compare at capture time — the pin never replaces app validation.
Expansion decks keep the same timeline/durations with locale-native week rules:
ru/Moscow week 12300 s (Monday-first) vs 23100 s in en/zh-Hans/es-419/pt-BR;
today 4500, all 198600 everywhere; Food pin `shot-cat-food 41400` live in all
manifests (`openspec/changes/app-store-screenshot-pilot/decks/totals-<locale>.json`).

## Core verification actuals (IMPLEMENTED 2026-10-30 — FINAL counts below)

Per `openspec/changes/app-store-screenshot-pilot/evidence-ios.md` (iOS worker),
final handoff 2026-10-30:

- Builds/tests FINAL: Debug 901 tests green; Screenshot 914 with the gated
  capture suite executed green (preparation 55/links/totals/
  draft-exclusion/restart, week rule, isolation, container, cleanup paths,
  config-aware route proof, locale fixes); ordinary-Release build success +
  binary-negative proof; `swiftlint lint --strict` 0 errors. (Interim:
  Debug 868/83, Screenshot 877/84; 884 after the `ScreenshotLocale`
  chrome-locale fix, 892 after the appex Stop-language fix with
  `LiveActivityStringsLocaleTests`.)
- Clock-gated verification: DST calendar seam genuine RED pre-fix (EXIT 65,
  1/6, fix withheld) → GREEN 6/6 after a one-line fix; four older seam tests
  proven red ONLY retrospectively (pristine c3e5911 scratch BASELINE-RED 4/4,
  7 issues; identical assertions green on fixed tree). **Chronology rule:**
  cite the baseline as retrospective execution, never as original before-proof;
  task 1.3 recorded closed per the owner disposition in `execution-notes.md`
  ('Ok, record this' — future reproduce-before-fixing rule unchanged).
- QA/capture handoff (INTERIM record — superseded by the iOS 27 pilot27 +
  expansion runs in the evidence section below): at the time, FRESH session
  sim `DC79DF29-708B-4928-91A9-8CD5B6352671` (screenshots BID only) was the
  capture device — prior `E915572B-…` test-only history. Standing: shared
  iPhone 17 `C18365F5` had test-host install/launch contact from filtered
  runs — leftover state UNKNOWN, never touch or manipulate it.
- Base stays `c3e5911`; `origin/main` has advanced to `479a998` — rebase is
  PR-phase work, not claimed fresh.

## Pilot evidence (APPROVED 5.4 2026-10-30 — English 7-frame iOS 27 set)

Two consecutive full runs on the iOS 27 6.9-inch capture device (`SHOT Pilot
iOS27 16ProMax`), in story order (Track running → Insights → History top →
Add entry → LA Lock → LA compact → LA expanded), every frame native
1320×2868. Root:
`/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`.

- `runs/pilot27-r1` + `runs/pilot27-r2` — both status complete,
  `pending_evidence: []`; deck `en-austin-1`, treatment `light-v1`.
- Approval tied to the `pilot27-r2` frame `screenshot_sha256` values recorded
  in task 5.4 / `approval-pilot27-r2.json` (track / insights / history /
  add-entry / la-lock / la-compact / la-expanded).
- Accepted as disclosed at 5.4: Lock-Screen "Saturday, 1 January" date
  (9:41 time-only-override side effect; ISO probe dead end) and real
  device-local times on home-screen clocks. Contact-sheet template approved.
- LA timers validated numerically (≤ 2 s tolerance, never pixel-compared).

Prior iOS 18.6 5-frame draft runs (`runs/pilot-r1` + `runs/pilot-r2` on DC79,
picker frame, History notes-viewport) are SUPERSEDED drafts — detail
preserved in the `capture-QAevidence.md` body for the record, NOT approved;
never mix those runtimes/frames into the approved set.

Standing items for 6.6 (open): ru-r1 + zh-Hans-r1 `needs-inspection`
(la-expanded teardown incomplete — a capture-owned banner may still be
live); 6.5 run-manifests not yet built (frames+sessions only); iPad
two-runs `needs-inspection` (unreviewed_variance, owner-cleared); iPad
Add-entry Notes peek/hidden split (owner call); track-caption vertical
offsets in three cross-run pairs + zh-65 lock-wallpaper change (recorded,
disposition at 6.6); add-entry sub-perceptual jitter everywhere (not a
blocker). Picker Russian-globe question is MOOT — picker frame removed.

Not approved: anything beyond the English pilot27 set. No pushes, no
deploys, no binaries in git. Task 5.4: APPROVED (English 7-frame iOS 27);
task 6.6 acceptance: PENDING.

## Operator flow (executed for pilot27 + expansion runs — procedure record)

1. Build Screenshot configuration; boot one capture-owned simulator at a time.
2. Snapshot prior appearance, Dynamic Type, keyboard, and status-bar state.
3. Run preparation pipeline; await `ready` (never sleep a fixed duration).
4. Capture seven frames in story order at native resolution via
   `simctl io screenshot` (5 on non-Island targets — Island states N/A,
   recorded never fabricated); apply 9:41/battery/network overrides where supported
   (iPad: real-date status bar accepted, no override).
5. Repeat for run 2; verify stable app content/totals across both runs.
6. Export named PNGs + machine-readable manifest to the external root;
   produce the external review sheet/contact sheet (binaries, outside git).
7. Scoped cleanup: end capture-owned activities, restore settings, clean only the
   known session directory. Never erase a shared simulator, never global kill,
   never touch another account's data.
8. **STOP at 5.4 (CLEARED for the English set):** the complete pilot package
    was copied to the external root, hashes verified, retained frames +
    manifest presented, explicit owner approval recorded tied to hashes.
    Section 6 captures ran under that approval; section 7 montage stays
    deferred; final acceptance is task 6.6.

## Serialization and safety (standing rules)

- One `xcodebuild` and one capture simulator at a time (see
  `docs/ios-test-loop.md`). Core's exclusive lease was RELEASED with its
  2026-10-30 verification report (nothing running, nothing held); device calls
  now belong to the QA/capture session on the handed-off session sim — this
  docs worker runs no tests/builds/device calls, coordinate via main.
- `xcodegen generate` when `project.yml` changed — plus a FIRST generate in any
  fresh worktree (the generated project is git-ignored, so a fresh checkout has
  no pbxproj and plain `xcodebuild` fails with a baseline setup error, not a code
  bug); never hand-edit pbxproj. Baseline setup in this worktree is fixed
  (first generate done by core); fresh checkouts still need it.
- `git status` must show text/source only; screenshot/montage/test-result
  binaries stay outside git.

## What is still missing (as of 2026-10-30, eighth docs pass — 5.4 approved, expansion captured)

- Task 6.3 PARTIAL: 6.9-inch iPhone sets COMPLETE (en approved pilot27 pair +
  4 non-en locales × 2 runs × 7 frames, manifests `complete` except ru-r1 +
  zh-Hans-r1 `needs-inspection` teardown flags); 6.5-inch sets captured (4
  non-en locales × 2 runs × 5 frames + valid en-65 pair, island N/A by
  design, Lock banner present; run-manifests not yet built; one la-lock
  teardown `partial`). Still open: r1 teardown clearance + two-complete-runs
  clearance + 6.5 manifest assembly. 5.4 English approval unchanged.
- Task 6.4 DONE (capture completeness only): all five locales × 2 runs × 5
  frames on iPad13, manifests `complete`, native 2064×2752, Island-N/A probes
  per run. Task 6.5 DONE: iPhone no clipping in any locale/size; iPad Notes
  peek/hidden split left as owner call; 13 mini + SE3 XXXL fit checks not
  rerun (no new app-visible copy since Oct-27 checks, prior evidence current).
- Task 6.6 OPEN: final fifteen-set manifest + review reports still need owner
  acceptance (draft manifest verified in external run dirs — 170 PNGs, 32
  contact sheets, sha-match clean — but NOT owner-accepted).
- Montage DEFERRED (7.x): built asset retained externally, not approved, no
  `web/` change.
- Task 2.1 explicit archive guard, task 3.4 frame scenarios, tasks 4.1–4.4
  runner/evidence extension stay open per tasks.md. Task 8.2 closes with this
  docs pass; 8.1/8.3/8.4 stay open (final verification, git-purity + external
  handoff, issue updates + PR-phase rebase).
