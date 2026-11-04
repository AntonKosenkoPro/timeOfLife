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
  capture windows and human observations. No fabrication, no OCR.
- record_pending_frame: deterministic human-handoff stubs for LA states
  without genuine pixels yet (used internally by run_session).
- finalize_run (session-receipt gated) / finalize_two_runs: assemble
  manifests, re-verify evidence, semantic (never byte-equal) comparison.

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
import shutil
import subprocess
import sys
import time
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
    observation_path: str,
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

    No device I/O. Fails unless the PNG has native geometry, the state is
    ready (with pin), and the human observation binds to the actual file
    hash with wall time inside ±2s. `mask` documents the capture policy
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
    try:
        observation = json.loads(Path(observation_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise FrameError(f"cannot read observation file: {exc}")
    la = state.get("live_activity")
    errs = insp.verify_la_observation(la, str(src), captured_at_iso, observation)
    if errs:
        raise FrameError("; ".join(errs))
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
            "observed_elapsed_s": observation.get("observed_elapsed_s"),
        },
        "observation_sha256": insp.sha256_file(observation_path),
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
    like every other record) but carries NO `capture_window` /
    `observation_sha256`, so `finalize_run` reports the frame as
    needs-inspection ("human timer observation not registered") instead
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
                "(tampered or stale observation binding)"
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
    pending: list[str] = []
    present_la = [f for f in req.LA_FRAMES if f not in na_frames]
    if "la-lock" not in present_la:
        # The Lock Screen state is required on every device; only island
        # states can be N/A (with an attested probe).
        raise FrameError("la-lock frame required; never not-applicable")
    for la_frame in present_la:
        la = next(r for r in records if r["frame"] == la_frame)
        if "capture_window" not in la or "observation_sha256" not in la:
            pending.append(f"{la_frame}: human timer observation not registered")
            continue
        cw = la["capture_window"]
        try:
            wall = (
                insp.parse_aware_iso(cw["captured_at_iso"])
                - insp.parse_aware_iso(cw["started_at"])
            ).total_seconds()
        except (insp.InspectionError, KeyError, TypeError) as exc:
            raise FrameError(f"{la_frame} capture window malformed: {exc}")
        observed = cw.get("observed_elapsed_s")
        if not insp.is_strict_nonneg_number(observed) or abs(
            wall - float(observed)
        ) > insp.LA_TOLERANCE_S:
            raise FrameError(
                f"{la_frame} registered observation no longer validates "
                "against its capture window"
            )
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
    """
    try:
        proc = run(argv)
    except (subprocess.TimeoutExpired, OSError) as exc:
        raise FrameError(
            f"simctl spawn failed: {' '.join(argv)} -> {exc!r:.300}"
        )
    if stats is not None:
        stats.count("simctl_spawn")
    return proc


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
    if domain not in sess.SESSION_DOMAINS:
        raise FrameError(f"unknown session_domain {domain!r}")
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
        # container/provenance — never per frame or command.
        try:
            model_proof = verify_owned_device(
                lambda argv: _counted(run, argv, stats), udid,
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
            (run_dir / "sessions" / f"{nonce}.receipt.json").write_text(
                json.dumps(receipt, indent=2, sort_keys=True) + "\n",
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
                probe = probe_island_capability(
                    lambda argv: _counted(run, argv, stats), udid,
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
            "stats": stats.to_dict(),
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
        "stats": stats.to_dict(),
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

    Pending stubs carry no observation binding; this stamp only marks when
    the placeholder was filed. Genuine replacement via
    record-external-frame supplies the real capture window. No clock math.
    """
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()
