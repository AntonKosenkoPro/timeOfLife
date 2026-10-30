# Screenshot capture runbook (DRAFT — 2026-10-30)

Initial draft from agreed interfaces, revised as implementation lands. The runner
has an executable CLI (`scripts/screenshots/capture.py`) proven through two
full pilot runs on fresh DC79 — raw PNGs retained, teardowns complete — but
the pilot is a CAPTURED DRAFT under owner review, not approved output. Sections
marked **AGREED** record owner/spec decisions that are stable. Do not treat
this file as proof that capture is accepted — see
`openspec/changes/app-store-screenshot-pilot/` for the authoritative
proposal/design/tasks/specs.

## AGREED decisions (stable)

- **External retention root:** `/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`
  (owner decision 2026-10-30; holds pilot raw PNGs, text manifest copies, review
  sheets). Resolving location is NOT approval of any asset — task 5.4 still gates.
- **Capture build:** separate Release-optimized, simulator-only `Screenshot`
  configuration (owner-selected 2026-10-29). Normal Debug/Release and archive
  routing stay unchanged; capture on a physical device or archive fails explicitly.
- **Pilot scope:** English iPhone 1320 × 2868, five frames in story order
  (Track running → Insights → History → name picker → genuine Live Activity),
  **two consecutive full runs**. Owner pilot approval (task 5.4) gates the
  expanded 15-set / 75-frame matrix and the landing montage.
- **Review rules:** App Store 2.3.3 (app in use, not splash/login) and 2.3.9
  (fictional account info only); binaries never in git.

## Runner interface (PROVEN on the DC79 pilot — see evidence below)

First-pass runner source landed 2026-10-30 under `scripts/screenshots/`:
`capture.py` (actual CLI — **not** `capture_pilot.py`; do not document the CLI
surface as stable until the second pass), `executor.py` (lease-gated verbs,
`LIFIO_CAPTURE_LEASE=1` required for mutating calls), `request_schema.py`,
`pilot_manifest.json`, `expected_totals.json`, `approval.py`, `inspection.py`,
`output_guard.py`, `preflight.py`, `run_manifest.py`, `state_check.py`,
`evidence-runner.md`, plus `tests/` (131/131 green by direct run 2026-10-30 — cleanup-wiring tests added
since the 115 baseline).
All verbs are fake-adapter tested only; the capture executor has no real-device
proof, so tasks 4.1/4.2/4.4 are NOT complete (main review found
negative-validation bugs; fixes in flight). Teardown is at best partial until
the app-side session/activity hook lands — runner will not invent one
(`teardown-frame` persists a per-frame record; `finalize-run` requires teardown
records before complete). Nothing here has produced a real capture — treat every
interface below as provisional until runtime proof.

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
- **Required tests (planned):** Release ignores capture arguments and keeps the
  sign-in gate (Release-negative); capture cannot read/write production Keychain,
  App Group state, or network (isolation); runner rejects repository output
  paths, wrong geometry, missing frames; partial-run cleanup is scoped.
  2.4 proven at binary level 2026-10-30: ordinary-Release binary holds ZERO
  capture payload strings with the production BID; only `AppClock` type-name
  symbols remain (declared production default seam).
- **Cleanup contract (app hook exists in source, runner integration pending):**
  launch with `SCREENSHOT_CLEANUP=<run_id> SCREENSHOT_CLEANUP_SHA=<sha>`
  (values from the last `capture-state.json`); the app verifies both against
  that state, ends ONLY fixture-text activities, removes ONLY the named run's
  session dir + capture prefs, and writes `Documents/capture-cleanup.json`
  (`cleaned`/`mismatch`/`failure` — ack always written, runner never waits on
  silence). Verified in `ScreenshotCleanup.swift` 2026-10-30; runner-side wiring
  of the contract is now stable (exact ack, all phases fail-closed) — runtime
  4.x stays pending until QA proves it on-device. Current checks: 868 Debug /
  877 Screenshot / 131 runner, all green.

## Pilot inputs (PINNED in text manifest — visual acceptance still 5.4)

Pinned 2026-10-30 in `scripts/screenshots/pilot_manifest.json` (task 1.4,
verified field-by-field): Tuesday 2026-10-20 09:41 local · app-owned elapsed
12:34 (`app_elapsed_s 754`) · light appearance · standard Large Dynamic Type ·
en / US / America/Chicago. Live Activity frame uses a separate real-time anchor
(wall time minus elapsed offset), validated numerically, never pixel-compared.
Fixture totals are PINNED and cross-verified 2026-10-30 (`expected_totals.json`:
27 texts, text-sum 198600 == all_seconds, today 4500, week 23100) against
`ScreenshotFixture.swift` (task 3.1 definition done); the runtime app must
still compute + compare at capture time — the pin never replaces app validation.

## Core verification actuals (IMPLEMENTED 2026-10-30 — pilot since captured, see below)

Per `openspec/changes/app-store-screenshot-pilot/evidence-ios.md` (iOS worker):

- Builds/tests: Debug FINAL 868 tests/83 suites green; Screenshot FINAL 877/84
  with the gated capture suite executed green (preparation 55/links/totals/
  draft-exclusion/restart, week rule, isolation, container, cleanup paths,
  config-aware route proof); ordinary-Release build success + binary-negative
  proof; `swiftlint lint --strict` 0 errors.
- Clock-gated verification: DST calendar seam genuine RED pre-fix (EXIT 65,
  1/6, fix withheld) → GREEN 6/6 after a one-line fix; four older seam tests
  proven red ONLY retrospectively (pristine c3e5911 scratch BASELINE-RED 4/4,
  7 issues; identical assertions green on fixed tree). **Chronology rule:**
  cite the baseline as retrospective execution, never as original before-proof;
  task 1.3 stays open pending user waiver.
