# Workflow pure-helper milestone — evidence only (NOT acceptance)

Date: 2026-11-04. Tasks stay 4/41 — NO 6.x closes: build/install/workflow wiring
(early job, device install, run_device_worker, matrix cutover) all unwired.
Independent baseline-worker audit in progress; acceptance pending audit + integration.

## Landed (pure helpers, no workflow wiring)

- `scripts/screenshots/workflow_inputs.py` (133 lines) — device/locale selection
  validation (empty/unknown/duplicate/malformed/injection-shaped rejected; default
  catalog retained). Tests: `tests/test_workflow_inputs.py` (165 lines).
- `scripts/screenshots/build_artifact.py` (671 lines) — arm64 slice inspection,
  permission-preserving tar (executable bits/symlinks), digest manifest, provenance
  mismatch rejection, cold-rebuild-on-miss. Tests: `tests/test_build_artifact.py`
  (599 lines).
- `scripts/screenshots/workflow_artifacts.py` (173 lines) — per-locale artifact
  layout helpers. Tests: `tests/test_workflow_artifacts.py`.
- Initial state: 54 green (helpers + tests present, issues still open).

## Parent review → red→green (owner-fixed, reported)

1. macOS vs iOS bundle layout — fixed; tests now use real iOS root
   (Info.plist + executable) and `PlugIns/LifioLiveActivities.appex` (root + exe)
   with exact app/extension IDs.
2. Missed valid-dir symlinks — fixed (legitimate directory symlinks accepted).
3. Missing manifest schema/IDs — fixed (schema + identity fields present).
4. Extraction alias mutation / hardlink issue — fixed: tar rejects hardlinks,
   duplicates, preexisting collisions, ancestor-link escapes.
5. Cache skips normal build — fixed: normal build ALWAYS runs after restore
   (cache is advisory only).

## Fix verification (owner-reported, audit pending)

- Repro: 32 errors + 7 fails on the corrected fixtures before fix.
- After: `test_build_artifact` 37 OK; existing suites green (no regressions).
- Manifest `xcode`/`sdkbuild` fields OPTIONAL until workflow integration, which MUST
  pin them (recorded gap, not a waiver).

## Device-worker thin loop 2026-11-04 (evidence only, YAML unwired/pilot-gated)

## Device-worker thin loop 2026-11-04 (evidence only, YAML unwired/pilot-gated)

- `scripts/screenshots/run_device_worker.py` (+ tests, verified present): 24/24 green
  after red 7 fails + 7 errors.
- Layout: per-locale out `shots/<dev>/<locale>` (requests/statuses inside);
  `deviceworker-summary` at `shots/<dev>`. NOTE: worker CLI `--out` = shots root,
  capture CLI `--out` = pair root — not interchangeable.
- Failure semantics: `OSError`/`TimeoutExpired` → failed + contaminate-stop (later
  locales halted); `KeyboardInterrupt` records status then reraises; summary write
  error = visible fail, never success; pair-comparison failure sets
  `effective_complete=false` while canonical pairs preserve pass-capture truth;
  direct-execute input rejects empty/duplicates/etc.
- YAML matrix cutover still unwired/pilot-gated. `test_session_run` latest snapshot
  shows 1 error during protocol-owner active changes — whole suite NOT green.
  Tasks stay 4/41; Swift/Python/panels still active, no progress polls.

## 5.4 expansion BLOCKED pre-device (2026-11-04) — approval plumbing missing

- Worker omits approval/retained-dir handling; gates correctly REQUIRE old-pilot
  owner approval for non-English / non-pilot geometry.
- Approval artifact VERIFIED present read-only (original untouched):
  `.../app-store-screenshot-pilot/approval-pilot27-r2.json` (1551 B) —
  `decision: approved`, run `pilot27-r2`, gates `['non-english', 'ipad']`,
  7 frame hashes, deck `en-austin-1`, treatment `light-v1`, manifest SHA pinned.
- Worker owner tasked: VALIDATE hash-bound approval, then plumb OPTIONAL paired
  flags through `run_device_worker` — no auto-bypass, no fabricated approval, no
  mutating retained originals. Owner approval is NOT reclassified as a new-session
  accepted source. No user question needed yet (existing approval may resolve it
  within scope).
