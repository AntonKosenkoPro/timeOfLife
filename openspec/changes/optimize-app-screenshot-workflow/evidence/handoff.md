# Handoff — optimize-app-screenshot-workflow (compaction checkpoint)

## Private-Release checkpoint 2026-11-04 (sole-writer commit next; NO auth-success claim)

- Private source `AntonKosenkoPro/lifio-design-assets`, live `apple-bezels-v1`: `https://github.com/AntonKosenkoPro/lifio-design-assets/releases/tag/apple-bezels-v1` — git text-only README+manifest, 3 PNGs Release-assets only (no PNG in git, no raw bezels in public ZIP, no Figma/API/DMG in CI).
- Pins: manifest SHA256 `a9b21ed8…ffaaad` (full `a9b21ed835d7a231088e2a3249e8cfcc42b92162dfec3dcbc870c34ee6affaad`); assets `171f0a39…52792a` (17PM Silver 1470×3000), `fb93a0b6…7006a` (17 White 1350×2760), `0565de2d…074c4024` (M5 13" 2300×3000); cavities 1320×2868@(75,66)/1206×2622@(72,69)/2064×2752@(118,124) — staged 3/3 hash+geometry PASS (`/tmp/lifio-audit-1104-final`).
- Secret `APPLE_BEZELS_TOKEN` (main-chosen): fine-grained read-only Contents on asset repo ONLY — CONFIGURED per owner, METADATA-verified via `gh secret list` 2026-11-04 (name+timestamp only, value never read); authenticated CI download NOT yet run — 10.4 stays PARTIAL, no false green; `GITHUB_TOKEN` still cannot cross repos, no copy from broad `gh auth`.
- Independent tooling PASS (same audit dir, clean venv no PIL): screenshots **510 OK/1 skip**, panels **126 OK/3 skips**, contracts **51**, actionlint clean, strict `openspec validate` pass. iOS separate: Shot **1135/103**, Debug **1051/98**, lint **0/255**; 17PM declared-source (7113-dirty) 4 PNG native 1320×2868 + 2 receipts LA honest-pending; 17/M5 local capture blocked on legit missing approval pair — NO local bypass.
- Round-1 ledger CORRECTED to **25 addressed/6 waived = 31** (3477 waived→fixed); existing GH thread replies updated by main after push. Unreadable-command fix retains file for next poll under existing HOST deadlines (no simctl retry, comments corrected); `.serialized` only fixture-path op isolation; exact CI test root UNKNOWN.
- Tasks **42/49**, open **8.3/8.6/9.5/9.6/10.2/10.3/10.4** — await actual CI + human new-template approval; full CI must still prove 3-geom/multilingual/private-read/PUBLIC HANDOFF ZIP (no raw art). Diff scoped only (26 modified +1 new stager +1 deleted fetcher, no secrets values/binaries/unfamiliar work). Base `origin/main 009b0d25`, HEAD `7113ea92`.

## Current local PASS + pilot proof 2026-11-04 (cutover pending; NOT CI acceptance)

- Checklist **41/45**, open **8.3/8.6/9.5/9.6** — remaining gates stay OPEN.
  No merge/archive/human approval claimed; planned CI acceptance NOT accepted
  from these local results.
- Full independent local green (main-reported, unit/structural scope only):
  screenshots **504 OK (1 retained-genuine-source skip)**, panels **107 OK
  (3 retained-source skips)**, contracts **48**, actionlint clean, strict
  `openspec validate` 4 changes pass. iOS **Screenshot 1134/103**
  (`/tmp/ios_full_shot.log`), **Debug 1051/98** (`/tmp/ios_full_dbg.log`),
  `swiftlint --strict` **0/255**; backend `gofmt`/`vet`/`build`/`test` +
  `golangci-lint 0 issues` green
  (`/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/backend-verify-pr235.log`).
  No native/CI single-pass acceptance follows from those results.
- Native English single-pass pilot proof (manual invocations, NOT CI):
  `/tmp/ios95-A.log` (`EXIT=0 WALL=46s`, invocation `15d21735061a`) +
  `/tmp/ios95-B.log` (`EXIT=0 WALL=30s`, invocation `faee97d6afc0`) with
  `.done` markers; roots `/tmp/ios95-A/` + `/tmp/ios95-B/` (iphone69/en,
  single r1-labelled pass each). Each run: 4 native app PNGs
  (track-running/insights/history/add-entry, `native-simctl` + macho
  `8625f5de…`) + 3 LA `external-lock-screen-pending` stubs, 2 session
  receipts (pinned 4-frame + realtime 3-frame, distinct session nonces per
  run, `complete` + `lease_released`). Statuses `ok` with honest
  `needs-inspection` LA reason AND explicit **undeclared source-provenance
  limitation** (`provenance not declared (commit base + dirty flag
  required)` in `iphone69-en-r1.status.json`) — do NOT retrofit historical
  receipts. Manual-rerun identity proof only (same inputs, new run identity,
  no state carryover claimed at pilot scope); three-geometry + multilingual +
  delivered-ZIP inspection remain 9.5/8.3 open.
- This cutover commits the uncommitted single-pass + 31-finding review
  hardening (24 addressed/7 waived ledger; 24 fixes must be pushed before
  their threads resolve) as one atomic review+singlepass unit — review and
  single-pass edits interleave in the same files (e.g. `executor.py` locale
  binding + spawn/receipt hardening, `ScreenshotSessionController.swift`
  single-pass wording + rejection-identity ack), so no clean two-commit split.
  Base at commit time `origin/main 009b0d25`; rebase/push gated below.

## Active single-pass revision checkpoint (supersedes earlier two-pass gates)

- Owner explicitly approved removing automatic r2/comparison and accepts about
  22 minutes versus 70+; 20 minutes is aspirational. Proposal/design/delta/tasks
  and operator docs revised. Old hard cold/warm tasks 8.1/8.2 are retired plain
  historical bullets, not fake passes. Current checklist **41/45**, open
  8.3/8.6/9.5/9.6. Single-pass changes are still uncommitted/unpushed;
  remote PR head remains 26b7c1e1 until publication.
- Worker single-pass implementation and unchanged shared-build contract are
  unit-verified (9.1/9.4 checked). Fresh invocation-bound run IDs, stable status
  filenames carrying actual IDs, pre-side-effect composite-length validation,
  refusal of any nonempty selected output cell; no overwrite or automatic r2.
  Owned suites 138 tests pass, screenshot actionlint clean. No native/CI
  single-pass acceptance follows from those results.
- Comparison CLI/function removed, single-plan utility corrected, semantic
  hashes retained for human comparisons. Malformed panel status pointers now
  fail closed, README/panels use one selector, and locale binding is verified
  against hash-bound archived envelopes. End-to-end cross-locale negative proof
  confirmed the original defect and now blocks. Owner full suites: screenshots
  504 OK (1 retained-genuine-source skip), panels 107 OK (3 retained-source
  skips). Tasks 9.2/9.3 checked at unit scope; final independent integration
  rerun belongs to ses_e597bc577ffe9NrRhY87Do51Uc, native English pilot/manual
  rerun proof to ses_e59878b29ffeKtHBN3aIIyBnhR. Native/CI acceptance still open.
- B owner ses_e5989c014ffeeoH5mSxXS9xvye owns executor/session/capture/finalizer
  and tests; C owner ses_e5980f8ddffe4PcBC568RJYyB7 owns panel selection/README
  and tests. A worker ses_e59878aeaffeg4e6sHHbip6KVS has finished. No other
  writer may overlap these files. Main owns task/checkpoint writes.
- Review run 41816179098: 31 findings reconciled against 31 threads; triage
  ledger 24 addressed/7 waived (mixed findings counted once as addressed).
  Seven waivers replied and resolved; 24 fixes must be pushed before their
  threads resolve. iOS final verification 1134/103 Screenshot, 1051/98 Debug,
  lint 0/255; backend fresh verification green. Source changes after these
  results require affected reruns. No merge/archive/human approval claimed.
- Independent pre-audit integration suites passed 494 screenshot tests
  (1 genuine-source skip), 97 panel tests (3 retained-source skips), but exposed
  gaps despite green tests. Do not cite those green counts as final acceptance.

## Pending-3 fix checkpoint 2026-11-04 (approved for PR235, sole-writer commits)

- Scope preserved: exactly the 3 approved files, no unfamiliar writes
  (`git diff --check` clean): `ScreenshotSessionTests.swift`
  (payload-once byte-identity fix) + `executor.py` /
  `test_session_run.py` (cleanup-spawn protected exception accounting).
  No behavior changes outside this reviewed diff; no test reruns here
  (source unchanged since main-verified runs); no dispatch from this unit.
- These fix OUR bugs, not the underlying simctl stalls. Latest retry
  41817895686 still failed iphone63 appearance 60s and ipad cleanup 60s;
  the previous overall-transient claim is WITHDRAWN. No complete-ZIP claim.
- Swift: Foundation unsorted serialization differed 5/30 processes; test
  re-serialized instead of hashing transmitted bytes. Fix passes one
  payload through both nonces and asserts byte-identity hash. Main-verified:
  full Screenshot 1132/103 + lint clean.
- Python: cleanup `simctl launch` hang escaped bare (red: 0 receipt, lease
  leaked — 41817895686 ipad13-en-r2 shape). Fix moves the spawn inside the
  fail-closed region: appended failure, partial receipt + session record
  with completed transcript, lease released, prior failure preserved first.
  Main-verified: red→green on the new cases; full 467 OK / 1 skip; focused
  28/24/38/24 + contracts 45.
- Research: ctx7 `/websites/developer_apple_foundation` query
  `JSONSerialization WritingOptions sortedKeys` (key order unspecified
  without `.sortedKeys` — fix avoids relying on it); internal Python
  exception-accounting waiver (spawn protection stays internal
  fail-closed, no new external API).
- Tasks 8.1/8.2/8.3/8.6 stay OPEN; ~22min performance accepted by user, no
  further speed work; formal planning untouched. Main schedules a
  diagnostics experiment next, not a blind retry.

## Dry-run fixes checkpoint 2026-11-04 (verified, sole-writer commit next)

- Cold dry run (~22min vs 70+; user explicitly accepts, no further speed
  optimization requested) still produced NO successful final ZIP. Two root
  causes, both fixed and verified; no source re-verification needed here
  (unexpected source would require reruns — none found: exactly the 7
  expected files, no unfamiliar work).
- Root cause 1 — capture: host `simctl ui appearance` hung 60s past the
  runner timeout (iphone63/ru-r1 mirror) while the receipt claimed
  `complete` for a truncated 1-of-4 transcript with zero failures.
  Fix (`scripts/screenshots/executor.py` `_counted`): spawn failures
  (`TimeoutExpired`/`OSError`) raise fail-closed `FrameError`, so
  `run_session` receipt accounting records partial + named failure;
  cleanup/restore/lease still run. Tests: 2 new in `test_session_run.py`
  (timeout-at-export-verify, oserror-at-snapshot).
- Root cause 2 — packaging: pinned iPad Figma node renders landscape
  3000x2300 vs owner-approved portrait 2300x3000 — REJECTED as drift;
  no unapproved asset rotation/pin, no geometry relaxation downstream.
  Fix (`app-screenshots.yml` + panels): fetch fails closed with the exact
  drift message and keeps verified iPhone bezels; Render/Write/Upload each
  pin their own `if: "!cancelled()"` so a red fetch still yields a
  failure-path debug ZIP (partial panels + matrix manifest + bezel-fetch
  log + shots) with loud copy/missing-transcript guards; README inventories
  `bezel-fetch*` with sha256. Tests: 2 new in panels `test_matrix.py`
  (landscape-drift partial bundle, readme log inventory) + 4 new in
  `test_workflow_contract.py` (cancelled-gating, diagnosable fetch,
  loud copy, pins/scale preserved).
- Tests (main-verified dry run, reproduced before/after): screenshot suite
  465 OK / 1 skip (459+2+4), panels 91 OK / 3 skip, contracts 45,
  actionlint clean. No further tests run in this commit unit.
- Tasks 8.1/8.2/8.3/8.6 stay OPEN; PR #235 stays draft (observed
  non-draft at commit time — flagged for main; no state changed here).
  No iOS edits, no secrets/binaries (`git diff --check` clean; only the
  pre-existing `secrets.FIGMA_API_KEY` ref), no threshold changes.
  Main schedules the clean retry; no screenshots/dispatch from this unit.

