#!/usr/bin/env python3
"""Lease-gated session execution with injectable subprocess (stdlib only).

Every simctl spawn goes through the ``run`` callable and every sleep
through ``sleeper``, so unit tests inject fakes and no real device is
ever touched without the lease. Production wires ``subprocess.run``.

Verb split (task 8.5: the temporary v1 per-frame verbs prepare_frame,
capture_app_frame, and teardown_frame were removed after the
baseline/pilot comparison; session orchestration below is the only
capture path):
- run_session: one owned device lease, one provenance resolve, one chrome
  scope, one launch per session domain; ordered queue commands with
  per-command ack binding and per-export live validation. Covers pinned
  (4 frames) and real-time (LA states, one anchor) domains.
- record_external_frame: registers the genuine Lock Screen / Island PNGs
  produced externally (authored Argent flow after handoff) with their
  capture windows. No fabrication, no OCR.
- record_pending_frame: deterministic human-handoff stubs for LA states
  without genuine pixels yet (used internally by run_session).
- finalize_run (session-receipt gated): assemble manifests, re-verify
  evidence (single pass; no automatic pass comparison — human
  inspection governs manual reruns via preserved semantic hashes).

Cleanup note: simctl-side restore (appearance/content_size/status_bar) is
implemented exactly from snapshots. Session cleanup is identity-checked
(one invocation per session, transcript-bound receipt combining app ack
with runner-verified chrome restoration, process termination, and lease
release); forced cancellation or host loss leaves a missing receipt and
therefore incomplete evidence.
"""

from __future__ import annotations

import json
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))

import inspection as insp
import output_guard as guard
import preflight as pf
import request_schema as req
import run_manifest as rm
import session as sess
import state_check as sc

# `status_bar list` outputs treated as a clean slate. QA-observed on a
# session-owned sim (no overrides): exactly
# 'Current Status Bar Overrides:\n=============================' (command
# trailing newline stripped by the runner). Anything else — including that
# header PLUS entries — aborts the run (fail-closed, never blanket-cleared).
STATUS_BAR_CLEAN_MARKERS = (
    "",
    "Current Status Bar Overrides:\n=============================",
)

POLL_TIMEOUT_S = 120.0
POLL_INTERVAL_S = 2.0
CLEANUP_TIMEOUT_S = 60.0


class FrameError(Exception):
    """Fail-closed frame execution error with a human-readable diagnostic."""


class CleanupRefused(FrameError):
    """A matching cleanup ack that refuses completion (mismatch/failure).

    Carries the ack's own status so teardown records it faithfully instead
    of collapsing to "unverified".
    """

    def __init__(self, ack_status: str, message: str):
        super().__init__(message)
        self.ack_status = ack_status


def default_run(argv: list[str]) -> Any:
    return subprocess.run(argv, capture_output=True, text=True, timeout=60)


def no_sleep(_seconds: float) -> None:
    return None


def run_dir_for(out_root: str, run_id: str) -> Path:
    return Path(out_root) / "runs" / run_id






def frame_png_path(run_dir: Path, frame: str) -> Path:
    return run_dir / "frames" / f"{frame}.png"


def frame_record_path(run_dir: Path, frame: str) -> Path:
    return run_dir / "frames" / f"{frame}.json"




def _check(proc: Any, argv: list[str], what: str) -> str:
    if getattr(proc, "returncode", 1) != 0:
        raise FrameError(
            f"{what} failed: {' '.join(argv)} -> "
            f"rc={getattr(proc, 'returncode', '?')} "
            f"stderr={getattr(proc, 'stderr', '')!r:.300}"
        )
    return (getattr(proc, "stdout", "") or "").strip()


def get_container_data(run: Callable, udid: str, bid: str) -> str:
    argv = ["xcrun", "simctl", "get_app_container", udid, bid, "data"]
    out = _check(run(argv), argv, "get_app_container")
    if not out or not out.startswith("/"):
        raise FrameError(f"get_app_container returned unusable path {out!r}")
    return out


def snapshot_chrome(run: Callable, udid: str) -> dict[str, str]:
    snap: dict[str, str] = {}
    for argv, key in (
        (["xcrun", "simctl", "status_bar", udid, "list"], "status_bar_list"),
        (["xcrun", "simctl", "ui", udid, "appearance"], "appearance"),
        (["xcrun", "simctl", "ui", udid, "content_size"], "content_size"),
    ):
        snap[key] = _check(run(argv), argv, f"snapshot {key}")
    return snap


def ensure_clean_chrome(snap: dict[str, str]) -> None:
    if snap.get("status_bar_list", "") not in STATUS_BAR_CLEAN_MARKERS:
        raise FrameError(
            "preexisting status_bar overrides detected; refusing to capture "
            "on a dirty session (clear them manually or use a session-owned "
            "simulator; runner never blanket-clears foreign overrides)"
        )


def apply_chrome(run: Callable, udid: str) -> None:
    for argv in pf.apply_commands(udid):
        _check(run(argv), argv, "apply chrome")


def launch_capture(run: Callable, udid: str, bid: str) -> str:
    argv = pf.launch_argv(udid, bid)
    return _check(run(argv), argv, "launch capture")


def restore_chrome(
    run: Callable, udid: str, snap: dict[str, str], session_overrode: bool
) -> None:
    prior_empty = snap.get("status_bar_list", "") in STATUS_BAR_CLEAN_MARKERS
    failures = []
    for argv in pf.restore_commands(
        udid,
        snap.get("appearance", "light"),
        snap.get("content_size", "large"),
        session_overrode,
        prior_empty,
    ):
        try:
            _check(run(argv), argv, "restore chrome")
        except FrameError as exc:
            failures.append(str(exc))
    if failures:
        raise FrameError("restore failures: " + "; ".join(failures))


def terminate_app(run: Callable, udid: str, bid: str) -> None:
    argv = ["xcrun", "simctl", "terminate", udid, bid]
    _check(run(argv), argv, "terminate app")


def app_provenance(run: Callable, udid: str, bid: str) -> dict[str, Any]:
    """Best-effort compiled-app identity (never raises).

    Resolves the installed .app bundle, reads CFBundleExecutable via
    plistlib, and hashes the Mach-O. Unreadable pieces are recorded as
    explicit null+reason, never silently omitted.
    """
    record: dict[str, Any] = {"bundle_id": bid, "macho_sha256": None}
    try:
        argv = ["xcrun", "simctl", "get_app_container", udid, bid]
        proc = run(argv)
        if getattr(proc, "returncode", 1) != 0:
            record["unavailable_reason"] = (
                f"get_app_container rc={getattr(proc, 'returncode', '?')}"
            )
            return record
        bundle = (getattr(proc, "stdout", "") or "").strip()
        with open(os.path.join(bundle, "Info.plist"), "rb") as fh:
            info = plistlib.load(fh)
        exe = info.get("CFBundleExecutable")
        if not exe or not isinstance(exe, str):
            record["unavailable_reason"] = "no CFBundleExecutable in Info.plist"
            return record
        record["executable"] = exe
        record["macho_sha256"] = insp.sha256_file(os.path.join(bundle, exe))
    except (OSError, ValueError) as exc:
        record["unavailable_reason"] = str(exc)[:200]
    return record


def _read_state_dict(
    docs_dir: Path, filename: str = pf.STATE_FILENAME
) -> tuple[dict | None, bytes | None]:
    try:
        raw = (docs_dir / filename).read_bytes()
        state = json.loads(raw.decode("utf-8"))
    except (OSError, ValueError, UnicodeError):
        return None, None
    return (state, raw) if isinstance(state, dict) else (None, None)


def clear_owned_state(docs_dir: Path) -> bool:
    """Remove our session-owned state file before a fresh launch.

    The file is regenerable app output scoped to this container; the
    session record preserves what matters. Returns True when removed.
    """
    try:
        (docs_dir / pf.STATE_FILENAME).unlink()
        return True
    except FileNotFoundError:
        return False
    except OSError as exc:
        raise FrameError(f"cannot clear owned state file: {exc}")












def validate_cleanup_ack(
    ack: dict, *, expect_activity_id: str | None = None
) -> list[str]:
    """Validate ack fields against the canonical CaptureCleanupState contract.

    Pinned app-clock frames must report no activities (the session ends
    strays at start and never mints system timers); each realtime la-*
    frame must list the real activity id from live state.
    """
    errs: list[str] = []
    ended = ack.get("ended_activity_ids")
    if not isinstance(ended, list) or any(
        not isinstance(i, str) for i in ended
    ):
        errs.append("ack ended_activity_ids must be a list of strings")
    elif expect_activity_id is None and ended != []:
        errs.append(
            f"pinned frame reports ended activities {ended!r}; expected none"
        )
    if ack.get("removed_session") is not True:
        errs.append(
            "ack removed_session is not true: the session directory "
            "(own SQLite/WAL/SHM) was not verifiably removed"
        )
    if expect_activity_id is not None and (
        not isinstance(ended, list) or expect_activity_id not in ended
    ):
        errs.append(
            f"real activity {expect_activity_id!r} not in ended_activity_ids: "
            "a capture-owned banner may still be live"
        )
    err = ack.get("error")
    if isinstance(err, dict) and err.get("code"):
        errs.append(f"ack carries error {err['code']!r}")
    return errs








def _checked_session_binding(binding: dict, frame: str) -> dict[str, Any]:
    """Validate an optional session binding for a frame record.

    Callers without a session pass None and keep the exact legacy record.
    A binding carries {session_nonce, session_domain, seq} and is echoed
    so session_evidence can join the frame to its session receipt.
    """
    if not isinstance(binding, dict):
        raise FrameError("session_binding must be an object")
    import session as sess

    nonce = binding.get("session_nonce")
    if sess.validate_nonce(nonce):
        raise FrameError(f"invalid session_nonce for {frame!r}")
    domain = binding.get("session_domain")
    if domain not in sess.SESSION_DOMAINS:
        raise FrameError(f"unknown session_domain for {frame!r}")
    seq = binding.get("seq")
    if isinstance(seq, bool) or not isinstance(seq, int) or seq < 0:
        raise FrameError(f"invalid seq for {frame!r}")
    return {"session_nonce": nonce, "session_domain": domain, "seq": seq}


def _checked_device_key(device_key: str | None, frame: str,
                        in_session: bool, prior_path: Path) -> dict[str, Any]:
    """Carry trusted device identity across genuine replacement.

    An explicit key must be a clean token and must agree with the
    overwritten stub record when one carries a key (re-keying a frame
    fails closed). Without an explicit key, the prior record's verified
    disk binding is inherited so session unanimity survives pending to
    genuine replacement. Session outputs never tolerate a missing key:
    with no explicit key and no prior binding, session registration
    fails; v1 records without any key keep the exact legacy shape.
    """
    prior_key: str | None = None
    try:
        prior = json.loads(prior_path.read_text(encoding="utf-8"))
        if isinstance(prior, dict) and isinstance(
                prior.get("device_key"), str) and prior["device_key"]:
            prior_key = prior["device_key"]
    except (OSError, ValueError):
        prior_key = None
    if device_key is not None:
        if not isinstance(device_key, str) or not device_key \
                or ".." in device_key or "/" in device_key:
            raise FrameError(f"invalid device_key for {frame!r}")
        if prior_key is not None and prior_key != device_key:
            raise FrameError(
                f"refusing to re-key {frame!r} from {prior_key!r} to "
                f"{device_key!r}")
        return {"device_key": device_key}
    if prior_key is not None:
        return {"device_key": prior_key}
    if in_session:
        raise FrameError(
            f"session genuine registration for {frame!r} carries no "
            "device_key and the overwritten stub has none; refusing to "
            "leave session outputs keyless")
    return {}


def record_external_frame(
    *,
    run_dir: Path,
    frame: str,
    png_src: str,
    captured_at_iso: str,
    state: dict,
    request: dict,
    request_sha256: str,
    pinned_totals: dict | None = None,
    expected_geometry: tuple[int, int] = req.PILOT_GEOMETRY,
    device_udid: str = "unknown",
    mask: str | None = None,
    session_binding: dict | None = None,
    device_key: str | None = None,
    state_archive: str | None = None,
) -> dict[str, Any]:
    """Register an externally produced PNG (genuine Lock Screen / Island capture).

    No device I/O. Fails unless the PNG has native geometry and the state is
    ready (with pin). The record carries capture_window
    {started_at, captured_at_iso} only — there is no timer reading anywhere
    in the pipeline. `mask` documents the capture policy
    the external producer must have used (None = per-frame default:
    --mask=black for la-compact/la-expanded, simctl default otherwise)
    and is recorded for audit, never inferred from pixels.
    """
    if frame not in req.LA_FRAMES:
        raise FrameError(
            f"record-external-frame serves {list(req.LA_FRAMES)!r} only"
        )
    src = Path(png_src)
    if not src.is_file():
        raise FrameError(f"external PNG not found: {png_src}")
    try:
        dims = insp.png_dimensions(str(src))
    except insp.InspectionError as exc:
        raise FrameError(str(exc))
    if dims != (expected_geometry[0], expected_geometry[1]):
        raise FrameError(f"external PNG geometry {dims} != {expected_geometry}")
    verdict, v_errs = sc.validate_state_dict(state, request, request_sha256, pinned_totals)
    if verdict != sc.OK:
        raise FrameError(f"state verdict {verdict}: {'; '.join(v_errs) or 'not ready'}")
    la = state.get("live_activity")
    # Fail closed on the session anchor and timestamps: the state must
    # carry the real anchor and both timestamps must parse as aware ISO.
    if not isinstance(la, dict):
        raise FrameError("state live_activity block is required before validation")
    if not la.get("started_at"):
        raise FrameError("state live_activity.started_at (real anchor) is required")
    try:
        capture_dt = insp.parse_aware_iso(captured_at_iso)
        start_dt = insp.parse_aware_iso(la.get("started_at"))
    except insp.InspectionError as exc:
        raise FrameError(str(exc))
    if (capture_dt - start_dt).total_seconds() < -1:
        raise FrameError("capture timestamp predates the real start anchor")
    try:
        resolved_mask = pf.resolve_screenshot_mask(frame, mask)
    except ValueError as exc:
        raise FrameError(str(exc))
    dest = frame_png_path(run_dir, frame)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest)
    # Provenance comes from the overwritten stub record (v2 session flow);
    # the removed per-frame session files are never consulted.
    try:
        prior = json.loads(
            frame_record_path(run_dir, frame).read_text(encoding="utf-8")
        )
        session_provenance = prior.get("app_provenance") \
            if isinstance(prior, dict) else None
    except (OSError, ValueError):
        session_provenance = None
    record = {
        "schema_version": 1,
        "frame": frame,
        "mode": req.MODE_REALTIME,
        "device_udid": device_udid,
        "run_id": request.get("run_id"),
        "deck_version": request.get("deck_version"),
        "treatment": request.get("treatment"),
        "request_sha256": request_sha256,
        "request_semantic_sha256": req.semantic_sha256(request),
        "screenshot_sha256": insp.sha256_file(str(dest)),
        "geometry": {"width": dims[0], "height": dims[1]},
        "expected_totals": state.get("expected_totals"),
        "capture": "external-lock-screen",
        "capture_window": {
            "started_at": la.get("started_at"),
            "captured_at_iso": captured_at_iso,
        },
        "screenshot_mask": resolved_mask or "default",
    }
    if session_binding is not None:
        record.update(_checked_session_binding(session_binding, frame))
    record.update(_checked_device_key(device_key, frame,
                                      session_binding is not None,
                                      frame_record_path(run_dir, frame)))
    if state_archive is not None:
        if not isinstance(state_archive, str) or not state_archive \
                or ".." in state_archive \
                or state_archive.startswith("/"):
            raise FrameError("state_archive must be a safe run-relative path")
        record["state_archive"] = state_archive
    if isinstance(session_provenance, dict):
        record["app_provenance"] = session_provenance
    frame_record_path(run_dir, frame).write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return record