- Unblock order: file validation + CLI plumb → explicit Swift resume. Swift
  RELEASED now: zero expansion sims/build active. 5.4 stays OPEN; 13/41.

## Expansion report 2026-11-04 — owner-reported, 3.5/5.4 ON HOLD for audit

- Root verified present: `shot-session-expansion/shots` = 6 pairs (iphone63/en,
  iphone69 × ru/zh-Hans/es-419/pt-BR, ipad13/en); 114 PNGs total on disk
  (canonical + staging). All timing/count claims below are owner-reported.
- iphone63/en 95s @1206×2622 (exact 17); ipad13/en 116s @2064×2752 (M4-8GB, lock
  only + N/A probe); 18PM 4-locale worker 362s with per-locale 107+62+58+58=285
  — 77s overhead UNSOURCED (needs log source).
- Inventory ambiguity FLAGGED: 56 canonical reported vs 80 expected across 6
  pairs (14+10+56) — scope of the count unclear; auditor to reconcile.
- Sequencing observed per owner (ru→zh-Hans→es-419→pt-BR native chrome); pt-BR
  Insights tab English is PRE-EXISTING, out of fix scope; iPad layout claimed
  same as production Debug.
- LA ALWAYS PENDING, never genuine — owner's 'evidence genuine' phrase means
  native app fidelity ONLY. No approval invented for new sets (old file gates
  expansion scope only).
- Swift RELEASED, sims deleted, Argent scoped-cleaned. Stage-6 YAML rewire only
  after audit passes. 13/41 unchanged.

## Expansion audit corrections 2026-11-04 (auditor-verified, 3.5/5.4 still HOLD)

- Inventory CORRECTED: 80 canonical (14 phone63 + 10 pad + 56 ML) + 32 staging =
  112 PNG scope. Old '56' was partial; docs' 114 likely includes 2 Debug ancillary
  (excluded). New inventory `/tmp/SHA-expansion-fresh` VERIFIED (112 lines, SHA
  `8d712023…` matches).
- Timings CORRECTED: 95 phone63 / 116 pad verified; ML 305 NOT 362 (raw locales
  123 ru + 64 zh + 58 es + 59 pt ≈ 304 sum). The 77s 'missing overhead' and the
  362/107 figures are WITHDRAWN as unsourced.
- Verified: model/build/locale pins, fresh nonces, approval false-CI posture, all
  LA honest-pending.
- 3.5 CLOSURE ON HOLD: auditor observes zh History CJK date headers AFTER zh —
  'preexisting' UNPROVEN. Swift assigned fresh isolated zh repro + sources for
  reviewer; could be actual carryover. No-carryover NOT asserted despite non-blank
  native shells.

## Locale carryover CONFIRMED 2026-11-04 — real bug, 3.5/5.4 OPEN till fixed proof

- Repro 8/8 native History images (docs-verified pattern): each locale's r1 shows
  the PREVIOUS locale's headers (ru-r1 EN, r2 RU; zh-r1 RU, r2 ZH; es-r1 ZH,
  r2 ES; pt-r1 ES, r2 PT). Prior 'static product bug' classification WITHDRAWN
  as WRONG.
- Mechanism source-verified by docs: day-label formatters set `.calendar` but
  never `.locale` (`HistoryViewModel+Formatting` ~21–26, ~53–62); `timeText`
  already has the `SCREENSHOT_CAPTURE` locale/timezone override pattern (~89–101);
  `HistoryVM` day/time formatters read `calendar.locale` (~402–408);
  `ScreenshotApp` ~26–35 documents frozen `Locale.current` at launch.
- Fix authorized (minimal, SCREENSHOT_CAPTURE-only): explicit `dayLabelLocale`
  consistent with existing `timeText` pattern. Requirements: ctx7 before SDK
  dependence, red tests first, fresh 4-locale BOTH-passes retake into new unique
  approved temp `shot-session-expansion-locale-fixed/` (+ other 2 geos with new
  binary if needed). Old images RETIRED, never edited.
- No shipping-locale changes; pt-BR Insights fix NOT authorized. Workflow rewire
  holds on the locale gate.
- Count correction (auditor): 24 receipts / 24 sessions in 12 manifests; 112 shots
  PNG (80 canon + 32 staging) + 2 root ancillary = 114 overall. Previous ambiguous
  statements updated to these counts.