## PR and failed cold-run checkpoint (supersedes precommit status below)

- PR #235: https://github.com/AntonKosenkoPro/timeOfLife/pull/235 (draft).
  Implementation commit 3594c8d3 rebased cleanly onto origin/main 009b0d25;
  test-only tooling CI fix c5c7773c is pushed. Human author identity and agent
  attribution preserved. No merge or archive.
- Mandatory PR checks pass on c5c7773c: backend-gate, ios-gate, tooling-tests,
  panels-tests, and OpenSpec. Final local post-rebase Debug1051/98,
  Screenshot1132/103, Release simulator build, backend and tooling checks pass.
- Cold full default run 41813403434 FAILED. Dispatch 10:19:27Z, final failure
  10:41:23Z (~21m56s; NOT final-ZIP timing). Shared build, iphone69, ipad13
  succeeded; iphone63 Capture locales failed, then panels Fetch Apple bezel
  assets failed. No final ZIP. Tasks 8.1/8.2/8.3 remain open; no cold/warm
  runtime acceptance. No warm dispatch before fixes.
- Failure owners: Python capture ses_e59d50d17ffeXmzQ56N3ctmrK5;
  panels/workflow ses_e59d50cecffeS7gT6NNBJFRfOZ;
  iOS read-only diagnosis ses_e59d50cadffei0lnql8aNWy6I7.
  Main owns checkpoint/tasks; no fix may relax deadlines, geometry, cleanup,
  genuine-evidence, or approval gates to obtain green output.
