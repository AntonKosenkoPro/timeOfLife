# Swift session milestone — independently verified (unit + cross-lang + pilot-partial)

Date: 2026-11-04. Docs owner verified paths/counts/logs read-only; no builds run.
Counts below are log-observed, not owner-asserted.

## Sources (verified present)

- `ios/TimeOfLife/TimeOfLife/Core/Capture/ScreenshotSession.swift` (605 lines)
- `ios/TimeOfLife/TimeOfLife/Core/Capture/ScreenshotSessionController.swift`
  (727 lines; mount proof rides `.task(id: revision.id)` — NEW SDK behavior, see
  research gap below)
- `ios/TimeOfLife/TimeOfLifeTests/ScreenshotSessionTests.swift` (31 @Test)
- `ios/TimeOfLife/TimeOfLifeTests/ScreenshotSessionGoldenTests.swift` (3 @Test)
- `ios/TimeOfLife/TimeOfLifeTests/session_envelope_golden.json` (project test
  resource, referenced by GoldenTests line 19)

## Logs (observed)

- `/tmp/ses_full2.log`: Screenshot full suite **1112/1112 in 102 suites**,
  `TEST EXECUTE SUCCEEDED`.
- `/tmp/ses_red*.log` (4 red runs): `ses_red2.log` shows build-failed red state;
  `ses_red4.log` carries 68 failed/error lines. Red-before-green recorded.
- swiftlint strict 0 errors + Debug/Screenshot builds green: owner-reported, NOT
  independently observed (no build run by docs).

## Cross-language (executed)

- GoldenTests: fixture contract pins frozen keys/domains; every vector hashes
  exactly + parses with full runner schema; semantic projection excludes only
  volatile `run_id`. Shared fixture = same file Python reads.

## Pilot (partial, owner-reported with caveats)

- 4 pinned native PNGs 1320×2868 + complete receipts; real timer 3 states, one
  shared anchor, cleanup complete; LA still pending. Caveats: different RID for
  pinned vs real-time, r2 NOT done → 5.1 stays open. Queue-dir leftovers → 4.3/4.4
  stay open (Swift regression fix + same-RID two-pass pilot assigned).

## Research gap

- `.task(id:)` restart/cancellation semantics: owner must refresh ctx7 Apple docs
  if not already fetched during implementation (parent asked owner to confirm).

## Follow-up pilot 2026-11-04 — owner-reported, 5.1 NOT closed

- Runner: 69s 2-pass vs 114s baseline (4 sessions, 8 launches) — owner-reported
  timing, not independently timed.
- Verified on disk: `/tmp/ses_fullpilot/shots/iphone69/en` = 20 PNGs (14 canonical
  `frames/` + 6 `staging/` LA per pass); hash ONLY canonical frame outputs. All 14
  canonical frames 1320×2868 (hashes recorded above in verification); both manifests
  `needs-inspection` with honest 3-LA pending; session files carry one RID per pass
  (same RID both domains per pass ✓); r1/r2 share one anchor per report.
- SIM CAVEAT (durable): report says fresh 16PM sim vs baseline 18PM; parent asked
  for actual identity proof — pilot files inspected carry no sim-model attestation,
  so nonequivalence is still possible. 5.1 stays open until identity-proved retake.
- Cleanup fix (owner-reported): scoped queue nonce, seq-0 consumed, root-orphan
  report dropped, new app ack `removed_session_queue:true`. VERIFIED GAP: that key
  appears nowhere in `scripts/screenshots/*.py` — runner receipts DROP it. 4.3/4.4
  stay open until strict copy + validation + retake (parent-assigned).
- ctx7 `SwiftUI.task(id:)`: owner claims researched; fetch record not observed by
  docs — cited as owner-claimed.
- Narrow-task reconciliation (named-proof, read-only): 2.1 still open (counters
  scope); 3.1–3.4 still open (no new negatives observed — 3.4 still only
  late-callback; resets/per-command revalidation/mount-order unproven); 3.5 open
  (no all-locale sequence); 4.7 open (Release gate unclear). No blanket marks.

