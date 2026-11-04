# Runner milestone — evidence only (NOT acceptance, 4/41 unchanged)

Date: 2026-11-04. Paths verified present read-only; no tests run by docs owner.
Owner-reported counts below are unverified by docs — cross-language + finalization
proof still required before any 2.x/4.x close.

## Landed (Python, fake-adapter only)

- `scripts/screenshots/session.py` + `scripts/screenshots/session_evidence.py`
  (`validate_run_evidence(run_dir, manifest, required_frames=None) -> list[str]`
  chokepoint, verified present) + `run-session` CLI (`capture.py cmd_run_session`,
  `executor.run_session`; CLI lease/domain/device-key guards in `tests/test_cli.py`,
  orchestration in `tests/test_session_run.py`).
- State ack / preflight / executor session additions (per frozen `evidence/protocol.md`).
- Owner reports: full screenshots suite 368 OK + 1 skip; 57 new scoped session tests.
  Fake-adapter only — no real pilot, no cross-language run yet.

## Golden vectors (shared with Swift)

- `scripts/screenshots/tests/fixtures/session_envelope_golden.json` — 2 vectors,
  verified present. Swift has the contract; cross-language exact-hash + projection
  proof still PENDING (gates 2.3).

## Remaining gaps (why 2.x/4.x stay open)

- `finalize_run` NOT yet receipt-gated; owner NOW working gate + session
  pending→genuine-registration test.
- Old per-frame verbs temporarily retained for unchanged-pilot comparison; MUST be
  removed in 8.5 (no shipped compat branch).
- Downstream now unblocked: panels implementing 6.7 shared-helper consumers;
  workflow thinning `run_device_worker.py` (outer loop/status, fake tests, CLI
  confirmed; YAML still pilot-gated).

## Dependency state

- Missing-helpers phase OVER; integration/test/pilot phase OPEN: receipt gating,
  Swift cross-language proof, real pilot 5.x, then workflow/panels integration.
- Note 2026-11-04: `test_session_run` latest snapshot shows 1 error during
  protocol-owner active changes — whole runner suite NOT green; see helpers.md
  device-worker section. Worker CLI `--out` = shots root vs capture CLI `--out` =
  pair root.

## Finalizer + probe checkpoint 2026-11-04 (owner-reported, audit pending)

- Counts (owner-reported, docs did NOT run): 428 OK + 1 skip, incl worker 24,
  sessions 32 / evidence 22 / run 33 / new CLI 3 / manifest 3.
- Session finalizer now strict-helper gates missing/partial/mixed-v1, iPad full-run
  N/A combination, and semantic comparison; actual `simctl-list` probe (schema-1,
  source + model{deviceTypeIdentifier,name,udid} + geometry + devicekey + run/
  realtime nonce — verified present in `session.py`/`session_evidence.py`/
  `executor.py`) joins the receipt; no fabricated Island, Lock required.
- Pending→genuine 7-frame E2E test bindings cover new hash/observations/shared
  anchor plus stale-hash/wrong-elapsed negatives. Real probe execution NOT proved —
  fake-adapter only.
- TDD caveat (truthful): finalizer tests were RED by inspection against old code,
  NOT by executed red run — do not assert a red run happened.
- Legacy per-frame branch stays ONLY for baseline comparison; explicit 8.5 removal.
- Parent started independent Python proof audit + panels-guard consolidation; Swift
  ack of contract forwarded. Tasks stay 4/41 pending combined verification audit.

## Independent audit 2026-11-04 (NOT acceptance; supersedes prior green snapshots)

- Audited snapshot: 433 tests, 1 FAIL — pending→genuine external registration loses
  `device_key`. Prior 428/81 greens SUPERSEDED by this audit.
- REAL blockers (runner assigned, negative tests required):
  1. Manifest-only pending top status `complete`, or invented capture/window/
     observation, accepted by shared validator → panels could render pending
     pixels as success.
  2. Exact model identifier + probe-UDID binding open — phantom model accepted.
  3. Schema-999 ack accepted despite unsupported-shape rejection contract.
- Panels assigned: manifest-invention consumer regressions + restored missing-probe/
  downgrade cases. Missing-probe/subset gate auditor-verified FIXED — whole gate
  still NOT complete.
- Record: external approved tmpdir `audit-session-RECORD.md`; shared code edited
  mid-review (fingerprint `082a2ad1a6c55a58` caveat — audit applies to that snapshot).
- Swift real cross-language proof + pilot still pending. 4/41.
- Root-orphan report REMOVED on Swift side — no stale finding outstanding.

## Retake prereqs 2026-11-04 — independently PROVED (not owner-only)