- Stage-1 AI review triggered by comment 6628698621; collector
  ses_e59d6b4baffeaGfnCn3raMQQbr owns run-ID-based reconciliation. Do not
  mark ready before mandatory checks and the reconciled review/thread gates.

## Precommit checkpoint 2026-11-04 (sole-writer commit + rebase; supersedes stale status prose below)

- Checklist **37/41**; open **8.1/8.2/8.3/8.6** (8.6 held for post-rebase reruns/handoff — do not check it here).
- Base `bd126664`, one behind `origin/main` `009b0d25` (#234: panels `--scale 2` + `fetch_bezel_assets.py` default 2; no other drift). Rebase next; expected touchpoint is the panels bezel-fetch line in `app-screenshots.yml` (keep session pipeline, adopt `--scale 2`).
- Precommit docs reconciliation done: `docs/ci.md` (6.x/8.5 still-pending → 6.x, 7.x + 8.5 done at unit/structural scope), runbook title/`Legacy removal` 8.5 ACTIVE→DONE/Swift-DONE/`Status` still-open list/`(8.1/8.2)` → 8.1/8.2/8.3 (+8.6), `Design/SCREENSHOTS.md` count 25/41→37/41 with archived-pilot-scope note, tasks 8.5 comment-cleanup queued→complete. Historical evidence untouched.
- Guards pass: no secrets (only `test-token` fixture + pre-existing backend PEM checks), no binaries (text/source only; largest untracked ~96 KB test file), no unfamiliar files (all ~60 in capture/openspec scope; `ScreenshotCaptureFlow.swift` + `test_executor.py` deletions are the intended 8.5 removal).
- No push/PR from this unit; main coordinates post-rebase parallel verification next. No tests run here by instruction.

Date: 2026-11-04. Active implementation checkpoint; implementation is uncommitted.
Context budget: user reminded compaction before 250K; repo rule stricter at 200K.

## Current recovery checkpoint (supersedes historical notes below)

- Authoritative checklist is **37/41**. Open:
  8.1, 8.2, 8.3, 8.6. Earlier planning-only, 4/41, 32/41, 34/41, 35/41, 36/41, unwired-YAML,
  and `HEAD==origin/main` statements below describe earlier snapshots only.
- No commits, pushes, workflow dispatches, or merges. The worktree has uncommitted
  implementation; the docs audit reports the base is one commit behind origin/main.
  A later rebase and affected verification remain required before a PR.
- Recovery screenshot run reproduced one approval-gate test failure: 459 tests,
  one failure, one skipped. The test relied on owner-specific paths unavailable
  in the current environment. The production gate was correct and unchanged.
  Its test now supplies temporary synthetic path fixtures to the mocked children;
  these are not owner approval or real evidence.
- Post-fix full screenshot discovery: **459 tests, OK (skipped=1)**, 64.301s,
  independently checked in the external log
  `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/screenshot-recovery-verify.log`.
  This includes the restored missing-provenance regression and eight modeled
  oversubscription tests.
- Independent tooling review is complete: screenshots 459 tests OK (1 skipped),
  panels 89 tests OK (3 skipped), contracts 41/41, oversubscription 8/8,
  legacy-removal 3/3, actionlint v1.7.12 clean. External final logs:
  `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/screenshot-full.log`
  (66.094s) and sibling `panels-full.log` (89.089s). Skips require genuine retained
  LA PNGs (one screenshot test), retained v13 sources (two panel tests), or
  retained ipad-v1 sources (one panel test). Tasks 7.3/7.4 are closed at the
  unit/structural boundary; no live CI timing or genuine evidence is implied.
- Strict OpenSpec validation passes; docs/spec scope audit found no new binaries
  or unrelated baseline/landing/backend changes and no relevant FURPS conflict.
  Task 8.5 still needs final Swift removal verification.
- Recovery final reports received: 6.4 real local verified artifact installation
  on all three device types passes (`/tmp/s64_artifact/report-6.4.json`), and
  7.1 backend formatting/vet/lint/build/tests pass (external
  `T/opencode/backend-verify-20261104-105927.log`). Both tasks closed.
- Post-removal Screenshot 1132/103 and Debug 1051/98 tests pass, but a full
  recompile reveals a project ActivityState switch warning in ScreenshotApp.swift.
  Earlier warning-clean claim is withdrawn and 7.2 reopened. New exclusive iOS
  owner `ses_e5a07c6a7ffeUn31XBgR58OGC2` investigates a compatible fix; no other
  worker is active. Historical pending-owner descriptions below are superseded.
- Warning resolved: ActivityState equality checks preserve prior cleanup behavior
  without newer-SDK case references or diagnostic suppression. Final iOS owner
  `ses_e5a0247d8ffe7ZwYErB61ZFMpW` confirms strict lint 0/255, Debug 1051/98
  (19.135s), Screenshot 1132/103 (33.544s), no Swift warnings/errors. Warm builds,
  not a fully cold claim; two Apple AppIntents tool notices separately disclosed.
  Task 7.2 reclosed; iOS portion of 8.5 passes. Final non-iOS removal validation
  remains with `ses_e5a024798ffer0BdkZjSxm9guq`.
- Final non-iOS removal validation received: strict OpenSpec valid, screenshots
  459 OK (1 skipped), panels 89 OK (3 skipped), legacy 3/3, contracts 41/41,
  screenshot actionlint clean; scope/binary/FURPS audit passes. Task 8.5 closed.
  Repo-wide actionlint still reports the unrelated pre-existing backend.yml:383
  finding. Comment-only cleanup of three misleading comparison/legacy docstrings
  in executor.py is complete (`ses_e59fdc8e5ffeuTNFSzut3MQXkC`); legacy tests
  3/3 and syntax validation pass. No runtime fallback remains.
- The earlier explore review stalled on provider HTTP 503 overload; inactive
  sessions and stale `succeeded` outcomes are not final verification evidence.
- Current owners: iOS recovery `ses_e5a375914ffeFaoGXkn4aLETGu` (exclusive
  xcodebuild/simulator owner); backend verification `ses_e5a3758eaffe9ccKsOF0yorirQ`
  (gofmt/vet green, build/lint/test background results pending); Python/workflow
  verification `ses_e5a36d714ffeMrWgLR2aUjM2yd` (suite/panels/actionlint and
  independent oversubscription review). Main owns checklist/checkpoint writes.
- Full cold/warm CI timings, delivered CI ZIP inspection, and final rebase/handoff
  remain open. Local pilots and a modeled queue do not establish CI performance,
  genuine Live Activity evidence, or owner approval. Obtain authorization before
  publishing the uncommitted branch and dispatching remote acceptance runs.

## Historical gate state: 32/41 — superseded by the recovery checkpoint above

- [x] 1.1 rebase + ctx7 refresh (HEAD==origin/main==bd126664; research in
  `evidence/research.md`; protocol waivers recorded).
- [x] 1.2 slow-workflow repro (run 41718031322 attempt-1; no drift; panels attempts
  distinguished; details in `evidence/baseline.md` §1.2).
- [x] 1.3 BASELINE DONE 2026-11-04, independently verified by docs owner (14/14
  native PNGs + sha-bound records, 14/14 teardowns complete, needs-inspection LA
  honesty, sim deleted; `evidence/baseline.md` §1.3). Baseline build/sim lock
  RELEASED — implementers may proceed per resume order below.
- [x] 1.4 requirements re-check (no conflicts; `evidence/research.md` §3).
- Frozen protocol (planning-only, 2.3 NOT implemented): `evidence/protocol.md`
  + design §4 clarification link. Swift + Python owners AGREE, no blockers.

## Serialization (single-writer resources) — updated 2026-11-04

- Baseline lock RELEASED: `OPT-BASELINE-69` deleted after the run (verified absent
  via `simctl list`); `shot-baseline/build.log` shows BUILD SUCCEEDED; no xcodebuild
  running. Shared iPhone 17 `C18365F5` was never touched.
- Implementers resume under normal serialization: one `xcodebuild`, one simulator,
  single-writer files per AGENTS.md.
- No polling agent progress; no foreground wait >60s (background log + 60s poll only).

## Ownership (active implementation — updated post-1.3)

- iOS worker exclusively owns local build + tests + its fresh sim (one `xcodebuild`,
  one simulator at a time; DerivedData lock respected).
- Python runner: NO sim; owns scripts/screenshots protocol/executor/finalizer + golden
  vector(s) first + shared `session_evidence` pure helper.
- Workflow: 6.1–6.4 pure helpers only (validation, build/provenance, caching, tar
  manifest, contract tests); 6.5 rewire + 6.6 still PILOT-gated (no device-matrix
  cutover before 5.x).
- Milestone 2026-11-04 (evidence only, NO 6.x close): `workflow_inputs.py` +
  `build_artifact.py` + `workflow_artifacts.py` landed with tests (initial 54 green);
  parent-review findings (macOS/iOS layout, dir symlinks, manifest schema/IDs,
  hardlink/alias/collision handling, cache-must-not-skip-build) fixed red→green
  (32 errors + 7 fails → 37 OK, suites green); manifest xcode/sdkbuild optional until
  integration pins them; wiring + audit still pending — see `evidence/helpers.md`.
  Audit 2026-11-04: no blocker (68/68; real-iOS 73 files/0 links; N1 traversal proven
  then fixed via strict status validation; targeted 73 OK, 12 suites green) — still
  helper-only, pending early CLI/golden/session-helper/pilot. Tasks stay 4/41.
- Runner milestone 2026-11-04 (evidence only, NO 2.x/4.x close): `session.py` +
  `session_evidence.py` + `run-session` CLI landed (fake-adapter; owner reports 368
  OK + 1 skip, 57 new scoped tests); 2 golden vectors ready, `validate_run_evidence`
  API ready; gap: `finalize_run` not receipt-gated (owner working it); old per-frame
  verbs retained temporarily (remove in 8.5); Swift has golden contract, panels on
  6.7 consumers, workflow thinning device-worker loop (YAML pilot-gated) — see
  `evidence/runner.md`. Dependencies now integration/test/pilot, not missing helpers.
- Device-worker checkpoint 2026-11-04 (evidence only, YAML unwired/pilot-gated):
  `run_device_worker.py` 24/24 green (red 7+7 prior); per-locale `shots/<dev>/<locale>`
  + summary at `shots/<dev>`; OSError/Timeout → failed + contaminate-stop, KI records
  then reraises, summary-write fail visible, pair-failure `effective_complete=false`;
  worker `--out`=shots root vs capture `--out`=pair root; `test_session_run` 1 error
  in latest snapshot — suite NOT green. Full detail in `evidence/helpers.md`.
- Panels-consumer checkpoint 2026-11-04 (evidence only, NOT 6.7/4.x done): builder +
  readme + matrix/panels tests landed (78 green after red 6-of-9 + README gate);
  strict helper call, whole-cell pending block, COMPLETE-vs-HANDOFF labels (not
  approval); blockers: finalizer gate, 7-frame assemble, iPad combination + real
  capability attestation (model/geometry/nonce) with helper consolidation. Detail in
  `evidence/panels.md`. Snapshot 4/41.
- Runner finalizer checkpoint 2026-11-04 (owner-reported 428 OK+1 skip; probe schema
  verified present; real-probe + cross-lang proof still pending; red-by-inspection
  caveat recorded; legacy branch 8.5-removal noted) — detail in `evidence/runner.md`.
  Independent Python audit + panels consolidation started; Swift ack forwarded.
- Audit 2026-11-04 (NOT acceptance, 4/41): 433 tests 1 FAIL (device_key loss);
  REAL blockers — manifest-invention accepted, phantom model/UDID open, schema-999
  ack accepted; runner+panels assigned fixes; missing-probe/subset verified fixed
  only; record in approved tmpdir, mid-review fingerprint caveat. See
  `evidence/runner.md`.
- Fix candidates 2026-11-04 (owner-claims 447 OK+1 skip; all 4 audit findings pending
  independent re-verify; A1/A2 re-run reject claimed; auditor + panels reruns
  restarted; Swift build/pilot/cross-lang still out). 4/41.
- Reaudit 2026-11-04: ALL original findings CLOSED at unit-code level (447 OK+1 skip,
  executed cases, fingerprints + record addendum in `evidence/runner.md`); follow-ups
  F1 (genuine-external CLI wiring) + F2 (whole-manifest complete check) open. Still
  no Swift/real-pilot. 4/41.
- Panels consumer 2026-11-04: 87 green (48+39), audit negatives + split-harness
  resolved, iPad anchor untouched; full 6.7 still needs packaging integration.
  Runner 455 OK+1 skip but CLI identity optional → strict-ack fix assigned, handoff
  not accepted. Backend verify on separate agent parallel to Swift (owns its
  build/tests; final report pending → 7.1 stays open). Swift proof still out. 4/41.
- Swift milestone 2026-11-04 (independently verified): controller + 31+3 tests,
  1112/1112 green, red logs, executed cross-lang golden; 2.2/2.3/2.4 MARKED (7/41).
  Open: 2.1 (counters scope), 3.1 (mount-order/migration/seed proof), 3.2 (resets),
  3.3 (per-command revalidation), 3.4 (unmounted/nav/geometry negatives), 3.5 (no
  ru→zh→es/pt sequence), 4.3/4.4 (queue leftovers), 4.7 (Release side), 5.1
  (same-RID r2). `.task(id:)` ctx7 refresh asked of owner. See `evidence/swift.md`.
- Follow-up 2026-11-04 (5.1 NOT closed): 69s vs 114s owner-reported; 20 PNGs
  (14 canonical verified 1320×2868 + 6 staging, hash canonical only); same-RID both
  domains ✓ but SIM identity unproven (16PM vs 18PM, files carry no attestation);
  cleanup fix owner-reported but runner drops `removed_session_queue` (verified by
  grep) → 4.3/4.4 open till retake; 2.1/3.x/4.7 unchanged open. 7/41. Backend final
  report still pending (no polling).
- Identity 2026-11-04: pilot sim was ACTUAL 16PM (SES1116, UDID 3B806C6D-…, now
  deleted); 1320 geometry proves nothing; 69s EXPLORATORY NON-EQUIVALENT, 5.1 OPEN
  for 18PM retake (old receipts never retrofit). Verif: Screenshot 1112/102 only;
  Debug subset only; Release untouched. Missing: 3.3 store-mutation, 3.1 sync
  injection, 3.5 multilocale; 3.4 partial (stale-ignore + mount-timeout proven).
  Swift RELEASED, no build/sim till runner contracts final. 7/41.
- 5.1 MARKED 2026-11-04 (independent audit; inventory SHA d5a63e00, 62 files,
  hash-verified): 59s accepted (63s rejected), ~48.2% local-warm only, no
  reduction claim, PIL visuals, owner 0% withdrawn. 4.3/4.4 LEFT OPEN with reasons
  (handles/preferences + F2 + real-failure proof unverified); 5.2 OPEN (panels-owner
  inspection next). 8/41.
- Proper-18PM pilot 2026-11-04 (verified-what-only, 5.1 OPEN): 28 PNGs (14 canonical
  verified 1320×2868 + 6 staging + 8 owner diffs); device UDID/model VERIFIED in
  records; receipts now bind queue-key + runner_verified (strict-vs-passthrough for
  auditor); hash-duplication flag recorded unresolved; timing/suite claims
  owner-reported (106-vs-1080 scope invalid); 4.3/4.4/5.1 candidates pending audit;
  5.2 needs only the inspection diff itself. See `evidence/swift.md`. 7/41.
- Accountability 2026-11-04: owner RETRACTED stale-16PM-derived parts (hash
  inventory, variance/bboxes, viewed images, status contents, 106-vs-1080);
  corrected ~60s + hash list MATCHES docs' independent hashes (values confirmed,
  not acceptance); 5.2 fresh-image inspection gap till auditor inspection (no new
  capture needed). No closures. Owner paused, no sim held. 7/41.