def record_pending_frame(
    *,
    run_dir: Path,
    frame: str,
    png_src: str,
    captured_at_iso: str,
    request: dict,
    request_sha256: str,
    reason: str,
    pinned_totals: dict | None = None,
    expected_geometry: tuple[int, int] = req.PILOT_GEOMETRY,
    device_udid: str = "unknown",
    mask: str | None = None,
    session_binding: dict | None = None,
) -> dict[str, Any]:
    """Register a simctl export as a deterministic human handoff (no OCR).

    CI simctl cannot produce genuine Lock Screen / island pixels
    (prepare leaves the capture app foregrounded; the island pill hides
    when the app is foreground), so `read_timer.py` would fail closed and
    abort the leg. This helper binds the exported PNG (hash + geometry,
    like every other record) but carries NO `capture_window`,
    so `finalize_run` reports the frame as
    needs-inspection ("genuine pixels not registered") instead
    of failing. The genuine pixels arrive later via
    `record-external-frame`, which overwrites this stub record. `reason`
    is required so the handoff is never silent.
    """
    if frame not in req.LA_FRAMES:
        raise FrameError(
            f"record-pending-frame serves {list(req.LA_FRAMES)!r} only"
        )
    if not isinstance(reason, str) or not reason.strip():
        raise FrameError("record-pending-frame requires a non-empty --reason")
    src = Path(png_src)
    if not src.is_file():
        raise FrameError(f"pending PNG not found: {png_src}")
    try:
        dims = insp.png_dimensions(str(src))
    except insp.InspectionError as exc:
        raise FrameError(str(exc))
    if dims != (expected_geometry[0], expected_geometry[1]):
        raise FrameError(f"pending PNG geometry {dims} != {expected_geometry}")
    try:
        resolved_mask = pf.resolve_screenshot_mask(frame, mask)
    except ValueError as exc:
        raise FrameError(str(exc))
    dest = frame_png_path(run_dir, frame)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest)
    record = {
        "schema_version": 1,
        "frame": frame,
        "mode": req.MODE_REALTIME,
        "device_udid": device_udid,
        "run_id": request.get("run_id"),
        "deck_version": request.get("deck_version"),
        "treatment": request.get("treatment"),
        "request_sha256": request_sha256,
        "request_semantic_sha256": req.semantic_sha256(request),
        "screenshot_sha256": insp.sha256_file(str(dest)),
        "geometry": {"width": dims[0], "height": dims[1]},
        "expected_totals": pinned_totals,
        "capture": "external-lock-screen-pending",
        "captured_at_iso": captured_at_iso,
        "pending_reason": reason.strip(),
        "screenshot_mask": resolved_mask or "default",
    }
    if session_binding is not None:
        record.update(_checked_session_binding(session_binding, frame))
    frame_record_path(run_dir, frame).write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return record