## Device identity (authoritative, owner-confirmed 2026-11-04)

- ACTUAL iPhone 16 Pro Max — not a typo. Create cmd type `iPhone-16-Pro-Max`,
  named SES1116 16PM, UDID `3B806C6D-…` in all records (live sim now absent —
  scoped cleanup deleted it, consistent with CI teardown).
- Geometry 1320 proves NOTHING about identity (16PM and 18PM share it).
- The 69s result is EXPLORATORY NON-EQUIVALENT — never a baseline performance
  acceptance. 5.1 OPEN; proper 18 Pro Max retake awaits runner strict queue/model
  preflight. Old receipts are NEVER retrofitted.
- Precise verification state: Screenshot full 1112/102 pass (`ses_full2.log`);
  Debug build + 10-request subset ONLY (full Debug suite NO); Release NOT
  built/tested.
- Narrow missing negatives: 3.3 store-mutation injection OPEN; 3.1 active-sync
  injection OPEN; 3.5 real multilocale sequence NOT executed. 3.4: stale-ignore +
  two device-mount-timeout repro/task-fix proven, other criteria remain.
- Swift resource RELEASED — waiting explicit resume; no build/sim active from
  Swift until runner contracts finalize.

## Proper 18PM pilot 2026-11-04 — 5.1 MARKED (audit-verified, see tasks.md)
- Prior verified-what-only + retraction notes above stand as history. Audit verdict
  5.1 ELIGIBLE on all dimensions; inventory hash-verified by docs (62 files).
  59s ACCEPTED / 63s rejected / ~48.2% local-warm only / no sim-command reduction
  claim / PIL visual numbers / owner 0% claim withdrawn.
- 4.3/4.4 assessed, LEFT OPEN: combined receipts structurally proven in pilot
  artifacts + fake failure matrix covers all phases, BUT 4.3's per-item criteria
  (task/store handles closed before removal, named files/preferences removal)
  are NOT yet source-verified by docs, and 4.4's F2 whole-manifest landing +
  any real (non-fake) failure proof are unverified. Reasons recorded; no habit-hold.
- 5.2 OPEN: fresh actual-image inspection assigned to panels owner next (no human
  owner approval required by task text). Screenshot 1114/102 green exact-tree log
  cited in tasks. Count 8/41.

- Verified on disk (`shot-session-pilot-18`): 28 PNGs total = 20 under `runs/`
  (14 canonical `frames/` + 6 LA `staging/`) + 8 owner-made `diffs/` (4 frames ×
  diff + context — owner artifact, not evidence); all 14 canonical 1320×2868;
  both manifests `needs-inspection` + honest 3-LA pending;
  4 session files per pass; attestation UDID `C7EA3C93-…` +
  `deviceTypeIdentifier …iPhone-18-Pro-Max` in session records ✓ (device claim VERIFIED).
- Combined receipts VERIFIED structurally: `app_cleanup` carries
  `removed_session_queue` + nonce/final_seq/transcript, plus `runner_verified`
  (chrome/lease/process) and transcript — the previously-dropped key now flows.
  Whether strict validator (not passthrough) copied it is FOR THE AUDITOR.
- RED FLAGS (recorded, not adjudicated): static frames byte-stable across ALL
  runs/devices (history `f331171e`, insights `4ab1c775` — third appearance);
  track shows only 2 variants (`d076…` r1-type, `ba37…` r2-type) across 3
  runs/devices; LA system pixels DO vary run-to-run. Stale-inventory vs
  determinism is the auditor's call — pixel-identical NOT asserted.
  ⚠️ RETRACTED 2026-11-04 (stale-file-derived): owner ADMITS 16PM inspection
  paths were mixed into the 18PM report. Withdrawn: the 14-hash inventory above,
  r1↔r2 variance + bboxes, viewed Insights/History/Add-entry images, status-file
  contents, 106-vs-1080 claim. Corrected fresh owner claims: ~60s NOT 63 (raw
  07:34:36→07:35:35); r1 track `ba378bfd` insights `4ab1c775` history `f331171e`
  add-entry `a9d7616e`; r2 track/insights/history same, add-entry `329177e9`.
  Docs note: these corrected values MATCH docs' own independent hashes of the 18PM
  files (same prefixes observed) — hash values confirmed, still NOT acceptance.
  Fresh-claimed (pending audit): worker log/summary, phase counts, receipts +
  queue check, Argent diff currentPath 18PM. Auditor is checking all actual files
  plus diff sources.