- 5.2 MARKED 2026-11-04 (fresh native inspection by panels owner, honest-LA only):
  4 frames verified + SHAs + 6/6 LA pending-with-reason; 'blocked as a set' is a
  panel-completeness phrase, NOT a 5.2 gate; genuine-LA + owner-approval gates stay
  explicitly open. 4.3/4.4 stay OPEN pending focused source verification (fake
  injection + real happy receipts can suffice — no unrequested real-device failure
  injection). 9/41.
- 5.4 BLOCKED pre-device 2026-11-04: worker lacks approval/retained-dir plumbing;
  approval file verified present (`approval-pilot27-r2.json`, gates non-english +
  ipad, 7 hashes); worker owner to validate + plumb optional paired flags (no
  bypass/fabrication/mutation); Swift RELEASED, zero expansion sims/build.
  Unblock: validation + plumb → explicit Swift resume. See `evidence/helpers.md`.
  13/41 confirmed (4.3/4.4 marks already applied).
- 3.5 + 4.6 MARKED 2026-11-04 (frozen-final audit): inventory self-hashed
  (152 entries, complete scope corrected); 8/8 native headers; M4 probe + N/A
  fulfilled; 5.4 native eligible but HELD for timing/binary-extension audit;
  no same-UDID claim; extension-SHA note not a 3.5 blocker. 24/41.