- Runner: 472 OK + 1 skip / full focused 205. Repro 20/20: queue flag missing /
  false / lying / leftover dir → partial-fatal + shared-helper reject; wrong-16PM
  iphone69 in BOTH domains → prelaunch zero exports; actual attestation exact 18PM;
  foreign files/queue/state → preserved refusals.
- Old 16PM 69s stays NON-EQUIVALENT (never acceptance); old no-flag receipts are
  NOT retrofitted.
- Swift authorized for the correct 18PM 2-pass retake (approved temp
  `shot-session-pilot-18`, sole local build/sim owner). Result pending → 5.1/4.3/4.4
  stay OPEN. 7/41; backend 7.1 report still pending.

## Fix candidates 2026-11-04 (owner-claimed, PENDING independent re-verify)

> SUPERSEDED by reaudit closure + retake prereqs below/above (472 OK, all findings
> closed at unit level). Kept for chronology; do not cite as current status.

- Owner reports 447 OK + 1 skip. All 4 audit fixes CLAIMED (do NOT treat as closed):
  1. Strict normalized exact-record agreement + top-status-vs-disk pending reject +
     numeric genuine observations.
  2. External registration preserves `device_key`.
  3. Exact catalog real M4 8GB/16GB model + probe-UDID binding.
  4. Acks strict schema-2 (non-bool guarded).
- Original A1/A2 repro owner re-ran → reject (owner-reported).
- Parent restarted: auditor original cases + panels 3-RED rerun + real-model-ID
  fixture. Statuses stay 'fix-candidate pending independent re-verify' until audit
  reports. Swift real build/pilot + accepted cross-language still outstanding. 4/41.

## Independent reaudit 2026-11-04 — ALL original findings CLOSED (unit code only)
- Snapshot: 447 OK + 1 skip. Executed (not inspection): A1/A2, external-key
  preservation, exact-model + probe-UDID binding, ack-schema rejection,
  missing-probe, metadata-strip, iPad-genuine-path (fake-adapter).
- Fingerprints: `session.py 7efdce0e`, `session_evidence.py 8b727a92`,
  `executor.py 4b00c932`, `state 200899d8`; audit record addendum in external
  approved tmpdir.
- Independently verified: unit-code level only. Still NO Swift real build/pilot,
  NO accepted cross-language proof, NO real-probe execution.
- Follow-ups assigned (open, runner-owned):
  F1. Genuine-external path is API-only — must wire trusted-stub binding in CLI.
  F2. `complete` status must check the WHOLE manifest, not the required subset
  (production callers currently immune, contract still requires it).
- CLI follow-up 2026-11-04 (owner reports 455 OK + 1 skip): parent found CLI state
  identity OPTIONAL → assigned strict `validate_session_ack` + UDID/geometry/full
  tuple/transcript negative fix. CLI handoff NOT accepted until fixed.

## Final Python unit handoff 2026-11-04 — independently VERIFIED (unit only)

- Worker: 458 green + 1 skip (focused 117 session + 28 CLI), independently verified.
- Minimal repro 16/16: missing nonce / v1 schema / empty transcript / device/
  geometry/run mismatches → all rc2, stub PNG receipts unchanged.
- Genuine CLI: 3 LA share one anchor, state-archive passes; +2.5s rejects, +2.0s
  exact accepts; pending-expanded never completes.
- No Python blocker left; NO Swift/native proof (real combined receipt for 4.4,
  cross-language, pilot all still pending).
- v1 comparison branches stay on the 8.5-removal list, unchanged.
- Runner quirk (evidence command only, NOT global runbook): discover from the
  tests dir (`python -m unittest discover -s tests`), not via the
  `tests.test_session_evidence` parent import path.

## 4.5 MARKED 2026-11-04 — F1 CLI wiring landed (reviewer-eligible)

- `record_external_session` strict trusted-stub bindings + envelope + receipt
  coverage; `validate_session_ack` integer-2 full-tuple/transcript; locks archive
  after verify. Numeric ±2s + geometry/mask preserved. CLI 9/9, PendingGenuine
  2/2, tolerance/mask/probe 12/12 executed; 18PM one-anchor receipts `886A`/`4B83`
  match 6 LA honest-pending; iPad M4 lock-probe valid. No genuine-pixel gate, no
  approval claim. 22/41.

## 4.3/4.4 MARKED 2026-11-04 — 234 focused Python green, no bugs (reviewer)

- Failure matrix + receipt-gating + contaminate-stop + subset-forgery regressions
  all pass; real happy-path receipts corroborate. No extra gates invented
  (real-device failure injection not required). Limits in `swift.md`. 13/41.