## Locale fix report 2026-11-04 — candidate, 13/41 HOLD for audit

- Fix source-verified by docs: both `dayLabel` overloads take explicit locale +
  strict timezone pairing under `SCREENSHOT_CAPTURE` (one-shot + reusable-box
  overloads; caller's box bypassed so pinned formatters can't leak). Red logs
  present (`/tmp/slocale_red*.log`).
- Suite/build counts owner-reported (NOT independently counted): Screenshot
  1125/112, Debug 1051/98, Release SIM build 0 errors, NO edits after verification
  (owner claim). Two toolchain AppIntents warnings EXPLICITLY labeled — no
  0-warnings claim.
- Retake root verified present: `shot-session-expansion-locale-fixed/` (80 PNGs
  under `shots/`, `sha-frames.json` dict/56, header strips incl es-419/pt-BR/ru/zh
  samples observed, wall 260s owner-claimed). Old images retired, not retrofitted.
- CAVEATS for auditor: pilot binary `sloc_app2` PREDATES last tz refinement
  (claimed runtime-neutral — source auditor to verify); shipping-unchanged + nav
  reset capture-only to verify; 3.1–3.4/4.7/7.2 eligibility assigned; consumer
  owner does 8-fresh-image + artifactual audit for 3.5/5.4.
- 63/iPad NOT retaken on new binary (owner rationale: en_US same vs ambient) —
  audit decides whether any runtime change matters.
- Swift RELEASED, no resources active. Backend final report pending. 13/41 HOLD.
- 5.4: measurement within ≤150s BUT must validate locale app frames + actual
  evidence; does NOT require genuine LA or owner approval (old 5.4 is a different
  namespace) — those gates not invented.
- Receipt count 12 vs 24 nonces UNDER CLARIFICATION (owner/reviewer checking actual
  files); no accepted count until fixed. Stage-6 YAML awaits locale-issue
  clarification. No code writes. 13/41 kept.

## Still missing (blockers to any 6.x close)

- Workflow integration: build job, artifact upload/download, device install,
  `run_device_worker.py`, device-only matrix cutover (6.5), packaging/finalizer
  rewire (6.6–6.7) — none wired.
- Baseline-worker audit of the above + integration proof still pending.

## Independent audit 2026-11-04 (no blocker; still helper-only, NOT acceptance)

- Auditor: 68/68 tests pass on the helper snapshot; real iOS product validated
  (73 regular files, 0 symlinks/hardlinks — tar composition matches a genuine
  iOS app bundle, not the earlier macOS-shaped fixture).
- Latent N1 `write_status` path traversal PROVEN by auditor, then owner-fixed:
  strict `validate_status_record` now guards `status_path_for`/`write`/`load`
  (exact schema, key types, device/locale catalog, pass, status, reason, run-ID
  regex); malicious device `../evil` rejected with no writes. Also fixed: clear
  error on non-dict manifest, accurate symlink/hash composition docs (verified
  present in `workflow_artifacts.py` + `tests/test_workflow_artifacts.py`).
- Fix verification (owner-reported): 5 new methods, red 25 fails + 5 errors, then
  green — targeted 73 tests OK (artifacts 16 / build 37 / inputs 20); existing
  12 suites green including old workflow contract.
- Scope guard: do NOT assert the whole protocol suite is green from this helper
  snapshot. Pending dependencies unchanged: early CLI, golden vectors,
  `session_evidence` helper, pilot 5.x. Swift/Python workers active and own their
  modified files; no agent polling needed.

## 6.x pipeline marks 2026-11-04 — UNIT/STRUCTURAL only (32/41)

- 6.1/6.2/6.3/6.5/6.6/6.7 MARKED on audit PASS (no findings: cache/SDK/toolchain/
  multipath-reshard/backfill/raw-ZIP/resource-hash/dirty/catalog fixes) +
  docs-observed YAML structure (validate→build→device-workers→panels,
  max-parallel 5, fromJSON device matrix, ARCHS=arm64) + panels 89/89 green.
- RED-TEST CAVEAT (docs-observed 2026-11-04): `scripts/screenshots/tests` runs
  443 (== method count) with 1 FAIL + 1 skip — the failure is
  `test_legacy_removal.RemovedVerbsTests.test_record_external_request_flag_unrecognized`
  (expects old argparse 'unrecognized arguments', gets new fail-closed
  'invalid: state file not found'), i.e. 8.5-legacy-removal fallout under active
  work, orthogonal to 6.x criteria. Audit's '495 OK' count scope unreconciled
  (docs count 443 methods); recorded, not laundered.