- 7.2 + 4.5 MARKED 2026-11-04: fresh strict lint exit 0 (256 files, post-final,
  UTC/local consistent, no-drift SHA); full CURRENT suites + Release SIM build
  green (toolchain warnings audited); F1 CLI wiring with executed CLI/tolerance/
  probe suites + real one-anchor receipts. 3.5/5.4 remain frozen-retake pending;
  backend 7.1 awaits final report. 22/41.
- 5.4 MARKED 2026-11-04 (audit PASS, inventory self-verified 361 files): timings
  108/122/236, source/app/appex/SDK verified; '80 PNG only' rejected, exact scope
  recorded. HOLD 6.x for integration-gap fixes (SDK/toolchain/LCA/statuses/ZIP/
  resource-map/drift) + real 6.4 install + actual CI. App freeze unchanged. 25/41.
- 8.4 MARKED 2026-11-04 (5 docs coherent with wired YAML/helpers, verified CLI
  paths, inventory truth consolidated, unmet 8.1/8.2 cited; 6.x held, 7.3 pending
  post-removal). ctx7 Xcode CLI refresh post-wiring (2 cmds, `research.md` §6).
  26/41.
- 7.4 + 8.5 verification 2026-11-04 (no marks): `scenario-matrix.md` maps EVERY
  delta scenario to named tests + native evidence (PROVEN-U/N except runtime +
  oversubscription no-drop gap, precisely specified for owner); FURPS re-checked
  (`Requirements/` zero diff; tree diff capture-only, no prod behavior change —
  1.4 rows hold); `openspec validate --strict` valid; baselines untouched;
  0 tracked binaries, status text-only. 8.4 runbook 8.5 list corrected to actual
  (Python CLI done, Swift active; live utilities enumerated; no shipping-compat
  promise). 7.3 awaits final tests, 6.4 install + backend pending. 32/41.