- QA/capture handoff: FRESH session sim `DC79DF29-708B-4928-91A9-8CD5B6352671`
  (screenshots BID only) is the current capture device — prior `E915572B-…`
  is test-only history. No PNGs claimed until QA returns frames. Shared
  iPhone 17 `C18365F5` had test-host install/launch contact from filtered
  runs — leftover state UNKNOWN, never touch or manipulate it.
- Base stays `c3e5911`; `origin/main` has advanced to `479a998` — rebase is
  PR-phase work, not claimed fresh.

## Pilot evidence (CAPTURED DRAFT 2026-10-30 — explicitly NOT approved)

Two consecutive full runs on fresh `DC79DF29-708B-4928-91A9-8CD5B6352671`
(screenshots BID only), in story order, every frame native 1320×2868. Root:
`/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`.

- `runs/pilot-r1/run-manifest.json` — status complete, `pending_evidence: []`
  (read directly): track `1dcacbe0…cb6b21d5`, insights `992ae012…79e0a9a8`,
  history `f2d76f4f…7a5a5df`, picker `8945cfd7…4e299d1da`, live-activity
  `8296fc8e…2a654216`.
- `runs/pilot-r2/run-manifest.json` — status complete, `pending_evidence: []`
  (read directly): track/insights/picker byte-identical to r1; history
  `961f7a49…d2fb697` (content-identical, 29.6kpx/0.78% island-edge shimmer,
  needs-inspection — do NOT quote superseded 675-pixel/2701-byte figures);
  live-activity `09b4bbe9…6590957` (real anchor `04:31:43-05:00`, captured
  `11:46:13+02:00`, observed 869 s vs wall 870 s, |diff| 1 s).
- `finalize-two-runs`: semantic equality, no errors; needs-inspection
  `[history, live-activity]` — owner clears per-frame with reviewer+date,
  never auto-passed. Disclosed as-is: NOT pixel-identical.
- Review sheets: `contact-pilot-r1.png` / `contact-pilot-r2.png` + JPEGs;
  `contact-pilot-r2-review.jpg` 2000x856, sha
  `e39c228713bb5ab8b5268228f2593a3df79355fa4bfd011fd135e8d1cb5a9a70`
  (read directly; first-derivative codec garbage fixed at root — contacts +
  JPEG rebuild — raws never touched).
- Teardown: 10/10 complete (cleaned acks, sessions removed, both LA ids
  ended, chrome restored); sim server stopped scoped to DC79.

Review blockers (open — 3.4 done, 5.3 owner review of corrected frames):
History notes viewport CORRECTED 2026-10-30 via the reusable
`.argent/flows/history-notes-viewport.yaml` scenario (no fixture change, no app
edits): r1 `b4cc904f…26df2` / r2 `d2da6b4c…af0e3`, both native 1320×2868,
Deep-work blue notes glyph visible, day totals present, Today/Yesterday labels
out of frame by design. Lock Screen "Saturday, 1 January" is a DEAD END on
this toolchain — ISO-date probe `probes/lock-iso-probe.png` (`28b9c6b7…e311f`)
still renders Jan-1 on a bare lock screen; disclosed native, no retouch; Jan-1
stays unless the owner accepts it or scopes a toolchain change. Picker Russian
secondary globe (active layout English — owner treatment call, not a bug).

Not begun: non-English decks, iPad sets, montage. No pushes, no deploys, no
binaries in git. Task 5.4 approval: NONE.

## Operator flow (executed for both pilot runs — procedure record)

1. Build Screenshot configuration; boot one capture-owned simulator at a time.
2. Snapshot prior appearance, Dynamic Type, keyboard, and status-bar state.
3. Run preparation pipeline; await `ready` (never sleep a fixed duration).
4. Capture five frames in story order at native resolution via
   `simctl io screenshot`; apply 9:41/battery/network overrides where supported.
5. Repeat for run 2; verify stable app content/totals across both runs.
6. Export named PNGs + machine-readable manifest to the external root;
   produce the external review sheet/contact sheet (binaries, outside git).
7. Scoped cleanup: end capture-owned activities, restore settings, clean only the
   known session directory. Never erase a shared simulator, never global kill,
   never touch another account's data.
8. **STOP at 5.4:** copy the complete pilot package to the external root, verify
   hashes, present retained frames + manifest, record explicit owner approval
   tied to hashes. No section 6/7 work before this.

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

## What is still missing (as of 2026-10-30, seventh docs pass — localized 6.9in captured)

- Localized 6.9-inch capture COMPLETE (tasks.md 6.3 partial note, manifests read
  directly): ru / zh-Hans / es-419 / pt-BR × r1+r2, 7 frames each, status
  complete, native 1320×2868, Food pin 41400 live, ru week 12300 vs 23100
  elsewhere. Still missing: 6.5-inch 1242×2688 sets, iPad sets, 6.5 clipping
  review, 6.6 final manifest + owner acceptance. 5.4 English approval unchanged.

- Owner review of the corrected History notes-viewport frames + remaining
  dispositions (Jan-1 dead-end acceptance vs toolchain change, globe treatment,
  history/LA variance clearing); 5.3/5.4 stay open — no approval inferred.
- Task 2.1 explicit archive guard (core probe ongoing; stays open until result).
- Task 3.4 DONE (scenario + r1/r2 notes-viewport recapture proven, no fixture change).
- Sections 6–8 (nothing begun); PR-phase rebase; 8.2 stays open until all
  current docs are coherent + strict validation passes.
