# Protocol freeze v2 — session command envelope (planning-only, NOT implemented)

Status: Swift + Python owners explicitly AGREE; no blockers. Task 2.3 still NOT
implemented — runner owner writes golden vector(s) first after gate and shares with
Swift. No feature code written for this freeze. Clarifications stay within approved
design §4; NOT new product scope, NOT permission to drop checks. Tasks still 3/41
until 1.3 baseline gate done.

## Frozen outer envelope v2 (exact keys)

```text
{schema_version:2, run_id, session_nonce:32-lower-hex, session_domain:pinned|realtime,
 seq:0-based-int, frame, mode, request_sha256, request_json}
```

- `request_json`: canonical payload as UTF-8 STRING including trailing NL; contains
  the current full schema-1 payload internally.
- Runtime initial root WITHOUT the schema-2 envelope is rejected.
- Exact SHA = `sha256(request_json.utf8)` ONLY; outer metadata alone never changes it.
- Every ack binds full nonce/run/domain/seq/frame/mode/hash.

## Binding rules

- Outer/inner run/frame/mode must match; 7-frame list immutable; session-immutable
  fields fixed for all but frame within one domain.
- Tests assert exact raw-UTF-8 hash cross-language; semantic r1/r2 projection excludes
  volatile PAYLOAD fields only (never outer metadata).

## Transport (existing atomic-file mechanism, no new sockets/schemes/entitlements)

- Initial: fixed `Documents/capture-request.json` via existing `SCREENSHOT_REQUEST`
  token, seq 0.
- Later: queue `Documents/capture-sessions/<nonce>/command.json`, app-derived, with
  path/symlink guards; same-dir temp → atomic publish; app ATOMICALLY RENAMES/REMOVES
  the queue file BEFORE execution.
- Retained consumed-record re-observe = no-op; ANY NEW publication with old seq =
  replay (even identical bytes; no inode/mtime heuristic).

## State acks + cleanup

- Full accepted-command transcript in EVERY state ack (ready/preparing/failure once
  an active context exists) for recoverable cleanup. A no-active-context invalid state
  may report an explicit error but never ready.
- State/cleanup schema-2 adds required session identity for ready/cleaned.
- Cleanup launch keeps `SCREENSHOT_CLEANUP=<RID>` + `SCREENSHOT_CLEANUP_SHA=<HASH>`
  plus `SCREENSHOT_SESSION_NONCE=<NONCE>` `SCREENSHOT_SESSION_DOMAIN=<DOMAIN>`
  `SCREENSHOT_FINAL_SEQ=<N>`; app validates against the persisted accepted transcript
  (cleanup runs in a new process). Runner receipt = app cleanup + verified
  chrome/process/lease restoration.

## Session topology (unchanged)

- Fresh process per domain/locale/pass; one anchor per real-time 3 frames; iPad = lock
  required + N/A probe, no Island frame sessions.

## Runner surface (planned, not built)

- `capture.py run-session --device --request BASE --domain pinned|realtime --out SETROOT
  --run-id RID --geometry GEO --pinned-totals FILE` plus validated `--device-key` or
  `--island` flag. Workflow wrapper calls both domains per pass, then existing
  `finalize-run` + `finalize-two-runs`.
- Shared pure helper `scripts/screenshots/session_evidence.py`:
  `validate_run_evidence(run_dir, manifest, required_frames=None) -> list[str]` for
  finalizer/panels; no weaker duplicate verifier.