- 6.x pipeline 2026-11-04: 6.1/6.2/6.3/6.5/6.6/6.7 MARKED UNIT/STRUCTURAL
  (audit PASS + YAML structure + panels 89/89 observed). Caveat: 1 red 8.5-legacy
  test observed (443 run, fallout under active work); '495' count unreconciled.
  HELD: 6.4 (real install), 7.3 (removal + YAML lint), 7.4 (final snapshot),
  backend, 8.1/8.2/8.3/8.6. No false CI claim. 32/41.
- Expansion 2026-11-04 (report only, 3.5/5.4 ON HOLD for audit): 6 pairs done,
  root present (114 PNGs incl staging); per-device timings + 362-vs-285 overhead
  gap + 56-vs-80 inventory ambiguity flagged; sequencing/pt-BR/iPad notes;
  LA always pending ('genuine' = app fidelity only); no new-set approval invented;
  Swift released, sims cleaned; YAML rewire post-audit. See `evidence/helpers.md`.
  13/41.
- Expansion audit 2026-11-04: inventory corrected (80+32=112, SHA verified); timings
  corrected (95/116/305, 362 withdrawn); pins/nonces/LA-honesty verified. 3.5 HOLD
  (zh CJK-header carryover question, zh repro assigned); 5.4 needs frame+evidence
  validation (no genuine-LA/approval gates); receipts 12-vs-24 clarifying; YAML
  awaits locale fix. 13/41 kept.