- Owner-reported only (pending audit): 63s vs 114s (45%), 4 complete queue proofs
  + empty-nonce queue, tree-full 1114 green + lint/build 0 errors. simctl 106 vs
  1080 scope comparison INVALID (1080 = all 5 locales; per-locale baseline ≈216
  unless recomputed from logs).
- Readiness: 4.3/4.4/5.1 are closure-CANDIDATES after auditor verifies raw
  timing/hash/device/provenance — NOT before. 5.2 needs only native inspection
  diff (4 frames) + honest LA per task text (no owner approval / all-locales
  required), but the diff itself is undone and the hash flag unresolved → stays
  open. Archive owner gates 5.4/6.6/9.4 untouched.

## 5.3 profiling 2026-11-04 — measured NO-CHANGE (see tasks.md for numbers)
- Dominant cost is per-frame settle (~1s × 14) + overlapped poll; seed once per
  session; mount fast after first. Guard/cadence/deadlines retained; no bypass;
  no 42s-floor / 7–14s-bound claims; '8 vs 140' withdrawn (same-locale 28;
  all-5 140→40 structural). 5.4 expansion next after cleanup review.

## 4.3/4.4 MARKED 2026-11-04 — focused review, source spot-checked by docs
- 4.3: `verifySessionTranscript` + `loadVerifiedPrior` (`ScreenshotCleanup.swift`
  ~83–120, ~300–321, observed); queue-removal + host-gone proof (`executor.py`
  ~1982–1999, observed); namespace/token tests observed; anchor/fixture-end,
  named-files, defaults covered by review-cited code/tests + real-receipt key
  presence verified in 18PM artifacts. LIMITS: prefs = source/unit proof, no
  separate ack field; FD order = architectural + receipt-bound, no live
  instrument; 6 LA stubs pending `app_provenance` (intended). No extra gates.
- 4.4: full failure matrix both languages (test names observed §2 + device-worker
  24/24 + auditor subset-forgery passes); real happy 4 receipts corroborate
  (structure verified). Real-device failure injection explicitly NOT required.
- Prior "candidate" notes above stand as history; this section records the mark.

## Reset + verify-all 2026-11-04 — 3.1/3.2/3.3/3.4/4.1/4.2/4.7 MARKED (20/41)

- ResetTests observed (`ScreenshotSessionResetTests.swift`, 10 named tests):
  3.1 sync-inject/seed-once/locale-before-mount; 3.2 fresh-shell/nav-reset/blank-
  search/fresh-add-entry; 3.3 mutation-inject/Add-snapshots-identical; 3.4
  unmounted-mount-timeout. Capture-gating both overloads + nav-reset controller
  SCREENSHOT-only + shipping untouched source-verified.
- 4.1/4.2: `run_session` lease + provenance + evidence-gated staging (code +
  `SessionPollAndChromeTests` observed); real 18PM receipts corroborate.
- 4.7: route/namespace/token tests + Debug 1051/98 ×2 + Release SIM
  `/tmp/srel.log` BUILD SUCCEEDED (0 project warnings).
- Logs: Screenshot 1125/103 green (`/tmp/sloc_full3.log`; owner '112 suites'
  corrected to 103); Debug twice (`/tmp/sdbg*.log`); red→green ordered by mtime
  (`slocale_redtest` < failed-full `slocale_full` 70 issues < green `sloc_full3`).
- HELD with reasons: 7.2 (SwiftLint log `s63_lint.log` 07:45 predates 08:31/08:45
  fix edits — strict lint on the current tree unproven), 4.5 (F1 genuine-CLI
  wiring open), 3.5/5.4 (frozen-binary retake pending), backend 7.1 (report
  pending). No iOS build/sim run by docs.
