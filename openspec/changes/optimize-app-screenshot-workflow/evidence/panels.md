# Panels consumer (6.7 portion) — evidence only (NOT done, 4/41 unchanged)

Date: 2026-11-04. Files verified present read-only; no tests run by docs owner.
Do NOT mark 6.7 or 4.x done — producer blockers below remain.

## Landed (consumer side)

- 4 files: `scripts/panels/builder.py`, `write_bundle_readme.py`,
  `tests/test_matrix.py`, `tests/test_panels.py` (all verified present).
- Owner reports 78 tests green (40 + 38) after red 6-of-9 new tests + README gate
  before the new shared-helper gate.
- Strict shared-helper call (no duplicate verifier); pending whole-cell block rule;
  explicit COMPLETE (review) vs HANDOFF/DEBUG bundle labels — labels are NOT approval.

## Producer blockers (runner-owned, in progress)

- Finalizer receipt gate, 7-frame assembly, iPad full-run combination unfinished.
- Current N/A probe lacks ACTUAL device-capability attestation (only device-key flag
  reason run); must extend: strict helper validates actual model + native geometry +
  run/realtime nonce.
- Panel's own additive probe guard is temporary duplication; runner asked to
  consolidate ALL such checks in the shared helper, then panel removes its copy.

## Consumer unit milestone 2026-11-04 (owner-reported, independent review resolved)
- 87 green (48 matrix + 39 panels). All 3 audit negative cases intact/pass;
  missing-probe/metadata-strip intact/pass; exact model UDID.
- Historical-69 split: unmocked production `verify_sources` REJECTS 3 anchors;
  separate test ONLY scoped-mocks `_sev.validate_run_evidence` → `[]` for the
  in-process build_69 pixel compositor, then real selftest/template/approved-hash +
  byte equality — no production flag/env bypass/window rewrite/approval.
- iPad strict single-anchor retained untouched; session-receipt fixtures are
  test-scaffold ONLY. Owner reports no consumer gaps, but full 6.7 still needs
  packaging workflow integration → NOT done. 4/41.

## Retake prereqs 2026-11-04 — 89/89 (50 matrix + 39 panels)

- New missing/false queue-proof negatives PASS; all prior cases intact.

## 5.2 fresh inspection 2026-11-04 — DONE (panels owner, no stale-16)

- Direct reads + PIL: Track 12:34 Morning-run 9:41 chrome; Insights 6h25m/23100 +
  bars/tab; History search + Today/Yesterday + headers/tab; Add-entry 5 cards, no
  clipping. Insights/history byte-identical; Track = base-r2 (106px vs r1, avatar
  AA); add-entry 2456px/0.065% vs r1, ~6749px/0.168% vs r2 (text-band AA; auditor's
  6343 count-method range noted, not normalized). Fresh r1 SHAs recorded in tasks.
  6/6 LA external-pending with reasons; manifests 3-pending. 'Eligible but blocked
  as a set' applies to panel completeness, NOT to 5.2 (inspect + honest-LA only).
  Genuine-LA + owner-approval gates stay explicitly open.

## Scope guard

- Swift/protocol active; device-worker 24 tests accepted unit-only; YAML pilot-gated.
  Snapshot 4/41 until producer proof + integration land.

## 4.6 MARKED 2026-11-04 — real-probe proof fulfilled (24/41)

- Actual M4 iPad probe (simctl-list-nonce-joined) + 2 Island N/A in scope + zero
  Island files + lock required-pending; strict finalizer + shared helper + 89
  panels tests (pending/N/A/failed/genuine — the cases awaiting real-device probe).
  Genuine pixels / owner approval NOT required. Prior pending notes stand as history.