- Locale carryover CONFIRMED 2026-11-04 (8/8 repro, mechanism source-verified):
  prior 'product bug' label withdrawn; minimal capture-only fix authorized (ctx7 +
  red tests + fresh retake into `shot-session-expansion-locale-fixed/`); 3.5/5.4
  OPEN till fixed proof; counts corrected (24/24 in 12 manifests; 112+2=114).
  No shipping-locale/pt-BR changes. Rewire holds. 13/41.
- Locale-fix candidate 2026-11-04 (13/41 HOLD for audit): explicit-locale fix
  source-verified, reds present; suite/build counts owner-reported with 2 toolchain
  warnings labeled; retake root present (80 PNGs, sha-frames, strips); binary-predates-tz
  + shipping/nav-reset + eligibility caveats assigned; 63/iPad rationale for audit;
  backend pending. See `evidence/helpers.md`. 13/41.

## Frozen final retake 2026-11-04 — candidate, 3.5/5.4 HOLD for audit (22/41)

- Root verified present: `shot-session-final-verified/` (6 pairs, 120 PNGs =
  112 + 8 strips, freeze BEFORE/AFTER, epochs, build log).
- Freeze VERIFIED by docs: 166/166 files, same key set, 0 changed, diff SHA
  `a014ff1f`, HEAD `bd126664` (170-vs-168 top-level counts are metadata keys
  only — `_git_diff_stat`/`_git_status_untracked` present BEFORE, absent AFTER).
- Epochs verified: 1793776437→1793776673 = 236s ML ✓. Preserved claims
  (owner-reported): 24 sessions/receipts, 12 manifests, phone63 108s, pad 144s,
  8 correct headers, app `a4f0d8d5`/`43272f47`, one Xcode 27.1/SDK 27.1 build.