def load_frame_record(run_dir: Path, frame: str) -> dict:
    try:
        obj = json.loads(frame_record_path(run_dir, frame).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise FrameError(f"frame record missing/unreadable for {frame!r}: {exc}")
    if not isinstance(obj, dict):
        raise FrameError(f"frame record for {frame!r} must be an object")
    return obj


def _session_mode_for_records(records: list[dict], run_dir: Path) -> str:
    """Classify a run for finalization: 'session', 'v1', or 'mixed'.

    'session' when any frame record carries session binding or any session
    receipt exists. 'mixed' (fatal, never downgraded) when only part of the
    run is session-bound. 'v1' is the legacy keyless path (no session
    binding, no receipts); finalize_run explicitly rejects it in this
    session-only runtime (rerun via run-session).
    """
    bound = [bool(r.get("session_nonce")) for r in records]
    sessions_dir = run_dir / "sessions"
    receipts = sorted(sessions_dir.glob("*.receipt.json")) \
        if sessions_dir.is_dir() else []
    if any(bound) or receipts:
        return "session" if all(bound) else "mixed"
    return "v1"


def _require_session_evidence(run_dir: Path, records: list[dict]) -> None:
    """Fatal session-receipt gate (task 4.4): missing/partial/tampered.

    The shared validator must pass; any error raises FrameError so EVERY
    dependent frame is blocked (no manifest, never needs-inspection): a
    session without a complete combined receipt is contaminated. Honest
    pending LA handoffs still yield needs-inspection downstream via the
    normal pending path — but only after receipts verify.
    """
    import session_evidence as sev

    manifest_skel = {"frames": records,
                     "geometry": (records[0].get("geometry") or {})}
    errs = sev.validate_run_evidence(run_dir, manifest_skel)
    if errs:
        raise FrameError(
            "session evidence invalid; every dependent frame blocked: "
            + "; ".join(errs[:5]))


def _require_locale_binding(run_dir: Path, records: list[dict],
                            run_id: str) -> str:
    """Fail-closed run-locale binding from archived session commands.

    Every archived session command envelope under run_dir/requests is
    validated with the shared session parser (schema, exact-bytes hash,
    outer/inner identity binding — no duplicated envelope logic), must
    belong to this run, and must bind a frame record by (frame,
    request_sha256). All bound locales must be unanimous; that single
    locale is returned for the manifest `locale` field (exact key,
    envelope-derived — never a free claim, never inferred from paths).
    A missing archive, a rejected envelope, or divergent locales fails
    closed (rerun via run-session).
    """
    req_dir = run_dir / "requests"
    env_paths = sorted(req_dir.glob("session-*.envelope.json")) \
        if req_dir.is_dir() else []
    if not env_paths:
        raise FrameError(
            "no archived session command envelopes under requests/; "
            "run locale unattested (rerun via run-session)")
    pairs = {(r.get("frame"), r.get("request_sha256")) for r in records}
    seen: set[str] = set()
    for path in env_paths:
        if path.is_symlink():
            raise FrameError(
                f"archived command {path.name} is a symlink; "
                "refusing escape")
        try:
            env = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise FrameError(
                f"archived command {path.name} unreadable: {exc}")
        errs = sess.validate_envelope(env)
        if errs:
            raise FrameError(
                f"archived command {path.name} rejected: {errs[0]}")
        if env.get("run_id") != run_id:
            raise FrameError(
                f"archived command {path.name} run_id "
                f"{env.get('run_id')!r} != run {run_id!r} (stale or "
                "foreign command refused)")
        try:
            inner = sess.parse_envelope_payload(env)
        except sess.SessionError as exc:
            raise FrameError(
                f"archived command {path.name} payload rejected: {exc}")
        if (env.get("frame"), env.get("request_sha256")) not in pairs:
            raise FrameError(
                f"archived command {path.name} matches no frame record "
                "(stale or foreign command refused)")
        seen.add(inner.get("locale"))
    if len(seen) != 1:
        raise FrameError(
            f"archived commands span locales {sorted(str(v) for v in seen)!r} "
            "(cross-locale run refused)")
    return next(iter(seen))


def _session_ipad_records_or_raise(
    run_dir: Path, strict_err: FrameError
) -> tuple[list[dict], list[str]]:
    """iPad session fallback: present records + N/A island frames.

    Only missing la-compact/la-expanded records with an attested probe
    file present qualify; every present record must be session-bound to one
    run_id and one no-island catalog device. Anything else re-raises the
    original strict error. Full probe validation happens later in the
    session-evidence gate (fatal); this only decides the frame set.
    """
    import session as _sess

    present: dict[str, dict] = {}
    for frame in req.PILOT_FRAMES:
        try:
            present[frame] = load_frame_record(run_dir, frame)
        except FrameError:
            continue
    missing = [f for f in req.PILOT_FRAMES if f not in present]
    if "la-compact" in present or "la-expanded" in present:
        raise FrameError(
            "island frame records filed for an iPad run; N/A island "
            "states must have no records or pixels "
            "(fabricated evidence refused)")
    if not missing or any(
            f not in ("la-compact", "la-expanded") for f in missing):
        raise strict_err
    recs = [present[f] for f in req.PILOT_FRAMES if f in present]
    if not all(isinstance(r, dict) and r.get("session_nonce") for r in recs):
        raise strict_err
    if len({r.get("run_id") for r in recs}) != 1:
        raise strict_err
    keys = {r.get("device_key") for r in recs}
    if len(keys) != 1:
        raise strict_err
    entry = _sess.DEVICE_CATALOG.get(next(iter(keys)))
    if entry is None or entry.get("island") is not False:
        raise strict_err
    if not (run_dir / "sessions" / "island-probe.json").is_file():
        raise strict_err
    return recs, missing


def finalize_run(
    run_dir: Path, provenance: dict | None = None
) -> tuple[dict, list[str]]:
    """Assemble run-manifest.json. Returns (manifest, pending_evidence).

    Every frame PNG is rehashed and rebound to its record (existence,
    hash, geometry, frame id); deck/treatment/geometry must agree across
    records. Missing/tampered files and record mismatches are fatal
    FrameErrors, never needs-inspection. Missing human LA evidence yields
    needs-inspection instead.

    All finalization requires strict session evidence: the shared
    session-evidence validator must pass, else FrameError blocks every
    dependent frame — missing, partial, or tampered receipts are fatal
    even when LA evidence is honestly pending. Legacy per-frame runs
    (keyless records, per-frame teardowns, no session receipts) and
    mixed session/v1 runs are explicitly rejected (task 8.5 removed the
    temporary v1 comparison path); historical captures must rerun via
    run-session.
    """
    try:
        records = [load_frame_record(run_dir, f) for f in req.PILOT_FRAMES]
        na_frames = []
        island_probe = None
    except FrameError as strict_err:
        # iPad session runs file no island frames by design (N/A with an
        # attested probe, never placeholders). Anything else re-raises the
        # original strict error — missing files are never inferred as N/A.
        records, na_frames = _session_ipad_records_or_raise(
            run_dir, strict_err)
        try:
            island_probe = json.loads(
                (run_dir / "sessions" / "island-probe.json").read_text(
                    encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise FrameError(f"island probe unreadable: {exc}")
    want_order = [f for f in req.PILOT_FRAMES if f not in na_frames]
    if [r.get("frame") for r in records] != want_order:
        raise FrameError(
            f"frame record mismatch: wanted order {want_order!r}, got "
            f"{[r.get('frame') for r in records]!r}"
        )
    for key in ("deck_version", "treatment"):
        values = {json.dumps(r.get(key), sort_keys=True) for r in records}
        if len(values) != 1:
            raise FrameError(f"{key} drifts across frames of one run")
    geometries = set()
    for rec in records:
        png = frame_png_path(run_dir, rec["frame"])
        if not png.is_file():
            raise FrameError(f"screenshot file missing for {rec['frame']!r}")
        actual_sha = insp.sha256_file(str(png))
        if actual_sha != rec.get("screenshot_sha256"):
            raise FrameError(
                f"screenshot for {rec['frame']!r} changed after capture "
                "(tampered capture binding)"
            )
        try:
            dims = insp.png_dimensions(str(png))
        except insp.InspectionError as exc:
            raise FrameError(str(exc))
        claimed = rec.get("geometry") or {}
        if (dims[0], dims[1]) != (claimed.get("width"), claimed.get("height")):
            raise FrameError(
                f"screenshot geometry {dims} != record for {rec['frame']!r}"
            )
        if dims != (req.PILOT_GEOMETRY[0], req.PILOT_GEOMETRY[1]):
            if dims not in req.MATRIX_GEOMETRIES:
                raise FrameError(
                    f"screenshot geometry {dims} not in supported matrix "
                    f"{sorted(req.MATRIX_GEOMETRIES)}"
                )
            # Non-pilot matrix geometry: authorization lives at the CLI
            # approval gate (ipad kind); finalize records truthfully and
            # never fabricates pilot dimensions.
        geometries.add(dims)
    totals = [json.dumps(r.get("expected_totals"), sort_keys=True) for r in records]
    if len(set(totals)) != 1:
        raise FrameError("expected totals drift across frames of one run")
    mode = _session_mode_for_records(records, run_dir)
    if mode == "mixed":
        raise FrameError(
            "mixed session/v1 frame records in one run; refusing silent "
            "downgrade")
    if mode != "session":
        # Task 8.5: the temporary v1 per-frame comparison path is removed.
        # Historical per-frame captures (keyless records, per-frame
        # teardowns, no session receipts) are explicitly rejected: rerun
        # via run-session to produce session evidence.
        raise FrameError(
            "legacy per-frame runs rejected: no session evidence "
            "(session_nonce/receipts); rerun via run-session")
    _require_session_evidence(run_dir, records)
    run_locale = _require_locale_binding(run_dir, records, run_dir.name)
    pending: list[str] = []
    present_la = [f for f in req.LA_FRAMES if f not in na_frames]
    if "la-lock" not in present_la:
        # The Lock Screen state is required on every device; only island
        # states can be N/A (with an attested probe).
        raise FrameError("la-lock frame required; never not-applicable")
    for la_frame in present_la:
        la = next(r for r in records if r["frame"] == la_frame)
        cw = la.get("capture_window")
        # Pending only when no genuine pixels at all: a pending handoff
        # stub (or any record without a genuine capture window) stays
        # needs-inspection. Genuine LA is accepted on pixels + session
        # binding alone — there is no timer reading to check.
        if la.get("capture") != "external-lock-screen" \
                or not isinstance(cw, dict) \
                or "started_at" not in cw \
                or "captured_at_iso" not in cw:
            pending.append(f"{la_frame}: genuine pixels not registered")
            continue
        try:
            insp.parse_aware_iso(cw["captured_at_iso"])
            insp.parse_aware_iso(cw["started_at"])
        except (insp.InspectionError, KeyError, TypeError) as exc:
            raise FrameError(f"{la_frame} capture window malformed: {exc}")
    # Session receipts were gated fatally above; no legacy per-frame
    # teardown files exist or are consulted (removed in task 8.5).
    if provenance is None:
        pending.append("provenance not declared (commit base + dirty flag required)")
        provenance_block: dict[str, Any] = {"declared": False}
    else:
        if (
            not isinstance(provenance.get("commit_base"), str)
            or not provenance["commit_base"]
            or not isinstance(provenance.get("dirty"), bool)
        ):
            raise FrameError(
                "provenance must be {commit_base: non-empty string, dirty: bool}"
            )
        provenance_block = {
            "repo_commit_base": provenance["commit_base"],
            "dirty": provenance["dirty"],
            "source_note": (
                "uncommitted source possible; repo HEAD is not implied "
                "as the exact build source"
            ),
        }
    session_run_id = run_dir.name
    manifest = rm.assemble_run_manifest(
        session_run_id,
        records[0].get("device_udid", "unknown"),
        records[0].get("deck_version", req.PILOT_DECK_VERSION),
        records[0].get("treatment", req.PILOT_TREATMENT),
        (records[0]["geometry"]["width"], records[0]["geometry"]["height"]),
        records,
        na_frames=na_frames or None,
        island_probe=island_probe,
    )
    # Manifest locale (exact coordinated key): bound above from the
    # validated unanimous session envelopes — an envelope-derived
    # claim, never a free string and never inferred from paths. The
    # consumer requires it to equal the cell language.
    manifest["locale"] = run_locale
    manifest["status"] = "needs-inspection" if pending else "complete"
    manifest["pending_evidence"] = pending
    app_prov = records[0].get("app_provenance")
    if isinstance(app_prov, dict):
        provenance_block["app"] = app_prov
    else:
        provenance_block["app"] = {"macho_sha256": None,
                                   "unavailable_reason": "not recorded"}
    manifest["provenance"] = provenance_block
    manifest["cleanup"] = (
        "session receipts verified per domain (pinned+realtime); "
        "combined app-cleanup + runner chrome/process/lease receipt "
        "gates every dependent frame"
    )
    (run_dir / "run-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest, pending


# --- Session orchestration (frozen v2; tasks 2.1/4.1-4.4) ---

SESSION_PENDING_REASON = (
    "CI simctl pixels; human handoff (session); "
    "genuine pixels via record-external-frame"
)


def _classify_spawn(argv: Any) -> str:
    """Semantic command category for the spawn trail (no raw argv kept).

    Returns a fixed label such as "ui-appearance-query" or
    "launch-cleanup" for known simctl shapes, else "simctl-unknown".
    Only the label is recorded — raw argv, paths, nonces, launch
    args, and stderr never enter persisted stats. The ephemeral scan
    below is classification only, never stored.
    """
    try:
        parts = list(argv)  # type: ignore[arg-type]
    except TypeError:
        return "simctl-unknown"
    if len(parts) < 3 or parts[0] != "xcrun" or parts[1] != "simctl":
        return "simctl-unknown"
    verb = parts[2]
    if verb == "list":
        return "device-list"
    if verb == "get_app_container":
        return "get-app-container"
    if verb == "status_bar":
        sub = parts[4] if len(parts) > 4 else ""
        if sub == "list":
            return "status-bar-list"
        if sub == "clear":
            return "status-bar-clear"
        return "status-bar-set"
    if verb == "ui":
        field = parts[4] if len(parts) > 4 else ""
        mutating = len(parts) > 5
        if field == "appearance":
            return "ui-appearance-set" if mutating else "ui-appearance-query"
        if field == "content_size":
            return ("ui-content-size-set" if mutating
                    else "ui-content-size-query")
        return "simctl-unknown"
    if verb == "launch":
        for part in parts:
            if isinstance(part, str) \
                    and part.startswith("SCREENSHOT_CLEANUP="):
                return "launch-cleanup"
        return "launch-capture"
    if verb == "io":
        return "screenshot-export"
    if verb == "terminate":
        return "terminate-app"
    return "simctl-unknown"


def _counted(run: Callable, argv: list[str],
             stats: sess.PhaseStats | None) -> Any:
    """Run one simctl subprocess, counting it when stats are present.

    Spawn failures (a hang past the runner timeout, a missing binary)
    are fail-closed FrameErrors, never raw tracebacks: run_session's
    receipt accounting only tracks FrameError, so a bare
    TimeoutExpired/OSError would escape with a "complete" receipt for a
    truncated transcript (cold-run iphone63/ru-r1: appearance query hung
    60s, receipt claimed complete with 1 of 4 frames and no failures).
    Same convention as run_device_worker.call and preflight --execute.
    No timeout, deadline, or retry change here.

    Every spawn also appends one bounded trail entry (semantic
    category, active phase, start-relative-ms, duration-ms, outcome,
    return code where available) on the runner monotonic clock,
    including timeout/OSError events recorded in the finally path.
    The failure message names the category only: exception reprs may
    echo raw argv (paths, nonces, launch tokens), so they are never
    interpolated. Counter meaning ("simctl_spawn" per successful
    spawn) is unchanged.
    """
    category = _classify_spawn(argv)
    if stats is None:
        try:
            return run(argv)
        except (subprocess.TimeoutExpired, OSError) as exc:
            raise FrameError(
                f"simctl spawn failed: {category} "
                f"({type(exc).__name__})"
            )
    t_start = stats.now()
    outcome = "ok"
    rc: int | None = None
    try:
        proc = run(argv)
        raw_rc = getattr(proc, "returncode", None)
        rc = raw_rc if isinstance(raw_rc, int) \
            and not isinstance(raw_rc, bool) else None
        return proc
    except subprocess.TimeoutExpired as exc:
        outcome = "timeout"
        raise FrameError(
            f"simctl spawn failed: {category} ({type(exc).__name__})"
        )
    except OSError as exc:
        outcome = "oserror"
        raise FrameError(
            f"simctl spawn failed: {category} ({type(exc).__name__})"
        )
    finally:
        t_end = stats.now()
        try:
            stats.note_spawn(category=category, outcome=outcome,
                             t_start=t_start, t_end=t_end, rc=rc)
        except sess.SessionError:
            pass  # diagnostics never break fail-closed capture
        if outcome == "ok":
            stats.count("simctl_spawn")


def _checked_session_run_args(device_key: str,
                              geometry: tuple[int, int] | None,
                              island_available: bool | None
                              ) -> tuple[tuple[int, int], bool]:
    """Validate --device-key against the fail-closed catalog.

    Returns (geometry, island_available). An explicit geometry must match
    the catalog entry; an explicit island flag must agree with it.
    """
    entry = sess.DEVICE_CATALOG.get(device_key)
    if entry is None:
        raise FrameError(
            f"unknown device_key {device_key!r}; want one of "
            f"{sorted(sess.DEVICE_CATALOG)}")
    want_geo = entry["geometry"]
    if geometry is not None and tuple(geometry) != tuple(want_geo):
        raise FrameError(
            f"geometry {tuple(geometry)} != catalog geometry {tuple(want_geo)} "
            f"for device_key {device_key!r}")
    want_island = bool(entry["island"])
    if island_available is not None and bool(island_available) != want_island:
        raise FrameError(
            f"island flag {island_available!r} contradicts catalog for "
            f"{device_key!r} (island={want_island})")
    return tuple(want_geo), want_island if island_available is None \
        else bool(island_available)


def poll_session_ack(
    docs_dir: Path,
    *,
    want_nonce: str,
    want_domain: str,
    want_seq: int,
    want_sha: str,
    want_frame: str,
    timeout_s: float = POLL_TIMEOUT_S,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    on_poll: Callable[[], None] | None = None,
) -> tuple[dict, int]:
    """Await the session ack bound to one command envelope.

    Stale identities are ignored; `preparing` keeps polling with identity
    still bound; terminal session states fail promptly. The optional
    on_poll hook models the app watcher in tests (production: the real app
    claims and acks on device). Raises FrameError on refusal or deadline.
    """
    deadline = clock() + timeout_s
    attempts = 0
    while True:
        attempts += 1
        if on_poll is not None:
            on_poll()
        state, _raw = _read_state_dict(docs_dir)
        if (
            state is not None
            and state.get("session_nonce") == want_nonce
            and state.get("session_domain") == want_domain
            and state.get("seq") == want_seq
            and state.get("request_sha256") == want_sha
            and state.get("frame") == want_frame
        ):
            status = state.get("status")
            if status == "ready":
                return state, attempts
            if status == "preparing" or status == "presenting":
                pass  # keep polling; identity stays bound
            else:
                detail = ""
                err = state.get("error")
                if isinstance(err, dict) and err.get("code"):
                    detail = f": {err['code']}"
                raise FrameError(
                    f"session command {want_frame}#{want_seq} ended "
                    f"({status}{detail}) after {attempts} poll(s)"
                )
        if clock() >= deadline:
            raise FrameError(
                f"session ack for {want_frame}#{want_seq} never arrived after "
                f"{attempts} poll(s) ({timeout_s}s); no screenshot taken"
            )
        sleeper(interval_s)


def _ack_transcript_covers(ack: dict, envelopes: list[dict]) -> list[str]:
    """Require the cleanup ack to archive every accepted command.

    The app must persist the accepted transcript before queue leftovers
    are removed: an ack whose transcript is missing, empty, or drops any
    published seq/frame/sha cannot prove what it cleaned. Pure check over
    the ack dict; the runner's own transcript stays authoritative for the
    receipt, this corroborates the app's independent record.
    """
    transcript = ack.get("transcript")
    if not isinstance(transcript, list) or not transcript:
        return ["cleanup ack carries no accepted-command transcript"]
    errs: list[str] = []
    for env in envelopes:
        if not any(isinstance(row, dict) and row.get("seq") == env.get("seq")
                   and row.get("frame") == env.get("frame")
                   and row.get("request_sha256") == env.get("request_sha256")
                   for row in transcript):
            errs.append(
                f"cleanup transcript drops seq {env.get('seq')} "
                f"({env.get('frame')!r}); app archive incomplete")
    return errs


def _require_queue_removal(ack: dict) -> list[str]:
    """Session cleanup must prove owned-queue removal (fail closed).

    Every `cleaned` ack carries removed_session_queue:true from the
    app's identity-scoped removal of capture-sessions/<nonce> (consumed
    records, end marker). Missing (fixed old acks) or false stays
    partial: a cleaned session with leftovers is contaminated. Legacy
    per-frame runs carry no session cleanup and are rejected at
    finalization (session-only runtime).
    """
    if ack.get("removed_session_queue") is not True:
        return ["cleanup ack does not prove owned-queue removal "
                "(removed_session_queue != true; fixed acks stay fixed)"]
    return []


def poll_session_cleanup_ack(
    docs_dir: Path,
    *,
    run_id: str,
    request_sha: str,
    want_nonce: str,
    want_domain: str,
    want_final_seq: int,
    timeout_s: float = CLEANUP_TIMEOUT_S,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> tuple[dict, int]:
    """Await the session cleanup ack bound to nonce/domain/final-seq.

    Stale or foreign acks are ignored; mismatch/failure/unknown fail
    promptly via CleanupRefused. Raises FrameError on deadline.
    """
    deadline = clock() + timeout_s
    attempts = 0
    while True:
        attempts += 1
        ack, _raw = _read_state_dict(docs_dir, filename=pf.CLEANUP_FILENAME)
        if (
            ack is not None
            and ack.get("run_id") == run_id
            and ack.get("request_sha256") == request_sha
            and ack.get("session_nonce") == want_nonce
            and ack.get("session_domain") == want_domain
            and ack.get("final_seq") == want_final_seq
        ):
            status = ack.get("status")
            if status == "cleaned":
                return ack, attempts
            detail = ""
            err = ack.get("error")
            if isinstance(err, dict) and err.get("code"):
                detail = f": {err['code']}"
            raise CleanupRefused(
                status,
                f"session cleanup refused ({status}{detail}) after "
                f"{attempts} poll(s); nothing was touched on device",
            )
        if clock() >= deadline:
            raise FrameError(
                f"session cleanup ack never arrived after {attempts} poll(s) "
                f"({timeout_s}s)"
            )
        sleeper(interval_s)


def _read_device_entry(
    run: Callable,
    udid: str,
    stats: sess.PhaseStats | None = None,
) -> dict:
    """Read-only simctl device listing; return OUR device's entry.

    Fail closed on spawn failure, malformed output, or absent UDID.
    Shared core for pre-capture verification and island probes.
    """
    argv = ["xcrun", "simctl", "list", "-j", "devices"]
    proc = _counted(run, argv, stats)
    if getattr(proc, "returncode", 1) != 0:
        raise FrameError(
            f"simctl list failed rc={getattr(proc, 'returncode', '?')}; "
            "island capability unattested")
    try:
        listing = json.loads(getattr(proc, "stdout", "") or "")
    except ValueError as exc:
        raise FrameError(f"simctl list output malformed: {exc}; unattested")
    if not isinstance(listing, dict) or not isinstance(
            listing.get("devices"), dict):
        raise FrameError("simctl list shape unexpected; unattested")
    found: dict | None = None
    for _runtime, entries in listing["devices"].items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict) and entry.get("udid") == udid:
                found = entry
                break
        if found is not None:
            break
    if found is None:
        raise FrameError(
            f"owned device {udid!r} absent from simctl list; unattested")
    return found


def _attest_device(
    run: Callable,
    udid: str,
    *,
    device_key: str,
    geometry: tuple[int, int],
    stats: sess.PhaseStats | None = None,
) -> tuple[dict, bool]:
    """Attest the owned device against the catalog (shared core).

    Returns (simctl entry, island flag) after full agreement: actual
    model identifier in the catalog's model set, island expectation
    agreement, and geometry agreement. Every divergence fails closed.
    """
    found = _read_device_entry(run, udid, stats)
    model_id = found.get("deviceTypeIdentifier")
    try:
        island = sess.island_for_model(model_id)
    except sess.SessionError as exc:
        raise FrameError(f"{exc}; unattested")
    entry = sess.DEVICE_CATALOG.get(device_key)
    if entry is None:
        raise FrameError(f"unknown device_key {device_key!r}")
    model_errs = sess.check_catalog_model(device_key, model_id,
                                          found.get("name"))
    if model_errs:
        raise FrameError(f"{model_errs[0]}; unattested")
    if bool(entry["island"]) != island:
        raise FrameError(
            f"attested island={island} for model contradicts catalog "
            f"device_key {device_key!r}; unattested")
    if tuple(geometry) != tuple(entry["geometry"]):
        raise FrameError(
            f"session geometry {tuple(geometry)} != catalog geometry "
            f"{tuple(entry['geometry'])} for {device_key!r}; unattested")
    return found, island


def verify_owned_device(
    run: Callable,
    udid: str,
    *,
    device_key: str,
    geometry: tuple[int, int],
    stats: sess.PhaseStats | None = None,
) -> dict[str, Any]:
    """Pre-capture gate for EVERY session: all keys, both domains.

    Verifies the actual owned UDID's simctl-reported model against the
    requested catalog (identifier set, island agreement, geometry) BEFORE
    any capture — including pinned and no-N/A phones, not only iPad N/A
    probes. A fresh 16 Pro Max (or any non-cataloged model) never passes
    for iphone69 however matching its geometry. Returns the attestation
    summary recorded on the session record.
    """
    found, island = _attest_device(
        run, udid, device_key=device_key, geometry=geometry, stats=stats)
    return {
        "deviceTypeIdentifier": found.get("deviceTypeIdentifier"),
        "name": found.get("name"),
        "udid": udid,
        "island": island,
    }


def probe_island_capability(
    run: Callable,
    udid: str,
    *,
    device_key: str,
    run_id: str,
    session_nonce: str,
    geometry: tuple[int, int],
    stats: sess.PhaseStats | None = None,
) -> dict[str, Any]:
    """Attest Dynamic Island capability against the OWNED device.

    Shared attestation core, then the probe record. Fail closed on every
    divergence; see verify_owned_device for the pre-capture gate used on
    every session. Real-device proof belongs to pilot 5.x; unit/fake
    tests cover every failure branch here.
    """
    found, island = _attest_device(
        run, udid, device_key=device_key, geometry=geometry, stats=stats)
    entry = sess.DEVICE_CATALOG[device_key]
    model_id = found.get("deviceTypeIdentifier")
    return {
        "schema_version": 1,
        "device_key": device_key,
        "island_available": island,
        "reason": ("capability probe: no Dynamic Island"
                   if not island else
                   "capability probe: Dynamic Island present"),
        "run_id": run_id,
        "session_nonce": session_nonce,
        "geometry": {"width": geometry[0], "height": geometry[1]},
        "model": {
            "deviceTypeIdentifier": model_id,
            "name": found.get("name"),
            "udid": udid,
        },
        "source": "simctl-list",
    }


def _verify_session_presentation(run: Callable, udid: str) -> None:
    """Per-frame chrome check: required light/large must still hold."""
    for argv, key, want in (
        (["xcrun", "simctl", "ui", udid, "appearance"], "appearance", "light"),
        (["xcrun", "simctl", "ui", udid, "content_size"], "content_size",
         "large"),
    ):
        proc = run(argv)
        got = (getattr(proc, "stdout", "") or "").strip()
        if getattr(proc, "returncode", 1) != 0 or got != want:
            raise FrameError(
                f"chrome drift: {key} is {got!r}, want {want!r}; "
                "failing the session rather than clearing unknown settings"
            )


# --- Live capture inside hold-open realtime sessions (genuine LA pixels) ---

# Hold-open window: the session stays RUNNING with its verified anchor while
# the live-capture driver runs the button dance, and no cleanup is issued
# until the driver finishes explicitly (the stock auto-clean window is what
# previously killed the activity mid-dance, ~13-17s). The bound equals the
# existing POLL deadline; every driver failure fails closed through normal
# contamination, and expiry still yields a partial receipt + cleanup +
# lease release, never a hang.
HOLD_OPEN_TIMEOUT_S = 120.0  # = POLL scale. Was 60 (= CLEANUP), set
# unmeasured; CI run 42045831617 proved 60 insufficient with the driver
# making steady progress (6 HID actions + 4 live shots in 60.6s on a
# cold runner vs ~40s locally). Still bounded and fail-closed on
# expiry (partial receipt + cleanup + lease release, never a hang).
# Bounded simctl-export retry inside live steps only (the specified
# HID-transition exception): initial attempt + 2 retries. The stock export
# path keeps its no-retry semantics.
LIVE_SHOT_ATTEMPTS = 3

# Cold-start fix (run 42051429064 iphone69-en): the hold phase burned 135s
# on 2 HID actions — both `argent run describe` calls hit 60s timeouts
# back-to-back (cold ax-service daemon/tool-server on first attach),
# expiring before the expanded hold. Locally warm describes take ~1-2s,
# which is why this never reproduced locally.
# (a) one pre-hold warm-up describe (outside the hold budget),
# (b) describe 30s + at most one retry per describe site (<=60s per
# describe op), (c) per-HID-op durations into stats["hid_ms"].
# Hold budget unchanged at 120s.
DESCRIBE_TIMEOUT_S = 30.0
DESCRIBE_MAX_RETRIES = 1
DESCRIBE_BUDGET_S = 60.0  # 2 x DESCRIBE_TIMEOUT_S per describe op

# Island regions pinned from LIVE headless pixels only (never scaled or
# guessed). 1206x2622 idle pill spans x[415,790] y[42,151] (lock-screen
# capture, zero bright content inside); the verdict box below adds margin.
# 1320x2868 live pill spans x[392,976] y[45,150] (live-la-compact.png with
# the activity RUNNING, app backgrounded via Home: dark_frac 0.81 with live
# content in the box below); VOID probes (no live activity) and the lock
# capture show dark_frac 0.00 in the same box, so the existing thresholds
# separate honestly with no tuning change. Any other geometry is
# unattested: no claim, never a pass.
ISLAND_REGIONS: dict[tuple[int, int], tuple[int, int, int, int]] = {
    (1206, 2622): (400, 805, 30, 165),
    (1320, 2868): (400, 990, 35, 160),
}
PILL_DARK_FRAC_MIN = 0.40
PILL_CONTENT_MIN = 200

# Expanded-card band below the island (x0, x1, y0, y1): a genuine long-press
# card renders here as a large dark mass, distinct from the compact pill
# (band y0 sits below every island box y1 above). No-card baselines on
# 1320x2868 (live compact Home: frac 0.06; VOID probes: 0.01) reject at the
# threshold below; the 1206x2622 band is the proportional mirror (no genuine
# 1206 expanded pixels exist) and is covered by synthetic tests only.
EXPANDED_REGIONS: dict[tuple[int, int], tuple[int, int, int, int]] = {
    (1206, 2622): (320, 886, 180, 594),
    (1320, 2868): (350, 970, 180, 650),
}
EXPANDED_DARK_FRAC_MIN = 0.30
EXPANDED_BRIGHT_MIN = 500
# Settle after the single-finger long-press for the card animation (~1.5s;
# the gesture-custom Up delayMs already holds the contact DOWN 1200ms).
EXPANDED_HOLD_SETTLE_S = 1.5
# Settle after Home before the first expanded Down (~1.0s; SpringBoard needs
# a beat after backgrounding before the island pill accepts a long-press —
# headless flake showed the first Down landing mid-transition with no card.
# Bounded sleeper inside the existing HOLD_OPEN deadline (no deadline
# increase); pre-settle + up-to-3 holds/settles stays ≤ ~15s added wall.
EXPANDED_PRE_HOLD_SETTLE_S = 1.0
# App-chrome probe band as a height fraction (avoids tab-bar/home-indicator
# rows): the capture app's Timer screen is uniform near-white here (top
# quantized bucket ~100% light on 1320x2868 track-running.png) while
# SpringBoard wallpaper spreads across buckets (top bucket ~16%). A tap on
# the pill that opens the app (instead of expanding) is rejected on these
# pixels, never by eye.
APP_CHROME_BAND_FRAC = (0.836, 0.906)
APP_CHROME_SHARE_MIN = 0.90
# Consent-sheet alert band as fractions of (width, height): a centered
# system alert body (light, >=550px wide, >=200px tall on 1320x2868) with a
# blue Allow-label cluster in its bottom half. Provisional geometry; every
# tap is gated on detection plus post-tap disappearance, never blind.
SHEET_BAND_FRAC = (0.136, 0.864, 0.348, 0.627)
SHEET_BODY_MIN_W = 550
SHEET_BODY_MIN_H = 200
SHEET_LABEL_MIN_MASS = 300
# Pixel-derived dismissal is capped at ONE tap: on failure record blocked
# with the evidence and move on (lock pixels stay genuine regardless — do
# not loop taps). The durable path is the XCUITest AX harness (interruption
# monitor tapping Allow on the SpringBoard sheet), a separate iOS-owner
# task; this probe only takes the cheap pixel win when it verifies.
SHEET_DISMISSAL_MAX_TAPS = 1


class HidBackend:
    """Injectable HID/AX surface for live-capture steps (stdlib contract).

    Production is ArgentHidBackend (argent-simulator-server one-shots,
    headless-proven); tests inject scripted fakes. Coordinates for tap()
    must come from find_allow_button over a real tree — never literals.
    """

    def press_button(self, button: str) -> None:
        raise NotImplementedError

    def tap(self, x: float, y: float) -> None:
        raise NotImplementedError

    def multitouch_hold(
        self, x1: float, y1: float, x2: float, y2: float
    ) -> None:
        raise NotImplementedError

    def long_press(self, x: float, y: float, duration_ms: int = 1200) -> None:
        raise NotImplementedError

    def ax_dump(self) -> dict:
        raise NotImplementedError


class ArgentHidBackend(HidBackend):
    """Production HID via argent one-shots (describe-backed consent grant).

    - ax_dump shells ``argent run describe --udid <udid> --json`` (bounded
      timeout DESCRIBE_TIMEOUT_S=30s; run 42051429064 proved the prior 60s
      stall on a cold daemon) and parses the text tree's AXButton lines
      into a describe-derived document ``{"source", "buttons":
      [{role, label, center, frame}]}``. Transport/parse failures raise
      FrameError (fail closed: the grant loop records a blocker and taps
      nothing — never blind coordinates).
    - tap shells ``argent run gesture-tap --udid <udid> --x <x> --y <y>``
      with normalized [0,1] coordinates from find_allow_button over a real
      describe document (proven on a headless scratch sim).
    - long_press shells ``argent run gesture-custom --udid <udid>
      --events-json '[{"type":"Down",...},{"type":"Up",...,"delayMs":1200}]'``
      (single-finger hold at the verified pill center; 1200ms after the
      800ms pilot flaked on the first Down; bounded timeout: the shared
      HID runner's DESCRIBE_TIMEOUT_S).
    - press_button / multitouch_hold keep the argent-simulator-server
      one-shots (universalhid_button / universalhid_multitouch), proven on
      headless sims (no Simulator.app). multitouch_hold stays for compat
      only; the expanded step uses long_press.
    """

    HID_BUTTONS = ("home", "power")

    def __init__(self, udid: str, server: str = "argent-simulator-server",
                 runner: Callable | None = None,
                 argent: str = "argent") -> None:
        if not isinstance(udid, str) or not udid:
            raise FrameError("HID backend requires an explicit simulator UDID")
        self._udid = udid
        self._server = server
        self._argent = argent
        self._runner = runner or (lambda argv: subprocess.run(
            argv, capture_output=True, text=True,
            timeout=DESCRIBE_TIMEOUT_S))

    def _spawn(self, argv: list[str], what: str) -> None:
        exe = shutil.which(self._server)
        if exe is None:
            raise FrameError(
                f"HID {what} unavailable: {self._server!r} not on PATH "
                "(no blind fallback)")
        try:
            proc = self._runner([exe] + argv)
        except (subprocess.TimeoutExpired, OSError) as exc:
            raise FrameError(
                f"HID {what} spawn failed ({type(exc).__name__})")
        if getattr(proc, "returncode", 1) != 0:
            raise FrameError(
                f"HID {what} failed "
                f"rc={getattr(proc, 'returncode', '?')} "
                f"stderr={getattr(proc, 'stderr', '')!r:.200}")

    def _run_argent(self, argv: list[str], what: str) -> str:
        """Run one `argent` CLI invocation; return stdout (fail closed)."""
        exe = shutil.which(self._argent)
        if exe is None:
            raise FrameError(
                f"HID {what} unavailable: {self._argent!r} not on PATH "
                "(no blind fallback)")
        try:
            proc = self._runner([exe] + argv)
        except (subprocess.TimeoutExpired, OSError) as exc:
            raise FrameError(
                f"HID {what} spawn failed ({type(exc).__name__})")
        if getattr(proc, "returncode", 1) != 0:
            raise FrameError(
                f"HID {what} failed "
                f"rc={getattr(proc, 'returncode', '?')} "
                f"stderr={getattr(proc, 'stderr', '')!r:.200}")
        return getattr(proc, "stdout", "") or ""

    def press_button(self, button: str) -> None:
        if not isinstance(button, str) \
                or button.lower() not in self.HID_BUTTONS:
            raise FrameError(
                f"HID button {button!r} refused (capture role: "
                f"{list(self.HID_BUTTONS)})")
        self._spawn(["universalhid_button", "--id", self._udid,
                     "--button", button], f"button {button}")

    def tap(self, x: float, y: float) -> None:
        for value in (x, y):
            if isinstance(value, bool) or not isinstance(value, (int, float)) \
                    or not 0.0 <= float(value) <= 1.0:
                raise FrameError(
                    f"HID tap coordinate {value!r} refused "
                    "(normalized [0,1] from AX only)")
        self._run_argent(["run", "gesture-tap", "--udid", self._udid,
                          "--x", str(float(x)), "--y", str(float(y))],
                         f"tap ({x}, {y})")

    def multitouch_hold(
        self, x1: float, y1: float, x2: float, y2: float
    ) -> None:
        """Two-finger hold (compat only; the expanded step no longer uses it).

        Both contacts go DOWN together, hold ~1s server-side, then UP
        together via universalhid_multitouch. Proven incapable for the
        expanded card; kept so older callers fail honestly, never silently.
        """
        for value in (x1, y1, x2, y2):
            if isinstance(value, bool) or not isinstance(value, (int, float)) \
                    or not 0.0 <= float(value) <= 1.0:
                raise FrameError(
                    f"HID hold coordinate {value!r} refused "
                    "(normalized [0,1] inside the verified pill box)")
        self._spawn(["universalhid_multitouch", "--id", self._udid,
                     "--x1", str(float(x1)), "--y1", str(float(y1)),
                     "--x2", str(float(x2)), "--y2", str(float(y2))],
                    f"multitouch-hold ({x1}, {y1}) ({x2}, {y2})")

    def long_press(self, x: float, y: float,
                   duration_ms: int = 1200) -> None:
        """Single-finger long-press for the expanded-card probe (never a tap).

        Shells ``argent run gesture-custom`` with the Down/Up sequence
        [{"type":"Down","x":cx,"y":cy},
         {"type":"Up","x":cx,"y":cy,"delayMs":1200}] at the verified pill
        center (1200ms after the 800ms pilot flaked). A tap on the pill would open the
        app's Timer screen instead of expanding, so the expanded step
        calls only this (a tap here is a product bug, not a fallback).
        """
        for value in (x, y):
            if isinstance(value, bool) or not isinstance(value, (int, float)) \
                    or not 0.0 <= float(value) <= 1.0:
                raise FrameError(
                    f"HID long-press coordinate {value!r} refused "
                    "(normalized [0,1] inside the verified pill box)")
        if isinstance(duration_ms, bool) or not isinstance(duration_ms, int) \
                or not 1 <= duration_ms <= 5000:
            raise FrameError(
                f"HID long-press duration {duration_ms!r} refused "
                "(integer ms in [1, 5000])")
        events = [{"type": "Down", "x": float(x), "y": float(y)},
                  {"type": "Up", "x": float(x), "y": float(y),
                   "delayMs": duration_ms}]
        self._run_argent(["run", "gesture-custom", "--udid", self._udid,
                          "--events-json", json.dumps(events)],
                         f"long-press ({x}, {y})")

    def ax_dump(self) -> dict:
        """Describe the screen via `argent run describe` (fail closed).

        Returns the describe-derived document ``{"source", "buttons"}``
        consumed by find_allow_button / the consent grant loop. Any
        transport or parse failure raises FrameError (the grant loop
        records a blocker and taps nothing — positions only ever come
        from describe output, never blind estimates).
        """
        out = self._run_argent(
            ["run", "describe", "--udid", self._udid, "--json"], "describe")
        try:
            doc = json.loads(out)
        except ValueError as exc:
            raise FrameError(
                f"HID describe output malformed ({exc}); failing closed "
                "without tap")
        return {"source": doc.get("source", "ax-service") if isinstance(
            doc, dict) else "ax-service",
            "buttons": parse_describe_document(doc)}


def _is_unit(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) \
        and 0.0 <= float(value) <= 1.0


# Describe-backed consent parsing. `argent run describe --json` returns
# {description, source} where description is a TEXT rendering — one line per
# element with role, quoted label, optional id=/value= attrs, and a
# normalized [0,1] frame (same space as gesture-tap). There is no
# structured-output flag, so AXButton lines are regex-parsed with a strict
# anchored grammar (observed shapes: `AXButton "Allow"  (x, y, w, h)`;
# header/ROOT/non-button lines never match and are ignored, never guessed).
_DESCRIBE_BUTTON_RE = re.compile(
    r"^AXButton\s+"
    r"(?:\"(?P<label>(?:[^\"\\]|\\.)*)\"\s*)?"
    r"(?P<attrs>(?:[A-Za-z_]+=\"[^\"]*\"\s*)*)"
    r"\(\s*(?P<x>[0-9]+(?:\.[0-9]+)?)\s*,"
    r"\s*(?P<y>[0-9]+(?:\.[0-9]+)?)\s*,"
    r"\s*(?P<w>[0-9]+(?:\.[0-9]+)?)\s*,"
    r"\s*(?P<h>[0-9]+(?:\.[0-9]+)?)\s*\)\s*$")
_DESCRIBE_VALUE_RE = re.compile(r"value=\"([^\"]*)\"")

# Exact consent labels (casefolded, smart quotes normalized): the compact
# sheet offers Allow / Don't Allow, the follow-up offers Always Allow.
# Don't Allow is sheet EVIDENCE only — never tapped.
_CONSENT_LABELS = frozenset({"allow", "always allow",
                             "don't allow", "dont allow"})
_CONSENT_TAPPABLE = ("allow", "always allow")

# Bounded describe-guided taps in the grant loop (mirrors the
# pixel-dismissal cap: verify after every tap, never loop taps).
CONSENT_MAX_TAPS = 2
# Late-sheet wait: under host load the consent sheet surfaces seconds
# after the first describe (parallel proof: both describes clean while
# the sheet appeared later at lock). Bounded settle-wait rounds before
# declaring absent — still fail-closed, still zero blind taps.
# Foreground uses 1 round (the sheet has never been observed there in any
# run); lock uses 10 (every observed sheet surfaced at lock time).
SHEET_WAIT_ROUNDS = 3
LOCK_SHEET_WAIT_ROUNDS = 10


def _normalize_consent_label(label: Any) -> str:
    if not isinstance(label, str):
        return ""
    return label.strip().casefold().replace("\u2019", "'").replace(
        "\u2018", "'")


def parse_describe_buttons(description: str) -> list[dict[str, Any]]:
    """Parse AXButton entries from a describe text tree (strict).

    Returns [{role, label, center [x, y], frame [x, y, w, h]}] with the
    tap center derived as frame.x + frame.width / 2 (the describe
    header's own formula). Only exact-grammar lines parse; header, ROOT,
    and non-button lines are ignored. Non-string input raises FrameError
    (fail closed: no tree, no tap).
    """
    if not isinstance(description, str):
        raise FrameError(
            "describe output is not text; failing closed without tap")
    buttons: list[dict[str, Any]] = []
    for line in description.splitlines():
        match = _DESCRIBE_BUTTON_RE.match(line.strip())
        if match is None:
            continue
        label = match.group("label")
        if label is None:
            value = _DESCRIBE_VALUE_RE.search(match.group("attrs") or "")
            label = value.group(1) if value else None
        if label is None:
            continue
        try:
            frame = [float(match.group(name))
                     for name in ("x", "y", "w", "h")]
        except ValueError:
            continue
        if any(not _is_unit(v) for v in frame):
            continue
        label = label.replace('\\"', '"').replace("\\\\", "\\").strip()
        if not label:
            continue
        # Tap centers round to 1e-6 (device-identical; keeps records
        # comparable by exact equality instead of float noise).
        buttons.append({
            "role": "AXButton",
            "label": label,
            "center": [round(frame[0] + frame[2] / 2, 6),
                       round(frame[1] + frame[3] / 2, 6)],
            "frame": frame,
        })
    return buttons


def parse_describe_document(doc: Any) -> list[dict[str, Any]]:
    """Extract consent buttons from a parsed describe --json document.

    Requires the `description` text tree; a missing/non-string tree raises
    FrameError (malformed output fails closed: unknown screen state never
    grants and never taps).
    """
    if not isinstance(doc, dict):
        raise FrameError(
            "describe output is not an object; failing closed without tap")
    description = doc.get("description")
    if not isinstance(description, str) or not description.strip():
        raise FrameError(
            "describe document carries no text tree; failing closed "
            "without tap")
    return parse_describe_buttons(description)


def collect_consent_buttons(tree: Any) -> list[tuple[str, str, float, float]]:
    """Collect (normalized label, raw label, x, y) consent buttons.

    Accepts legacy dict trees (label/title/name/text + x/y or a two-number
    center, nested under children-style lists) AND describe-derived button
    dicts (label + center pair or frame quad, center derived). Only exact
    consent labels match — anything else is absent, never guessed.
    """
    hits: list[tuple[str, str, float, float]] = []

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            label: str | None = None
            for key in ("label", "title", "name", "text"):
                value = node.get(key)
                if isinstance(value, str) and value.strip():
                    label = value
                    break
            coords: tuple[float, float] | None = None
            if _is_unit(node.get("x")) and _is_unit(node.get("y")):
                coords = (float(node["x"]), float(node["y"]))
            else:
                center = node.get("center")
                if isinstance(center, (list, tuple)) and len(center) == 2 \
                        and _is_unit(center[0]) and _is_unit(center[1]):
                    coords = (float(center[0]), float(center[1]))
                else:
                    frame = node.get("frame")
                    if isinstance(frame, (list, tuple)) and len(frame) == 4 \
                            and all(_is_unit(v) for v in frame):
                        coords = (round(float(frame[0])
                                        + float(frame[2]) / 2, 6),
                                  round(float(frame[1])
                                        + float(frame[3]) / 2, 6))
            if isinstance(label, str) and coords is not None:
                norm = _normalize_consent_label(label)
                if norm in _CONSENT_LABELS:
                    hits.append((norm, label.strip(), coords[0], coords[1]))
            for value in node.values():
                walk(value)
        elif isinstance(node, (list, tuple)):
            for value in node:
                walk(value)

    walk(tree)
    return hits


def find_consent_button(tree: Any, want: str) -> tuple[float, float] | None:
    """Locate one exact consent label in a tree (describe or legacy)."""
    norm_want = _normalize_consent_label(want)
    for norm, _raw, x, y in collect_consent_buttons(tree):
        if norm == norm_want:
            return (x, y)
    return None


def find_allow_button(tree: Any) -> tuple[float, float] | None:
    """Locate the consent Allow button in an AX tree (documented shapes).

    Returns normalized (x, y) or None when no exact Allow match exists.
    Accepts legacy dict trees (label|title|name|text + x/y or a two-number
    center, nested anywhere under children-style lists) and
    describe-derived button dicts (label + center pair or frame quad with
    the center derived). Only an exact casefold 'allow' matches — anything
    else is absent, never guessed.
    """
    return find_consent_button(tree, "allow")


def grant_consent(
    hid: HidBackend,
    hid_count: Callable[[], None] = lambda: None,
    clock: Callable[[], float] = time.monotonic,
    hid_ms: list | None = None,
    sleeper: Callable[[float], None] | None = None,
    interval_s: float = 2.0,
    wait_rounds: int = SHEET_WAIT_ROUNDS,
) -> dict[str, Any]:
    """Describe-guided consent grant loop (consent phase of live capture).

    describe → no consent buttons: settle-wait rounds, then outcome
    absent (proceed, zero taps).
    Allow present: tap its describe-derived center via `argent run
    gesture-tap`, re-describe (max CONSENT_MAX_TAPS tap rounds); an Always
    Allow follow-up is tapped the same way, then re-verified. Verified
    absence → outcome granted (coords + rounds recorded). A sheet that
    persists past the bound, a sheet with no tappable Allow, or any
    describe/tap FrameError → outcome failed-blocker (detail recorded,
    taps so far kept) and the caller proceeds: lock/compact capture is
    consent-independent and continues undisturbed. Taps never loop and
    positions only ever come from describe output — blind or
    pixel-estimated taps stay forbidden. Unexpected (non-FrameError)
    exceptions propagate fail-closed.

    Late-sheet note (parallel proof): the sheet can surface seconds
    after the first describe under host load, so an empty first tree
    waits bounded settle rounds (wait_rounds × interval_s) before
    resolving absent — still zero taps while waiting. Foreground waits
    once (no sheet ever observed there); lock waits LOCK_SHEET_WAIT_ROUNDS
    (every observed sheet surfaced at lock time).

    Cold-start note (run 42051429064): each describe site retries at most
    once on FrameError (DESCRIBE_MAX_RETRIES=1) with a per-attempt
    DESCRIBE_TIMEOUT_S=30s bound, so each describe op costs at most
    DESCRIBE_BUDGET_S=60s. Every describe/tap attempt appends
    {"op", "ms"} to hid_ms (when given) for timing diagnosis.
    """
    taps: list[dict[str, Any]] = []
    if sleeper is None:
        sleeper = time.sleep

    def _note(op: str, t0: float) -> None:
        if hid_ms is not None:
            try:
                ms = (clock() - t0) * 1000.0
            except Exception:
                ms = 0.0
            hid_ms.append({"op": op, "ms": float(ms)})

    def _describe() -> dict:
        last: FrameError | None = None
        for attempt in range(DESCRIBE_MAX_RETRIES + 1):
            t0 = clock()
            try:
                tree = hid.ax_dump()
            except FrameError as exc:
                _note("describe", t0)
                last = exc
                if attempt < DESCRIBE_MAX_RETRIES:
                    continue
                raise
            _note("describe", t0)
            hid_count()
            return tree
        if last is not None:
            raise last
        raise FrameError("describe retry exhausted without result")

    def _tap(x: float, y: float) -> None:
        t0 = clock()
        try:
            hid.tap(x, y)
        except FrameError:
            _note("tap", t0)
            raise
        _note("tap", t0)
        hid_count()

    try:
        tree = _describe()
        found = collect_consent_buttons(tree)

        def prefer(
            rows: list[tuple[str, str, float, float]]
        ) -> tuple[str, str, float, float] | None:
            for want in _CONSENT_TAPPABLE:
                for row in rows:
                    if row[0] == want:
                        return row
            return None

        current = prefer(found)
        waited = 0
        while current is None and not found and waited < wait_rounds:
            # No sheet yet — it may surface late under load. Bounded
            # settle-wait, then re-describe; still zero taps.
            sleeper(interval_s)
            waited += 1
            tree = _describe()
            found = collect_consent_buttons(tree)
            current = prefer(found)
        if current is None:
            if found:
                return {"outcome": "failed-blocker",
                        "blocker": "consent sheet without a tappable Allow "
                                   "button; nothing tapped",
                        "rounds": 0, "taps": taps}
            return {"outcome": "absent", "rounds": 0, "taps": taps}
        while current is not None and len(taps) < CONSENT_MAX_TAPS:
            _norm, raw, x, y = current
            _tap(x, y)
            taps.append({"label": raw, "x": x, "y": y})
            tree = _describe()
            current = prefer(collect_consent_buttons(tree))
        if current is None:
            # Sheet gone after an Allow tap: outcome granted means
            # "dismissed via an Allow tap" (absence-verified) — NOT
            # authorization-confirmed. Only later pixels can confirm:
            # run_live_capture sets confirmed=True when the compact pill
            # verifies live or the lock banner verifies present.
            return {"outcome": "granted", "rounds": len(taps), "taps": taps}
        labels = sorted({row[1] for row in collect_consent_buttons(tree)})
        return {"outcome": "failed-blocker",
                "blocker": f"consent sheet persists after {len(taps)} "
                           f"describe-guided taps ({', '.join(labels) or 'unlabeled'}); "
                           "lock/compact capture continues, taps never loop",
                "rounds": len(taps), "taps": taps}
    except FrameError as exc:
        return {"outcome": "failed-blocker", "blocker": str(exc)[:300],
                "rounds": len(taps), "taps": taps}


def decode_png_rgba_band(path: str, max_rows: int) -> tuple[int, int, bytes]:
    """Decode the top band of an 8-bit RGB/RGBA non-interlaced PNG (stdlib).

    Returns (width, height, raw RGBA bytes for rows [0, max_rows)).
    Rows decode sequentially (filter state is row-local + previous row),
    so stopping early is exact. Raises FrameError on any shape mismatch.
    """
    try:
        blob = Path(path).read_bytes()
    except OSError as exc:
        raise FrameError(f"cannot read PNG for pixel verify: {exc}")
    try:
        if blob[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError("bad signature")
        width, height, depth, ctype, comp, filt, inter = struct.unpack(
            ">IIBBBBB", blob[16:29])
        if (depth, comp, filt, inter) != (8, 0, 0, 0) \
                or ctype not in (2, 6):
            raise ValueError(f"unsupported PNG depth={depth} type={ctype}")
        pos = 8
        parts: list[bytes] = []
        while pos < len(blob):
            size = struct.unpack(">I", blob[pos:pos + 4])[0]
            typ = blob[pos + 4:pos + 8]
            if typ == b"IDAT":
                parts.append(blob[pos + 8:pos + 8 + size])
            elif typ == b"IEND":
                break
            pos += 12 + size
        raw = zlib.decompress(b"".join(parts))
        channels = 3 if ctype == 2 else 4
        stride = width * channels
        want = max(1, min(max_rows, height))
        out = bytearray(want * width * 4)
        prev = bytearray(stride)
        out_off = 0
        for row in range(want):
            kind = raw[row * (stride + 1)]
            line = bytearray(
                raw[row * (stride + 1) + 1:(row + 1) * (stride + 1)])
            if kind == 1:
                for i in range(channels, stride):
                    line[i] = (line[i] + line[i - channels]) & 255
            elif kind == 2:
                for i in range(stride):
                    line[i] = (line[i] + prev[i]) & 255
            elif kind == 3:
                for i in range(stride):
                    left = line[i - channels] if i >= channels else 0
                    line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
            elif kind == 4:
                for i in range(stride):
                    left = line[i - channels] if i >= channels else 0
                    up = prev[i]
                    up_left = prev[i - channels] if i >= channels else 0
                    p = left + up - up_left
                    pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                    pr = left if (pa <= pb and pa <= pc) \
                        else (up if pb <= pc else up_left)
                    line[i] = (line[i] + pr) & 255
            elif kind != 0:
                raise ValueError(f"unknown filter {kind}")
            if channels == 3:
                for col in range(width):
                    out[out_off:out_off + 3] = \
                        line[col * 3:col * 3 + 3]
                    out[out_off + 3] = 255
                    out_off += 4
            else:
                out[out_off:out_off + stride] = line
                out_off += stride
            prev = line
        return width, height, bytes(out)
    except (ValueError, struct.error, zlib.error, IndexError) as exc:
        raise FrameError(f"pixel decode failed for {path!r}: {exc}")


def island_verdict(png_path: str,
                   geometry: tuple[int, int]) -> dict[str, Any]:
    """Pixel verdict for a live Dynamic Island capture (no OCR).

    Counts near-black mass (the pill) and bright content (timer/icon) in
    the pinned region. live=True only when the mass AND live content both
    verify; an idle pill, a missing pill, or an unattested geometry all
    yield live=False with an honest reason — no pill means no island claim.
    """
    region = ISLAND_REGIONS.get((geometry[0], geometry[1]))
    if region is None:
        return {"live": False, "dark_frac": 0.0, "bright": 0,
                "reason": f"island region unattested for "
                          f"{(geometry[0], geometry[1])}; no island claim"}
    x0, x1, y0, y1 = region
    width, height, px = decode_png_rgba_band(png_path, y1 + 1)
    if (width, height) != (geometry[0], geometry[1]):
        raise FrameError(
            f"pixel source geometry {(width, height)} != expected "
            f"{(geometry[0], geometry[1])}")
    dark = bright = total = 0
    for y in range(y0, y1 + 1):
        base = y * width * 4
        for x in range(x0, x1 + 1):
            off = base + x * 4
            r, g, b = px[off], px[off + 1], px[off + 2]
            total += 1
            if r < 24 and g < 24 and b < 24:
                dark += 1
            if r > 150 or g > 150 or b > 150:
                bright += 1
    frac = dark / total if total else 0.0
    verdict: dict[str, Any] = {"dark_frac": frac, "bright": bright,
                               "live": False, "reason": ""}
    if frac < PILL_DARK_FRAC_MIN:
        verdict["reason"] = "no pill mass in island region; no island claim"
    elif bright < PILL_CONTENT_MIN:
        verdict["reason"] = \
            "idle pill without live content; no island claim"
    else:
        verdict["live"] = True
        verdict["reason"] = "live pill content verified"
    return verdict


def expanded_verdict(png_path: str,
                     geometry: tuple[int, int]) -> dict[str, Any]:
    """Pixel verdict for a long-press expanded card (no OCR).

    Counts near-black mass in the card band below the island. expanded=True
    only when the band carries a large dark mass AND bright card content;
    a compact Home screen (wallpaper/icons: frac <=0.11 measured) yields
    expanded=False — no card means no expanded claim.
    """
    region = EXPANDED_REGIONS.get((geometry[0], geometry[1]))
    if region is None:
        return {"expanded": False, "dark_frac": 0.0, "bright": 0,
                "reason": f"expanded band unattested for "
                          f"{(geometry[0], geometry[1])}; no expanded claim"}
    x0, x1, y0, y1 = region
    width, height, px = decode_png_rgba_band(png_path, y1 + 1)
    if (width, height) != (geometry[0], geometry[1]):
        raise FrameError(
            f"pixel source geometry {(width, height)} != expected "
            f"{(geometry[0], geometry[1])}")
    dark = bright = total = 0
    for y in range(y0, y1 + 1):
        base = y * width * 4
        for x in range(x0, x1 + 1):
            off = base + x * 4
            r, g, b = px[off], px[off + 1], px[off + 2]
            total += 1
            if r < 24 and g < 24 and b < 24:
                dark += 1
            if r > 150 or g > 150 or b > 150:
                bright += 1
    frac = dark / total if total else 0.0
    out: dict[str, Any] = {"dark_frac": frac, "bright": bright,
                           "expanded": False, "reason": ""}
    if frac < EXPANDED_DARK_FRAC_MIN:
        out["reason"] = "no card mass below the island; no expanded claim"
    elif bright < EXPANDED_BRIGHT_MIN:
        out["reason"] = "dark band without card content; no expanded claim"
    else:
        out["expanded"] = True
        out["reason"] = "expanded card mass verified"
    return out


LOCK_BANNER_MIN_RED = 0.002


def lock_banner_verdict(png_path: str,
                        geometry: tuple[int, int]) -> dict[str, Any]:
    """Pixel verdict for a Lock Screen banner (no OCR).

    Counts stop-button red mass in the banner band (relative rows
    0.662H-0.697H, full width — geometry-relative, so every canvas is
    attested). Calibrated: genuine lock banners measure 0.00745 on
    1320x2868 (two independent runs), blank lock screens 0.0.
    banner=True only above threshold; a blank lock records
    lock_attempt and the stub stays pending — a banner-less shot is
    never staged genuine.
    """
    width, height, px = decode_png_rgba_band(png_path, geometry[1])
    if (width, height) != (geometry[0], geometry[1]):
        raise FrameError(
            f"pixel source geometry {(width, height)} != expected "
            f"{(geometry[0], geometry[1])}")
    y0 = int(0.662 * height)
    y1 = int(0.697 * height)
    red = total = 0
    for y in range(y0, y1, 2):
        base = y * width * 4
        for x in range(0, width, 4):
            off = base + x * 4
            r, g, b = px[off], px[off + 1], px[off + 2]
            total += 1
            if r > 150 and g < 100 and b < 100:
                red += 1
    frac = red / total if total else 0.0
    out: dict[str, Any] = {"red_frac": frac, "banner": False, "reason": ""}
    if frac < LOCK_BANNER_MIN_RED:
        out["reason"] = ("no banner stop-button mass on the lock screen; "
                         "no banner claim")
    else:
        out["banner"] = True
        out["reason"] = "lock banner stop-button mass verified"
    return out


def app_foreground_verdict(png_path: str,
                           geometry: tuple[int, int]) -> dict[str, Any]:
    """Pixel guard against a tap that opened the app (never eyeball-only).

    Samples the app-chrome probe band (below content, above tab-bar rows):
    the capture app's Timer screen is uniform near-white there (top
    quantized bucket ~100% light) while SpringBoard (wallpaper + icons)
    spreads across buckets. app=True means the device shows app UI, so a
    staged expanded card is refused (a tap opened the app; no expansion).
    """
    width, height, px = decode_png_rgba_band(png_path, geometry[1])
    if (width, height) != (geometry[0], geometry[1]):
        raise FrameError(
            f"pixel source geometry {(width, height)} != expected "
            f"{(geometry[0], geometry[1])}")
    y0 = int(height * APP_CHROME_BAND_FRAC[0])
    y1 = int(height * APP_CHROME_BAND_FRAC[1])
    buckets: dict[tuple[int, int, int], int] = {}
    total = 0
    for y in range(y0, y1 + 1, 2):
        base = y * width * 4
        for x in range(0, width, 2):
            off = base + x * 4
            key = (px[off] // 32, px[off + 1] // 32, px[off + 2] // 32)
            buckets[key] = buckets.get(key, 0) + 1
            total += 1
    if not total:
        return {"app": False, "share": 0.0,
                "reason": "empty probe band; no app claim"}
    top_key = max(buckets, key=lambda k: buckets[k])
    share = buckets[top_key] / total
    light = top_key[0] >= 6 and top_key[1] >= 6 and top_key[2] >= 6
    if light and share >= APP_CHROME_SHARE_MIN:
        return {"app": True, "share": share,
                "reason": "uniform near-white app chrome; app foregrounded"}
    return {"app": False, "share": share,
            "reason": "wallpaper variance; SpringBoard held"}


def _is_blue_label(r: int, g: int, b: int) -> bool:
    return b > 150 and r < 100 and g < 170


def find_allow_centroid(png_path: str,
                        geometry: tuple[int, int]) -> dict[str, Any]:
    """Locate the Allow button centroid on a consent-sheet probe (pixels).

    Finds a centered light alert body in the sheet band, then the largest
    blue label cluster in its bottom half (system Allow blue). Returns
    {"found": True, "x": nx, "y": ny, ...} with normalized coordinates
    derived from THIS image, or {"found": False, ...} (absent/ambiguous:
    no tap ships — an ambiguous sheet is never tapped blind).
    """
    width, height, px = decode_png_rgba_band(png_path, geometry[1])
    if (width, height) != (geometry[0], geometry[1]):
        raise FrameError(
            f"pixel source geometry {(width, height)} != expected "
            f"{(geometry[0], geometry[1])}")
    fx0, fx1, fy0, fy1 = SHEET_BAND_FRAC
    bx0, bx1 = int(width * fx0), int(width * fx1)
    by0, by1 = int(height * fy0), int(height * fy1)
    scale_w = width / 1320.0
    min_w = max(200, int(SHEET_BODY_MIN_W * scale_w))
    min_h = max(80, int(SHEET_BODY_MIN_H * (height / 2868.0)))
    # Candidate body rows: each carries a light run >= min_w; keep the
    # widest run's span per row, then the tallest overlapping stack.
    spans: list[tuple[int, int, int]] = []
    for y in range(by0, by1 + 1, 2):
        base = y * width * 4
        best: tuple[int, int] | None = None
        run_s: int | None = None
        for x in range(bx0, bx1 + 1):
            off = base + x * 4
            light = px[off] > 150 or px[off + 1] > 150 or px[off + 2] > 150
            if light and run_s is None:
                run_s = x
            if not light and run_s is not None:
                if x - run_s >= min_w and (
                        best is None or x - run_s > best[1] - best[0]):
                    best = (run_s, x - 1)
                run_s = None
        if run_s is not None and bx1 - run_s >= min_w and (
                best is None or bx1 - run_s > best[1] - best[0]):
            best = (run_s, bx1)
        if best is not None:
            spans.append((y, best[0], best[1]))
    bodies: list[tuple[int, int, int, int]] = []
    if spans:
        cur = [spans[0][0], spans[0][0], spans[0][1], spans[0][2]]
        for y, s, e in spans[1:]:
            if y - cur[1] <= 4 and not (s > cur[3] or e < cur[2]):
                cur[1] = y
                cur[2], cur[3] = min(cur[2], s), max(cur[3], e)
            else:
                bodies.append((cur[0], cur[1], cur[2], cur[3]))
                cur = [y, y, s, e]
        bodies.append((cur[0], cur[1], cur[2], cur[3]))
    cand = [b for b in bodies if b[1] - b[0] >= min_h]
    if not cand:
        return {"found": False,
                "reason": "no alert body in sheet band; no consent tap"}
    ty0, ty1, tx0, tx1 = cand[0]
    mid = (ty0 + ty1) // 2
    # Largest blue cluster in the body bottom half (stride-2 BFS).
    seen = bytearray(width * height)
    best_mass = 0
    best_cx = best_cy = 0.0
    for y in range(mid, ty1 + 1, 2):
        base = y * width * 4
        for x in range(tx0, tx1 + 1, 2):
            idx = y * width + x
            if seen[idx]:
                continue
            off = base + x * 4
            if not _is_blue_label(px[off], px[off + 1], px[off + 2]):
                continue
            stack = [(x, y)]
            seen[idx] = 1
            mass = sx = sy = 0
            while stack:
                cx, cy = stack.pop()
                mass += 1
                sx += cx
                sy += cy
                for nx, ny in ((cx - 2, cy), (cx + 2, cy),
                              (cx, cy - 2), (cx, cy + 2)):
                    if nx < tx0 or nx > tx1 or ny < mid or ny > ty1:
                        continue
                    nidx = ny * width + nx
                    if seen[nidx]:
                        continue
                    seen[nidx] = 1
                    noff = ny * width * 4 + nx * 4
                    if _is_blue_label(px[noff], px[noff + 1],
                                      px[noff + 2]):
                        stack.append((nx, ny))
            if mass > best_mass:
                best_mass = mass
                best_cx = sx / mass / width
                best_cy = sy / mass / height
    if best_mass < SHEET_LABEL_MIN_MASS:
        return {"found": False, "body": [ty0, ty1, tx0, tx1],
                "reason": "alert body without Allow label mass; "
                          "ambiguous sheet never tapped"}
    return {"found": True, "x": best_cx, "y": best_cy,
            "mass": best_mass, "body": [ty0, ty1, tx0, tx1],
            "reason": "Allow label centroid from live probe pixels"}


def _live_shot(
    run: Callable,
    udid: str,
    dest: Path,
    geometry: tuple[int, int],
    *,
    mask: str | None,
    label: str,
    stats: sess.PhaseStats | None,
    interval_s: float,
    sleeper: Callable[[float], None],
    clock: Callable[[], float],
    deadline: float,
) -> tuple[str, str]:
    """One simctl export with bounded spawn retry (no stability gate).

    Live timers tick every second, so consecutive exports never hash
    identically (E5 proof: a live pill re-renders constantly); settling is
    handled by the caller's spacing plus content verdicts, never by hash
    equality. Spawn failures retry within LIVE_SHOT_ATTEMPTS, geometry
    mismatch fails immediately, and an expired hold window fails closed.
    Returns (sha256, captured_at_iso).
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, LIVE_SHOT_ATTEMPTS + 1):
        if clock() >= deadline:
            raise FrameError(
                f"hold-open window expired during {label}; failing closed "
                "without capture")
        try:
            proc = _counted(run, pf.screenshot_argv(udid, str(dest), mask),
                            stats)
        except FrameError:
            # _counted raises FrameError only for spawn failures (hang /
            # missing binary), never for rc: bounded retry, the specified
            # HID-transition exception.
            if attempt == LIVE_SHOT_ATTEMPTS:
                raise FrameError(
                    f"live {label} screenshot failed after {attempt} "
                    "attempt(s); no pixels staged")
            sleeper(interval_s)
            continue
        if getattr(proc, "returncode", 1) != 0:
            if attempt == LIVE_SHOT_ATTEMPTS:
                raise FrameError(
                    f"live {label} screenshot failed "
                    f"rc={getattr(proc, 'returncode', '?')}; "
                    "no pixels staged")
            sleeper(interval_s)
            continue
        try:
            dims = insp.png_dimensions(str(dest))
        except (insp.InspectionError, OSError) as exc:
            if attempt == LIVE_SHOT_ATTEMPTS:
                raise FrameError(
                    f"live {label} screenshot unreadable ({exc}); "
                    "no pixels staged")
            sleeper(interval_s)
            continue
        if dims != (geometry[0], geometry[1]):
            raise FrameError(
                f"live {label} geometry {dims} != expected "
                f"{(geometry[0], geometry[1])}; never stretch another "
                "device's capture")
        try:
            sha = insp.sha256_file(str(dest))
        except OSError as exc:
            if attempt == LIVE_SHOT_ATTEMPTS:
                raise FrameError(
                    f"live {label} screenshot unreadable ({exc}); "
                    "no pixels staged")
            sleeper(interval_s)
            continue
        from datetime import datetime, timezone

        return sha, datetime.now(timezone.utc).isoformat()
    raise FrameError(
        f"live {label} screenshot failed; no pixels staged")


def run_live_capture(
    *,
    hid: HidBackend | None,
    run: Callable,
    udid: str,
    geometry: tuple[int, int],
    run_dir: Path,
    anchor_id: str,
    live_started_at: str,
    timeout_s: float = HOLD_OPEN_TIMEOUT_S,
    clock: Callable[[], float] = time.monotonic,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    stats: sess.PhaseStats | None = None,
) -> dict[str, Any]:
    """Hold-open live-capture driver: consent, compact re-probe, lock shot.

    Runs while the realtime session stays RUNNING (lease held, no cleanup
    yet) and returns the live-capture record; the caller persists it. The
    driver stages genuine pixels + capture windows under run_dir/staging
    but registers nothing: genuine registration happens later via
    record-external-frame (no OCR, no fabricated
    reading). Raises FrameError fail-closed; the session record keeps the
    outcome for audit.
    """
    if hid is None:
        raise FrameError("live capture requires an HID backend "
                         "(no blind fallback)")
    deadline = clock() + timeout_s

    def hold_left(step: str) -> None:
        if clock() >= deadline:
            raise FrameError(
                f"hold-open window expired before {step}; failing closed "
                "without capture (cleanup still runs)")

    def hid_count() -> None:
        if stats is not None:
            stats.count("hid_action")

    # Per-HID-op durations (run 42051429064 diagnosis aid): every HID call
    # below appends {"op", "ms"} on the runner clock. Stored on the shared
    # stats object when present (dynamic attr; session.py untouched) so the
    # session record/summary carry stats["hid_ms"].
    hid_ms: list[dict[str, Any]] = []
    if stats is not None:
        _existing = getattr(stats, "hid_ms", None)
        if isinstance(_existing, list):
            hid_ms = _existing
        else:
            try:
                stats.hid_ms = hid_ms  # type: ignore[attr-defined]
            except AttributeError:
                pass

    def _hid(op: str, thunk: Callable[[], Any]) -> Any:
        t0 = clock()
        try:
            out = thunk()
        except FrameError:
            try:
                ms = (clock() - t0) * 1000.0
            except Exception:
                ms = 0.0
            hid_ms.append({"op": op, "ms": float(ms)})
            raise
        try:
            ms = (clock() - t0) * 1000.0
        except Exception:
            ms = 0.0
        hid_ms.append({"op": op, "ms": float(ms)})
        hid_count()
        return out

    staging = run_dir / "staging"
    staging.mkdir(parents=True, exist_ok=True)

    # Consent grant BEFORE any capture, wired into the pipeline: the
    # describe-backed grant loop taps ONLY describe-derived Allow / Always
    # Allow centers (verified absent after, bounded to CONSENT_MAX_TAPS
    # taps), records granted coords + rounds, and degrades to a recorded
    # failed-blocker — lock/compact capture continues undisturbed. Cloud
    # runners start clean every run, so the one-time manual grant does not
    # transfer; this phase re-grants honestly on every run. Two-phase
    # timing: this foreground describe covers already-surfaced sheets + the
    # absent fast-path, but the system sheet surfaces at LOCK time — after
    # this describe already returned absent. The lock-phase re-grant below
    # (after the power press, before any lock screenshot) reuses the same
    # grant_consent helper. Bound: at most CONSENT_MAX_TAPS (2)
    # describe-guided taps per phase, total taps ≤4 (foreground + lock);
    # taps never loop and positions only ever come from describe output.
    hold_left("consent grant")
    consent_fg = grant_consent(hid, hid_count, clock, hid_ms,
                               sleeper=sleeper, interval_s=interval_s,
                               wait_rounds=1)

    # Compact re-probe after grant: Home backgrounds the app so the island
    # pill renders. Shots repeat (verdict-gated, bounded) until the pill
    # verifies live: a transition frame or an undismissed prompt fails the
    # verdict, never the session — no pill means no island claim and the
    # stub stays honestly pending.
    hold_left("compact re-probe")
    _hid("press_button", lambda: hid.press_button("Home"))
    compact_dest = staging / "live-la-compact.png"
    verdict: dict[str, Any] = {"live": False,
                               "reason": "no compact shot staged"}
    csha = ciso = ""
    for _ in range(LIVE_SHOT_ATTEMPTS):
        hold_left("compact re-probe")
        sleeper(interval_s)
        csha, ciso = _live_shot(
            run, udid, compact_dest, geometry,
            mask=pf.resolve_screenshot_mask("la-compact", None),
            label="compact re-probe", stats=stats, interval_s=interval_s,
            sleeper=sleeper, clock=clock, deadline=deadline)
        if stats is not None:
            stats.count("live_capture_shot")
        verdict = island_verdict(str(compact_dest), geometry)
        if verdict["live"]:
            break

    # Expanded hold-open probe (verdict-gated, up to LIVE_SHOT_ATTEMPTS
    # single-finger attempts): the device is still unlocked at Home with the
    # activity RUNNING. The compact verdict above already screenshots Home;
    # when it confirms the live pill, fire single-finger long-presses at the
    # pill center via gesture-custom (Down/Up 1200ms; never a tap — a tap
    # would open the app's Timer screen instead of expanding), settle,
    # screenshot, and stage staging/live-la-expanded.png on the FIRST pass
    # where the post shot verifies as a genuine card: card-band mass below
    # the island AND the island still present (a tap-opened app hides the
    # pill) AND no uniform app chrome. Each attempt reuses the
    # LIVE_SHOT_ATTEMPTS pattern (attempt -> screenshot -> expanded_verdict
    # + app-chrome guard); the last attempt PNG stays at
    # staging/live-la-expanded.attempt.png as evidence when nothing passes.
    # A short settle-wait after Home precedes the first Down (SpringBoard
    # transition flake); pre-settle + up-to-3 holds/settles adds ≤ ~15s wall
    # inside the existing HOLD_OPEN deadline (no deadline increase).
    # Without a confirmed pre-hold pill no hold fires (a blind long-press
    # could jiggle Home).
    hold_left("expanded hold-open")
    region = ISLAND_REGIONS.get((geometry[0], geometry[1]))
    expanded: dict[str, Any] | None = None
    expanded_attempt: dict[str, Any] | None = None
    if region is None:
        expanded_attempt = {
            "outcome": "no-card",
            "reason": f"island region unattested for "
                      f"{(geometry[0], geometry[1])}; no blind hold fired",
            "hold": None,
            "pre_live": bool(verdict.get("live")),
        }
    elif not verdict.get("live"):
        expanded_attempt = {
            "outcome": "no-card",
            "reason": f"pre-hold pill not live "
                      f"({verdict.get('reason', '')}); no hold fired, "
                      "Home left undisturbed",
            "hold": None,
            "pre_live": False,
        }
    else:
        x0, x1, y0, y1 = region
        cx = (x0 + x1) / 2 / geometry[0]
        cy = (y0 + y1) / 2 / geometry[1]
        hold_pts = {"x": cx, "y": cy, "duration_ms": 1200}
        hold_left("expanded hold-open")
        sleeper(EXPANDED_PRE_HOLD_SETTLE_S)
        attempt_dest = staging / "live-la-expanded.attempt.png"
        for attempt_idx in range(1, LIVE_SHOT_ATTEMPTS + 1):
            hold_left("expanded hold-open")
            _hid("long_press", lambda: hid.long_press(
                hold_pts["x"], hold_pts["y"], hold_pts["duration_ms"]))
            sleeper(EXPANDED_HOLD_SETTLE_S)
            hold_left("expanded hold-open")
            _, eiso = _live_shot(
                run, udid, attempt_dest, geometry,
                mask=pf.resolve_screenshot_mask("la-expanded", None),
                label="expanded hold-open", stats=stats,
                interval_s=interval_s, sleeper=sleeper, clock=clock,
                deadline=deadline)
            if stats is not None:
                stats.count("live_capture_shot")
            everdict = expanded_verdict(str(attempt_dest), geometry)
            post_island = island_verdict(str(attempt_dest), geometry)
            post_app = app_foreground_verdict(str(attempt_dest), geometry)
            island_held = post_island.get("dark_frac", 0.0) \
                >= PILL_DARK_FRAC_MIN
            if (bool(everdict.get("expanded")) and island_held
                    and not post_app.get("app")):
                staged = staging / "live-la-expanded.png"
                shutil.copyfile(attempt_dest, staged)
                try:
                    staged_sha = insp.sha256_file(str(staged))
                except OSError as exc:
                    raise FrameError(f"staged expanded unreadable: {exc}")
                expanded = {
                    "screenshot": "staging/live-la-expanded.png",
                    "screenshot_sha256": staged_sha,
                    "probe": "staging/live-la-expanded.attempt.png",
                    "captured_at_iso": eiso,
                    "verdict": everdict,
                    "post_island_dark_frac": post_island.get("dark_frac"),
                    "post_app_share": post_app.get("share"),
                    "hold": hold_pts,
                    "attempts": attempt_idx,
                }
                break
            if attempt_idx == LIVE_SHOT_ATTEMPTS:
                why = []
                if not everdict.get("expanded"):
                    why.append(everdict.get("reason", "no card mass"))
                if not island_held:
                    why.append(
                        "island pill hidden post-hold (a tap opens the app; "
                        "expansion refused)")
                if post_app.get("app"):
                    why.append(
                        "uniform app chrome post-hold (Timer screen, not a "
                        "card); expansion refused")
                expanded_attempt = {
                    "outcome": "no-card",
                    "reason": "; ".join(why) or "no expanded claim",
                    "probe": "staging/live-la-expanded.attempt.png",
                    "captured_at_iso": eiso,
                    "verdict": everdict,
                    "post_island_dark_frac": post_island.get("dark_frac"),
                    "post_app_share": post_app.get("share"),
                    "hold": hold_pts,
                    "pre_live": True,
                    "attempts": attempt_idx,
                }
            else:
                sleeper(interval_s)

    # Consent-sheet dismissal probe (pixel-derived, before lock): shoot the
    # lock screen; if an Allow sheet is pixel-detected, tap ONLY its
    # image-derived label centroid and re-shoot to verify it is gone (ONE
    # attempt max). A persistent sheet records blocked honestly with the
    # evidence and the run moves on — lock pixels stay genuine either way;
    # sheet presence is just noted, taps never loop. No sheet (or ambiguous
    # pixels) ships zero taps: location must come from the live image and
    # verify after, never blind coordinates. Durable dismissal is the
    # XCUITest AX harness (separate iOS-owner task).
    hold_left("consent dismissal probe")
    sleeper(interval_s)
    probe_dest = staging / "live-lock-probe.png"
    _, _ = _live_shot(
        run, udid, probe_dest, geometry,
        mask=pf.resolve_screenshot_mask("la-lock", None),
        label="consent dismissal probe", stats=stats, interval_s=interval_s,
        sleeper=sleeper, clock=clock, deadline=deadline)
    if stats is not None:
        stats.count("live_capture_shot")
    dismissal: dict[str, Any] = {"outcome": "absent", "attempts": 0,
                                 "tap": None,
                                 "probe": "staging/live-lock-probe.png"}
    for _ in range(SHEET_DISMISSAL_MAX_TAPS):
        hold_left("consent dismissal")
        found = find_allow_centroid(str(probe_dest), geometry)
        if not found.get("found"):
            dismissal["outcome"] = "dismissed" \
                if dismissal["attempts"] else "absent"
            dismissal["reason"] = found.get("reason", "")
            break
        _hid("tap", lambda: hid.tap(float(found["x"]),
                                     float(found["y"])))
        dismissal["attempts"] += 1
        dismissal["tap"] = {"x": found["x"], "y": found["y"],
                            "mass": found.get("mass")}
        sleeper(interval_s)
        hold_left("consent dismissal")
        _, _ = _live_shot(
            run, udid, probe_dest, geometry,
            mask=pf.resolve_screenshot_mask("la-lock", None),
            label="consent dismissal re-shot", stats=stats,
            interval_s=interval_s, sleeper=sleeper, clock=clock,
            deadline=deadline)
        if stats is not None:
            stats.count("live_capture_shot")
    else:
        hold_left("consent dismissal")
        found = find_allow_centroid(str(probe_dest), geometry)
        if found.get("found"):
            dismissal["outcome"] = "blocked"
            dismissal["reason"] = (
                "consent dismissal blocked: sheet persists after 1 "
                "pixel-derived tap with evidence; lock stays genuine, "
                "presence noted (durable path: XCUITest AX harness)")
        else:
            dismissal["outcome"] = "dismissed"
            dismissal["reason"] = found.get("reason", "")

    # powerx2 lock + simctl screenshot with retry (spike pattern:
    # delivery-redundant presses, ends locked either way). Two spaced
    # exports, the later (more settled) one staged; lock content has no
    # automated verdict (OCR is refused), so the human binds it later.
    hold_left("lock capture")
    _hid("press_button", lambda: hid.press_button("Power"))
    sleeper(interval_s)
    _hid("press_button", lambda: hid.press_button("Power"))
    # Lock-phase consent re-grant (clean-sim timing fix): the sheet
    # surfaces at LOCK time, after the foreground describe already returned
    # absent — so the driver attempts granting again once locked, before
    # any lock screenshot. Same grant_consent helper, same per-phase
    # max-2-taps budget (total taps ≤4, foreground + lock); if granted at
    # lock time, proceed to the lock screenshot (sheet gone → clean
    # banner). The foreground attempt above is NOT moved (it covers
    # already-surfaced sheets + the absent fast-path). The pixel-dismissal
    # probe above stays as-is (its correct refusal stands). Only runs when
    # the foreground phase was absent (0 taps): a foreground grant skips
    # (sheet already gone, no extra HID), and a foreground failed-blocker
    # skips in this revision (preserves the existing 2-tap bound for
    # persisting sheets and keeps the loop tests green; a not-granted
    # retry with total ≤4 is future work). The merged consent record keeps
    # the foreground outcome/rounds/taps shape and adds phase
    # ("foreground" when granted up front, "lock" when granted once
    # locked, None when no grant) plus the per-phase foreground/lock
    # details for audit.
    hold_left("lock consent grant")
    sleeper(interval_s)
    if consent_fg.get("outcome") == "granted":
        consent = dict(consent_fg)
        consent["phase"] = "foreground"
        consent["foreground"] = consent_fg
        consent["lock"] = None
    elif consent_fg.get("outcome") != "absent":
        consent = dict(consent_fg)
        consent["phase"] = None
        consent["foreground"] = consent_fg
        consent["lock"] = None
    else:
        consent_lock = grant_consent(hid, hid_count, clock, hid_ms,
                                       sleeper=sleeper, interval_s=interval_s,
                                       wait_rounds=LOCK_SHEET_WAIT_ROUNDS)
        fg_taps = consent_fg.get("taps", [])
        lock_taps = consent_lock.get("taps", [])
        total_taps = list(fg_taps) + list(lock_taps)
        if consent_lock.get("outcome") == "granted":
            consent = {
                "outcome": "granted",
                "rounds": len(total_taps),
                "taps": total_taps,
                "phase": "lock",
                "foreground": consent_fg,
                "lock": consent_lock,
            }
        elif consent_lock.get("outcome") == "absent":
            consent = {
                "outcome": "absent",
                "rounds": 0,
                "taps": [],
                "phase": None,
                "foreground": consent_fg,
                "lock": consent_lock,
            }
        else:
            consent = {
                "outcome": "failed-blocker",
                "blocker": consent_lock.get("blocker", ""),
                "rounds": len(total_taps),
                "taps": total_taps,
                "phase": None,
                "foreground": consent_fg,
                "lock": consent_lock,
            }
    # Pixel confirmation lands later (see banner gate below); until
    # then a grant means "sheet dismissed via Allow tap", unconfirmed.
    consent["confirmed"] = False
    lock_dest = staging / "live-la-lock.png"
    lock_attempt_dest = staging / "live-la-lock.attempt.png"
    lsha = liso = ""
    lock_attempt: dict[str, Any] | None = None
    if list(consent.get("taps", [])):
        # A grant just fired: SpringBoard needs a beat to present the
        # banner/pill before any lock pixels count. One bounded settle.
        hold_left("post-grant settle")
        sleeper(interval_s)
    for _ in range(2):
        hold_left("lock capture")
        sleeper(interval_s)
        lsha, liso = _live_shot(
            run, udid, lock_attempt_dest, geometry,
            mask=pf.resolve_screenshot_mask("la-lock", None),
            label="lock capture", stats=stats, interval_s=interval_s,
            sleeper=sleeper, clock=clock, deadline=deadline)
        if stats is not None:
            stats.count("live_capture_shot")
    # Banner gate: a lock shot without the activity banner (dead or
    # never-presented activity) is attempt evidence, never staged
    # genuine — the stub stays pending for a live rerun.
    banner = lock_banner_verdict(str(lock_attempt_dest), geometry)
    if banner.get("banner"):
        shutil.copyfile(lock_attempt_dest, lock_dest)
        try:
            lsha = insp.sha256_file(str(lock_dest))
        except OSError as exc:
            raise FrameError(f"staged lock unreadable: {exc}")
    else:
        lock_attempt = {
            "outcome": "no-banner",
            "reason": banner.get("reason", "no banner claim"),
            "probe": "staging/live-la-lock.attempt.png",
            "captured_at_iso": liso,
            "red_frac": banner.get("red_frac"),
        }
        lsha, liso = "", ""
    # Pixel confirmation: a grant counts as confirmed only when activity
    # UI actually rendered — live compact pill or verified lock banner.
    if banner.get("banner") or verdict.get("live"):
        consent["confirmed"] = True
    if expanded is not None:
        live_record: dict[str, Any] = {
            "schema_version": 1,
            "anchor": anchor_id,
            "consent": consent,
            "compact": {
                "screenshot": "staging/live-la-compact.png",
                "screenshot_sha256": csha,
                "captured_at_iso": ciso,
                "verdict": verdict,
            },
            "expanded": expanded,
            "consent_dismissal": dismissal,
            "lock_attempt": lock_attempt,
            "lock": {
                "screenshot": "staging/live-la-lock.png",
                "screenshot_sha256": lsha,
                "captured_at_iso": liso,
                "capture_window": {"started_at": live_started_at,
                                   "captured_at_iso": liso},
            },
        }
    else:
        live_record = {
            "schema_version": 1,
            "anchor": anchor_id,
            "consent": consent,
            "compact": {
                "screenshot": "staging/live-la-compact.png",
                "screenshot_sha256": csha,
                "captured_at_iso": ciso,
                "verdict": verdict,
            },
            "expanded_attempt": expanded_attempt or {"outcome": "no-card",
                                                     "reason": "unset"},
            "consent_dismissal": dismissal,
            "lock_attempt": lock_attempt,
            "lock": {
                "screenshot": "staging/live-la-lock.png",
                "screenshot_sha256": lsha,
                "captured_at_iso": liso,
                "capture_window": {"started_at": live_started_at,
                                   "captured_at_iso": liso},
            },
        }
    return live_record


def run_session(
    run: Callable,
    udid: str,
    base_request: dict,
    domain: str,
    run_dir: Path,
    *,
    device_key: str,
    bid: str = req.SCREENSHOT_BID,
    pinned_totals: dict | None = None,
    geometry: tuple[int, int] | None = None,
    island_available: bool | None = None,
    session_nonce: str | None = None,
    pending_reason: str = SESSION_PENDING_REASON,
    timeout_s: float = POLL_TIMEOUT_S,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    on_poll: Callable[[], None] | None = None,
    stats: sess.PhaseStats | None = None,
    hold_open: bool = False,
    hid: HidBackend | None = None,
    hold_timeout_s: float = HOLD_OPEN_TIMEOUT_S,
) -> dict[str, Any]:
    """Execute one frozen-v2 session domain (pinned XOR realtime).

    Owns the device lock for the whole session (lease covers frame
    commands, not individual frames), resolves container/provenance ONCE,
    snapshots/applies chrome ONCE, launches ONCE, then advances the domain
    story via ordered queue commands with per-command ack binding and
    per-export live validation. Exactly one identity-checked cleanup ends
    the session; its combined receipt gates every dependent frame.

    Writes envelope files, frame PNGs/records, the session record, the
    combined receipt, timing stats, and (iPad realtime) the island probe.
    Raises FrameError with a contamination note when the session cannot
    complete; earlier exports are preserved and the receipt stays partial.
    """
    stats = stats if stats is not None else sess.PhaseStats(clock=clock)
    # Per-HID-op durations live here (dynamic attr; session.py untouched).
    # run_live_capture reuses the same list via stats.hid_ms when present.
    hid_ms: list[dict[str, Any]] = []
    _existing_hid = getattr(stats, "hid_ms", None)
    if isinstance(_existing_hid, list):
        hid_ms = _existing_hid
    else:
        try:
            stats.hid_ms = hid_ms  # type: ignore[attr-defined]
        except AttributeError:
            pass
    if domain not in sess.SESSION_DOMAINS:
        raise FrameError(f"unknown session_domain {domain!r}")
    if hold_open and domain != "realtime":
        raise FrameError("hold-open live capture is realtime-only "
                         "(pinned sessions end immediately after export)")
    if hold_open and hid is None:
        raise FrameError("hold-open live capture requires an HID backend "
                         "(buttons/AX taps; no blind fallback)")
    geo, island = _checked_session_run_args(device_key, geometry,
                                            island_available)
    frames = sess.frames_for_domain(domain, island_available=island)
    run_id = base_request.get("run_id", run_dir.name)
    if base_request.get("run_id") is not None and run_id != run_dir.name:
        raise FrameError(
            f"base run_id {base_request.get('run_id')!r} != run directory "
            f"{run_dir.name!r}")
    # Fail-closed payload validation for every frame up front.
    payloads: dict[str, dict] = {}
    for frame in frames:
        try:
            derived = req.build_frame_request(
                {**base_request, "run_id": run_id}, frame)
        except req.RequestError as exc:
            raise FrameError(f"invalid frame request: {exc}")
        errs = req.validate_request_dict(derived)
        if errs:
            raise FrameError(f"invalid frame request: {errs[0]}")
        payloads[frame] = derived
    nonce = session_nonce or sess.new_nonce()
    if sess.validate_nonce(nonce):
        raise FrameError(f"invalid session_nonce {nonce!r}")
    if pinned_totals is None:
        raise FrameError("pinned_totals is required: ready refused without "
                         "an independently pinned dictionary")

    try:
        lock_path = guard.acquire_lock(udid, run_id)
    except guard.GuardError as exc:
        raise FrameError(f"cannot hold the device lease: {exc}")
    lease_released = False
    failures: list[str] = []
    hold_record: dict[str, Any] = {"enabled": bool(hold_open)}
    envelopes: list[dict] = []
    acks: list[dict] = []
    frame_records: list[dict] = []
    anchor_ids: set[str] = set()
    container = ""
    snap: dict[str, str] = {}
    provenance: dict[str, Any] = {}
    model_proof: dict[str, Any] = {}
    try:
        stats.start("resolve")
        container = get_container_data(
            lambda argv: _counted(run, argv, stats), udid, bid)
        provenance = app_provenance(
            lambda argv: _counted(run, argv, stats), udid, bid)
        # Owned-device preflight (all keys, both domains): the ACTUAL
        # simctl-reported model must match the requested catalog BEFORE
        # any capture. Resolved once per session here, alongside
        # container/provenance — never per frame or command. The raw
        # run goes in with stats so the inner _read_device_entry
        # records exactly one trail event/counter per spawn (a counted
        # lambda here would double-record: outer plus inner _counted).
        try:
            model_proof = verify_owned_device(
                run, udid,
                device_key=device_key, geometry=geo, stats=stats)
        except FrameError as exc:
            raise FrameError(f"owned-device preflight: {exc}")
        stats.stop("resolve")
        docs = Path(container) / "Documents"
        try:
            docs.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise FrameError(f"cannot use container {docs}: {exc}")

        stats.start("chrome")
        snap = snapshot_chrome(
            lambda argv: _counted(run, argv, stats), udid)
        ensure_clean_chrome(snap)
        apply_chrome(lambda argv: _counted(run, argv, stats), udid)
        stats.stop("chrome")

        # Stage the seq-0 envelope as the root request (existing token).
        stats.start("stage")
        first = frames[0]
        env0 = sess.build_envelope(payloads[first], run_id=run_id,
                                   session_nonce=nonce,
                                   session_domain=domain, seq=0)
        raw0 = (json.dumps(env0, sort_keys=True, separators=(",", ":"),
                           ensure_ascii=False).encode("utf-8") + b"\n")
        try:
            (docs / pf.REQUEST_FILENAME).write_bytes(raw0)
        except OSError as exc:
            raise FrameError(f"cannot stage root request in {docs}: {exc}")
        clear_owned_state(docs)
        try:
            (docs / pf.CLEANUP_FILENAME).unlink(missing_ok=True)
        except OSError as exc:
            raise FrameError(f"cannot clear owned cleanup file: {exc}")
        (run_dir / "requests").mkdir(parents=True, exist_ok=True)
        (run_dir / "sessions").mkdir(parents=True, exist_ok=True)
        (run_dir / "requests" /
         f"session-{nonce}-0-{first}.envelope.json").write_bytes(raw0)
        stats.stop("stage")
        stats.count("envelope_stage")

        stats.start("launch")
        launch_capture(lambda argv: _counted(run, argv, stats), udid, bid)
        stats.stop("launch")
        stats.count("launch")

        prev: dict | None = None
        consumed: set[int] = set()
        queue_root = docs / sess.SESSIONS_DIRNAME
        for seq, frame in enumerate(frames):
            payload = payloads[frame]
            env = sess.build_envelope(payload, run_id=run_id,
                                      session_nonce=nonce,
                                      session_domain=domain, seq=seq)
            errs = sess.validate_transition(prev, env, consumed)
            if errs:
                raise FrameError(f"session transition refused: {errs[0]}")
            if seq > 0:
                stats.start("publish")
                try:
                    sess.publish_command(queue_root, env)
                except sess.SessionError as exc:
                    raise FrameError(f"cannot publish command: {exc}")
                (run_dir / "requests" /
                 f"session-{nonce}-{seq}-{frame}.envelope.json").write_bytes(
                    json.dumps(env, sort_keys=True, separators=(",", ":"),
                               ensure_ascii=False).encode("utf-8") + b"\n")
                stats.stop("publish")
                stats.count("command_publish")
            envelopes.append(env)
            stats.start("poll")
            try:
                ack, attempts = poll_session_ack(
                    docs, want_nonce=nonce, want_domain=domain, want_seq=seq,
                    want_sha=env["request_sha256"], want_frame=frame,
                    timeout_s=timeout_s, interval_s=interval_s,
                    sleeper=sleeper, clock=clock, on_poll=on_poll)
            except FrameError as exc:
                raise FrameError(f"{exc}")
            finally:
                try:
                    stats.stop("poll")
                except sess.SessionError:
                    pass
            verdict, v_errs = sc.validate_session_ack(ack, env, pinned_totals)
            if verdict != sc.OK:
                raise FrameError(
                    f"state verdict {verdict}: "
                    f"{'; '.join(v_errs) or 'not ready'}")
            for row in ack.get("transcript", []):
                if isinstance(row, dict) and isinstance(row.get("seq"), int):
                    consumed.add(row["seq"])
            consumed.add(seq)
            app_durs = ack.get("app_durations_ms")
            if isinstance(app_durs, dict):
                for k, v in app_durs.items():
                    if isinstance(v, (int, float)):
                        stats.note_app_duration(f"{frame}.{k}", v)
            acks.append(ack)
            # Per-frame ack archive: the device state file is last-wins,
            # so persist each validated ack for later session-bound
            # genuine registration (record-external-frame --state per
            # frame; the surviving state alone only binds the last seq).
            try:
                states_dir = run_dir / "states"
                states_dir.mkdir(parents=True, exist_ok=True)
                (states_dir /
                 f"session-{nonce}-{seq}-{frame}.ack.json").write_text(
                    json.dumps(ack, sort_keys=True, separators=(",", ":"),
                               ensure_ascii=False) + "\n",
                    encoding="utf-8")
            except OSError as exc:
                raise FrameError(f"cannot archive session ack: {exc}")
            la = ack.get("live_activity")
            if isinstance(la, dict) and la.get("activity_id"):
                anchor_ids.add(la["activity_id"])
            stats.count("poll_attempt", attempts)

            # Per-export live validation + presentation check, then export.
            stats.start("export")
            _verify_session_presentation(
                lambda argv: _counted(run, argv, stats), udid)
            if domain == "pinned":
                dest = frame_png_path(run_dir, frame)
            else:
                # Realtime placeholders stage outside frames/: registering
                # the pending handoff copies them into place (copyfile
                # refuses same-file src/dst).
                dest = run_dir / "staging" / f"{frame}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            try:
                resolved_mask = pf.resolve_screenshot_mask(frame, None)
            except ValueError as exc:
                raise FrameError(str(exc))
            argv = pf.screenshot_argv(udid, str(dest), resolved_mask)
            proc = _counted(run, argv, stats)
            if getattr(proc, "returncode", 1) != 0:
                raise FrameError(
                    f"io screenshot failed for {frame!r} "
                    f"rc={getattr(proc, 'returncode', '?')}")
            try:
                dims = insp.png_dimensions(str(dest))
            except insp.InspectionError as exc:
                raise FrameError(str(exc))
            if dims != (geo[0], geo[1]):
                raise FrameError(
                    f"screenshot geometry {dims} != expected {geo}; "
                    "never stretch another device's capture")
            stats.stop("export")
            stats.count("screenshot")

            if domain == "pinned":
                record = {
                    "schema_version": 1,
                    "frame": frame,
                    "mode": payload["mode"],
                    "device_udid": udid,
                    "device_key": device_key,
                    "run_id": run_id,
                    "deck_version": payload.get("deck_version"),
                    "treatment": payload.get("treatment"),
                    "request_sha256": env["request_sha256"],
                    "request_semantic_sha256":
                        sess.semantic_sha256_of_payload(payload),
                    "screenshot_sha256": insp.sha256_file(str(dest)),
                    "geometry": {"width": dims[0], "height": dims[1]},
                    "expected_totals": ack.get("expected_totals"),
                    "capture": "native-simctl",
                    "screenshot_mask": resolved_mask or "default",
                    "session_nonce": nonce,
                    "session_domain": domain,
                    "seq": seq,
                }
                if isinstance(provenance, dict):
                    record["app_provenance"] = provenance
                frame_record_path(run_dir, frame).write_text(
                    json.dumps(record, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8")
                frame_records.append(record)
            else:
                record = record_pending_frame(
                    run_dir=run_dir, frame=frame, png_src=str(dest),
                    captured_at_iso=_session_filed_at_iso(),
                    request=payload,
                    request_sha256=env["request_sha256"],
                    reason=pending_reason,
                    pinned_totals=pinned_totals,
                    expected_geometry=geo,
                    device_udid=udid, mask=None,
                    session_binding={"session_nonce": nonce,
                                     "session_domain": domain, "seq": seq})
                record["device_key"] = device_key
                frame_record_path(run_dir, frame).write_text(
                    json.dumps(record, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8")
                frame_records.append(record)
            prev = env

        if domain == "realtime" and len(anchor_ids) > 1:
            raise FrameError(
                f"real-time session minted {len(anchor_ids)} activity "
                "anchors; exactly one anchor per session")
        if hold_open:
            # Hold-open: the session stays RUNNING with its verified anchor
            # while the live-capture driver runs the button dance (consent,
            # Home/compact, powerx2/lock). No cleanup is issued until the
            # driver finishes explicitly. Bounded by the hold window (at
            # most the existing CLEANUP deadline, under POLL: no deadline
            # increases); any driver failure fails closed through the
            # normal contamination path (cleanup still runs below).
            if len(anchor_ids) != 1:
                raise FrameError(
                    "hold-open live capture requires exactly one verified "
                    "anchor before any capture; failing closed")
            anchor_id = next(iter(anchor_ids))
            live_started_at: str | None = None
            for ack in acks:
                live = ack.get("live_activity")
                if isinstance(live, dict) and live.get("started_at"):
                    live_started_at = live["started_at"]
                    break
            if not live_started_at:
                raise FrameError(
                    "hold-open live capture requires the anchor capture "
                    "window (live_activity.started_at); failing closed")
            # Cold-daemon warm-up (run 42051429064): one `argent run
            # describe` AFTER launch/ready but BEFORE the hold phase
            # starts — never inside the hold budget. Success warms the
            # daemon and the result is discarded (log only). Failure is
            # recorded honestly as warmup_failed with detail and the
            # session continues (the hold driver still tries; its own
            # timeouts still gate). Never aborts, never retries (one
            # shot).
            if hid is not None:
                _wt0 = clock()
                try:
                    hid.ax_dump()
                except FrameError as _wexc:
                    try:
                        _wms = (clock() - _wt0) * 1000.0
                    except Exception:
                        _wms = 0.0
                    hid_ms.append({"op": "describe-warmup",
                                   "ms": float(_wms)})
                    hold_record["warmup"] = {
                        "status": "warmup_failed",
                        "detail": str(_wexc)[:300],
                    }
                else:
                    try:
                        _wms = (clock() - _wt0) * 1000.0
                    except Exception:
                        _wms = 0.0
                    hid_ms.append({"op": "describe-warmup",
                                   "ms": float(_wms)})
                    hold_record["warmup"] = {"status": "ok"}
            stats.start("hold")
            try:
                live_record = run_live_capture(
                    hid=hid, run=run, udid=udid, geometry=geo,
                    run_dir=run_dir, anchor_id=anchor_id,
                    live_started_at=live_started_at,
                    timeout_s=hold_timeout_s, clock=clock,
                    interval_s=interval_s, sleeper=sleeper, stats=stats)
            finally:
                try:
                    stats.stop("hold")
                except sess.SessionError:
                    pass
            (run_dir / "staging" / "live-capture.json").write_text(
                json.dumps(live_record, indent=2, sort_keys=True) + "\n",
                encoding="utf-8")
            stats.count("live_capture")
            hold_record.update({"anchor": anchor_id,
                                "live_capture": "staging/live-capture.json"})
    except FrameError as exc:
        failures.append(str(exc))
    finally:
        app_cleanup: dict[str, Any] = {"status": "unverified"}
        chrome_restored = False
        app_terminated = False
        try:
            if container and envelopes:
                last = envelopes[-1]
                stats.start("cleanup")
                argv = sess.build_cleanup_argv(
                    udid, bid, run_id, last["request_sha256"],
                    session_nonce=nonce, session_domain=domain,
                    final_seq=len(envelopes) - 1)
                try:
                    # The cleanup spawn lives inside this fail-closed
                    # region: a hang past the runner timeout (or missing
                    # binary) becomes an appended failure with an
                    # unverified cleanup ack, never a receipt-skipping
                    # escape (run 41817895686 ipad13-en-r2 left no receipt
                    # and leaked the lease). No retry, no timeout change.
                    _counted(run, argv, stats)
                    ack, ack_attempts = poll_session_cleanup_ack(
                        Path(container) / "Documents", run_id=run_id,
                        request_sha=last["request_sha256"],
                        want_nonce=nonce, want_domain=domain,
                        want_final_seq=len(envelopes) - 1,
                        timeout_s=CLEANUP_TIMEOUT_S, interval_s=interval_s,
                        sleeper=sleeper, clock=clock)
                    stats.count("poll_attempt", ack_attempts)
                    app_cleanup = {
                        "status": ack.get("status"),
                        "run_id": ack.get("run_id"),
                        "request_sha256": ack.get("request_sha256"),
                        "session_nonce": ack.get("session_nonce"),
                        "final_seq": ack.get("final_seq"),
                        "transcript": ack.get("transcript"),
                        "ended_activity_ids": ack.get("ended_activity_ids"),
                        "removed_session": ack.get("removed_session"),
                        "removed_session_queue":
                            ack.get("removed_session_queue"),
                    }
                    ack_errs = validate_cleanup_ack(
                        ack, expect_activity_id=_session_anchor(acks))
                    if ack_errs:
                        failures.extend(ack_errs)
                    cover_errs = _ack_transcript_covers(ack, envelopes)
                    if cover_errs:
                        failures.extend(cover_errs)
                    queue_errs = _require_queue_removal(ack)
                    if queue_errs:
                        failures.extend(queue_errs)
                except (CleanupRefused, FrameError) as exc:
                    app_cleanup = {"status": "unverified",
                                   "error": str(exc)[:300]}
                    failures.append(str(exc))
                finally:
                    try:
                        stats.stop("cleanup")
                    except sess.SessionError:
                        pass
            else:
                failures.append("no command was accepted; cleanup unattempted")
        finally:
            try:
                if snap:
                    restore_chrome(
                        lambda argv: _counted(run, argv, stats), udid, snap,
                        True)
                    chrome_restored = True
            except FrameError as exc:
                failures.append(str(exc))
            try:
                terminate_app(
                    lambda argv: _counted(run, argv, stats), udid, bid)
                app_terminated = True
            except FrameError as exc:
                failures.append(str(exc))
            # Host-side removal proof: the ack claims identity-scoped
            # queue removal, and the owned dir must actually be gone now
            # that cleanup acknowledged. A surviving dir catches a lying
            # ack; absence is the expected steady state.
            if container and nonce:
                qdir = (Path(container) / "Documents"
                        / sess.SESSIONS_DIRNAME / nonce)
                try:
                    if qdir.is_symlink():
                        failures.append(
                            "owned queue dir is a symlink; refusing escape")
                    elif qdir.exists():
                        try:
                            leftovers = sorted(
                                p.name for p in qdir.iterdir())[:8]
                        except OSError:
                            leftovers = ["<unlistable>"]
                        failures.append(
                            f"owned queue dir not removed: session {nonce} "
                            f"still holds {leftovers}")
                except OSError as exc:
                    failures.append(f"cannot verify queue removal: {exc}")
        transcript = [sess.transcript_entry(e) for e in envelopes]
        receipt = {
            "schema_version": 1,
            "session_nonce": nonce,
            "run_id": run_id,
            "session_domain": domain,
            "device_udid": udid,
            "device_key": device_key,
            "final_seq": len(envelopes) - 1 if envelopes else -1,
            "status": "complete" if not failures else "partial",
            "failures": failures,
            "transcript": transcript,
            "app_cleanup": app_cleanup,
            "runner_verified": {
                "chrome_restored": chrome_restored,
                "process_terminated": app_terminated,
                "lease_released": False,
            },
        }
        try:
            (run_dir / "sessions").mkdir(parents=True, exist_ok=True)
            # Interim write is explicitly partial: probe, session
            # record, lease release, and the final rewrite still lie
            # ahead, so a kill in that window must never leave an
            # on-disk "complete" for a status+transcript-only reader.
            # The interim note lives on this copy only — final
            # failures below never carry it. Transcript/stats stay for
            # debug on kill.
            interim = dict(
                receipt, status="partial",
                failures=[*failures,
                          "interim: island probe, session record, and "
                          "lease release still pending; final status "
                          "lands on the rewrite below"])
            (run_dir / "sessions" / f"{nonce}.receipt.json").write_text(
                json.dumps(interim, indent=2, sort_keys=True) + "\n",
                encoding="utf-8")
        except OSError as exc:
            failures.append(f"cannot persist session receipt: {exc}")
            receipt["status"] = "partial"
        if domain == "realtime" and not island and not failures:
            # Attested probe only: the owned device's actual model identifier
            # must confirm the absence. Any attestation failure contaminates
            # the session (partial receipt) — never a silent catalog claim.
            try:
                stats.start("probe")
                # Raw run with stats: the inner _read_device_entry
                # records exactly one trail event/counter per spawn
                # (a counted lambda here would double-record).
                probe = probe_island_capability(
                    run, udid,
                    device_key=device_key, run_id=run_id,
                    session_nonce=nonce, geometry=geo, stats=stats)
                stats.stop("probe")
                if probe.get("island_available") is not False:
                    raise FrameError(
                        "attested device reports an island; refusing N/A")
                (run_dir / "sessions" / "island-probe.json").write_text(
                    json.dumps(probe, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8")
            except (FrameError, OSError, sess.SessionError) as exc:
                try:
                    stats.stop("probe")
                except sess.SessionError:
                    pass
                failures.append(f"island probe unattested: {exc}")
                receipt["status"] = "partial"
        session_record = {
            "schema_version": 1,
            "run_id": run_id,
            "device_udid": udid,
            "device_key": device_key,
            "session_domain": domain,
            "session_nonce": nonce,
            "frames": frames,
            "request_sha256s": [e["request_sha256"] for e in envelopes],
            "container": container,
            "snapshot": snap,
            "app_provenance": provenance,
            "device_model": model_proof,
            "anchor_ids": sorted(anchor_ids),
            "hold_open": hold_record,
            "stats": {**stats.to_dict(), "hid_ms": [dict(e) for e in hid_ms]},
            "status": "complete" if not failures else "partial",
        }
        try:
            (run_dir / "sessions" / f"{nonce}.json").write_text(
                json.dumps(session_record, indent=2, sort_keys=True) + "\n",
                encoding="utf-8")
        except OSError as exc:
            failures.append(f"cannot persist session record: {exc}")
        try:
            guard.release_lock(lock_path, run_id)
            lease_released = True
            receipt["runner_verified"]["lease_released"] = True
        except (guard.GuardError, OSError) as exc:
            failures.append(f"cannot release the device lease: {exc}")
        receipt["status"] = "complete" if not failures else "partial"
        receipt["failures"] = failures
        try:
            (run_dir / "sessions" / f"{nonce}.receipt.json").write_text(
                json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                encoding="utf-8")
        except OSError as exc:
            failures.append(f"cannot persist session receipt: {exc}")
            receipt["status"] = "partial"
        _ = lease_released
    if failures:
        raise FrameError(
            f"session {domain} {run_id} contaminated: {failures[0]} "
            f"({len(failures)} failure(s)); later locales must stop; "
            "earlier exports preserved with a partial receipt")
    return {
        "run_id": run_id,
        "device_udid": udid,
        "device_key": device_key,
        "session_domain": domain,
        "session_nonce": nonce,
        "frames": frame_records,
        "receipt": receipt,
        "stats": {**stats.to_dict(), "hid_ms": [dict(e) for e in hid_ms]},
        "status": "complete",
    }


def _session_anchor(acks: list[dict]) -> str | None:
    """Single real-time activity id requiring end-proof; None when pinned."""
    ids = {la["activity_id"] for ack in acks
           for la in [ack.get("live_activity")]
           if isinstance(la, dict) and la.get("activity_id")}
    if len(ids) > 1:
        raise FrameError("real-time session minted multiple activity anchors")
    return next(iter(ids)) if ids else None


def _session_filed_at_iso() -> str:
    """Filing timestamp for pending stubs (marker only, never evidence).

    Pending stubs carry no capture window; this stamp only marks when
    the placeholder was filed. Genuine replacement via
    record-external-frame supplies the real capture window. No clock math.
    """
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()