- HELD: 6.4 (real verified tar install on all types — Swift when removal build
  finishes), 7.3 (legacy removal ongoing + YAML parse/action-lint assigned, no
  blanket ignore), 7.4 (final matrix mapping waits final snapshot; no >5-capacity
  claim — unit `describe_capacity` ≠ observed queue), 7.1 backend, 8.1/8.2/8.3/8.6.
  8.5 removal active. App freeze unchanged (only YAML/owned-helper writer active).

## Frozen-final audit 2026-11-04 — 3.5/4.6 MARKED (24/41)
- Source freeze: 166 BEFORE/AFTER, no drift, metadata-only delta (docs-verified).
- Inventory COMPLETE, self-hashed by docs: `sha-inventory.json` SHA
  `55298940…cfb674806`, 152 entries = 112 PNG (80 canonical + 32 staging) + 40
  manifest/receipt/probe records — NOT partial (owner's ML-scope description was
  wrong; corrected here).
- Shared-helper 12/12 OK on all records/PNGs (rehash BAD 0); 24 sessions fresh
  nonces, receipts complete; 12 `ci_approval_bypass:false`.
- Native: 8/8 History headers correct (ru/zh/es/pt both passes, date + chrome);
  phone63 1206×2622 + iPad 2064×2752 all-4-app correct, no clipping; iPad M4-8GB
  probe simctl-list-nonce-joined, 2 Island N/A in scope, zero Island files, lock
  required-pending. App `a4f0d8d5` in all 12 manifests / 48 app frame records.
- 5.4 native portion ELIGIBLE (no owner-approval/genuine-LA gates invented) but
  HELD for timing/binary-extension audit; conditional YAML gate still to finish.
  Missing extension-SHA in raw capture manifests noted (build-log verified by
  another owner — not a 3.5 blocker). Three geometries = 3 owned UDIDs; per-session
  join valid, no same-UDID claim.

## Evidence inventory truth (actual JSON, 2026-11-04 — supersedes contradictory
owner descriptions)

- Frozen pilot: `/tmp/SHA-18pm-pilot-retake` SHA `d5a63e00…89d83`, 62 files
  (docs-hashed, matches).
- Frozen final: `shot-session-final-verified/sha-inventory.json` — 152 entries =
  112 PNG (80 canonical + 32 staging) + 40 manifest/receipt/probe records.
- Full root: `/tmp/SHA-final-verified-full` SHA `5dcb34d6…89d83`, 361 files
  (112 PNG + requests/sessions/manifests/strips/provenance — docs-verified
  breakdown; '80 PNG only' rejected).
- Source freeze: 166/166 files, 0 changed, diff `a014ff1f`, HEAD `bd126664`.
- No empty approved bundle: every claimed-complete pair has both passes or an
  explicit failed/unattempted status; raw shots + receipts ship in the ZIP.

## 5.4 MARKED 2026-11-04 — freeze/timing/binary audit PASS (25/41)

- Full-root inventory self-verified: `/tmp/SHA-final-verified-full` SHA
  `5dcb34d6…89d83`, 361 files (112 PNG + requests/sessions/manifests/strips/
  provenance). The '80 PNG only' description REJECTED — exact scope recorded here;
  old source-audit inventory line noted wrong but not blocking (actual hash proof
  is clean).
- Timings: phone63 108s, iPad 122s RAW (144 withdrawn), ML 236s, all ≤150 guide.
  Source 166 no-drift + app/appex hashes + Xcode/SDK pins verified.
- HOLD all 6.x: workflow YAML 6.1–6.6 landed (31 contract tests, TDD red→green)
  BUT parent review caught real integration gaps (SDK-vs-runtime field, toolchain
  select/cache IDs, multi-path LCA double-locale, prework-failure statuses,
  ZIP panels-only omission, resource-map comparison, hardcoded dirty/catalog
  drift) — owner fixes assigned; coherent corrected pipeline + real-install 6.4
  proof + actual CI still pending. No false CI claim. Same app freeze unchanged;
  only YAML/owned-workflow-helper writer active.