- Inventory scope NOT laundered: reported 152 files / 80 PNGs = 56+24 reads as
  ML-scope vs whole-6-pairs 80 canonical + 32 staging = 112 — auditor reconciles.
- Gate: independent source/binary/timing audit + workflow owner verify, THEN
  conditional YAML 6.1–6.6 rewire ONLY on pass (no CI claims). Consumer owner
  does fresh 8-header + 2-geo frames/inventory next.
- Freeze rule: NO source/iOS changes during YAML writes — whole-repo digest will
  move, but the selected-166 inventory above is the freeze definition. Research
  refresh already recorded post-fix (`research.md` §5); no fake prior citation.
  Backend still pending. 22/41.
- Verify-all 2026-11-04: 3.1/3.2/3.3/3.4/4.1/4.2/4.7 MARKED with read source/test/
  log citations (ResetTests names, chrome/provenance/route tests, 1125/103 +
  1051/98×2 + srel BUILD SUCCEEDED; owner '112 suites' corrected to 103).
  HELD: 7.2 (lint log predates fix edits), 4.5 (F1), 3.5/5.4 (frozen retake),
  backend 7.1. ctx7 Foundation refresh done post-fix (2 cmds, confirms pattern,
  logged in `evidence/research.md` §5). Count verified 20/41.
- 4.3/4.4 MARKED 2026-11-04 (focused review ELIGIBLE, source spot-checked):
  transcript-bound cleanup + combined receipts + failure matrix + contaminate-stop
  + forgery regressions; limits recorded (prefs/FD/provenance-stub); no extra
  gates. Expansion Swift active, backend pending. 13/41.
- 5.3 MARKED 2026-11-04 (measured NO-CHANGE: phase/app-clock numbers, guard +
  cadence retained, '8 vs 140' withdrawn). 2.1 MARKED (PhaseStats source + 3
  Python tests + Swift timing test, all criteria covered). 11/41. 5.4 expansion
  next after cleanup review.
- Retake prereqs 2026-11-04 (independently PROVED): runner 472+1 (focused 205,
  repro 20/20, wrong-16PM zero-export, exact-18PM attestation, preserved refusals);
  panels 89/89 (50+39, queue-proof negatives pass); Swift AUTHORIZED for 18PM 2-pass
  retake (`shot-session-pilot-18`, sole build/sim owner) — result pending, so
  5.1/4.3/4.4 OPEN; root-orphan removed, no stale findings; old 69s never
  acceptance. 7/41; backend 7.1 pending.
- Final Python unit 2026-11-04 (independently verified, unit only): worker 458+1
  (117 session + 28 CLI), 16/16 minimal repro rc2, genuine-CLI anchor/tolerance
  semantics pass; no Python blocker, no Swift/native proof; v1 branches still
  8.5-remove; tests-dir discover quirk documented in `evidence/runner.md`.
  Consumer 87 green (3-anchor reject + render-only mock). Backend final report
  pending (gofmt/vet green so far); Swift sole build/sim owner pending. 4.4 still
  needs real combined receipt. 4/41.
- Panels: pending runner pure helper; no bundle approval claim.
- Scenario→evidence map: `evidence/scenario-matrix.md` (all new-code rows PENDING;
  existing tests prove nothing new).
- project-context.md / operator runbooks NOT updated as implemented — docs land in 8.4
  only, after measured evidence.

## Sessions (same IDs, now active)

- Parent: main / gpt-6.1-sol / ses_e879ace1. No commits/push/PR/merge yet.
- Baseline: ses_e5b61db2affeTLz700VC8t7LoL (done; owns `evidence/baseline.md` only now).
- Docs/tasks (YOU): ses_e5b61dab5ffeyj9fobFVRltSVn — sole tasks.md writer.
- iOS/Swift: ses_e5b6104baffeN0PL4P2duYfJZn — ACTIVE, failing regressions first,
  exclusively owns local build+tests+fresh sim.
- Python runner: ses_e5b610498ffeUiDjXr4u5jVC6s — ACTIVE, no sim, golden first.
- Workflow: ses_e5b610452ffeKlWcu0qf1qRYG9 — ACTIVE on 6.1–6.4 helpers only.
- Panels: ses_e5b610433ffePDclXS6JtKYU3q — pending runner pure helper.

## Next (in order)

1. DONE — 1.3 proved and marked; implementers resumed (golden-first, then pilot 5.x
   before full workflow).
2. Resume iOS + Python + pure workflow helpers in parallel, contract/golden-first
   (runner writes golden vector(s) first, shares with Swift).
3. Panels after helper ready; pilot 5.x before full workflow; backend-verify and
   iOS-verify on disjoint parallel agents.
4. 8.1/8.2 cold+warm full CI are the real acceptance (no sub-20-min claim until
   measured); 8.3 truthful bundle/LA still pending; 8.4 doc updates later.

## Invariants

- All file edits/repro/tests ONLY by implementers; parent orchestrates reads.
- Worktree already created/moved, from fresh origin bd126664
  (`timeOfLife.wt/optimize-app-screenshot-workflow`, branch
  `opsx/optimize-app-screenshot-workflow`).
- Never: writes to original repo main checkout, binaries in git, secret persistence,
  history rewrite, `merge main` (rebase + force-with-lease only).
