#!/usr/bin/env python3
"""Lease-gated frame execution with injectable subprocess (stdlib only).

Every simctl spawn goes through the ``run`` callable and every sleep
through ``sleeper``, so unit tests inject fakes and no real device is
ever touched without the lease. Production wires ``subprocess.run``.

Verb split (task 4.1):
- prepare_frame: write request -> copy into container Documents -> snapshot
  chrome -> abort on preexisting overrides -> apply -> launch -> poll state
  to ready. Covers all 7 frames (la-* included; their system
  presentation is awaited externally afterwards).
- capture_app_frame: native `io screenshot` export for the first 4
  app-clock frames, only after ready. Refuses la-* frames.
- record_external_frame: registers the genuine Lock Screen / Island PNGs
  produced externally (authored Argent flow after handoff) with their
  capture windows and human observations. No fabrication, no OCR.
- finalize_run / finalize_two_runs: assemble manifests, re-verify evidence,
  semantic (never byte-equal) comparison.

Cleanup note: simctl-side restore (appearance/content_size/status_bar) is
implemented exactly from snapshots. Ending capture-owned Live Activities
or wiping the app session has NO confirmed app hook: do NOT invent a core
API (no synthetic launch args). That hook is pending main/core
coordination; `terminate` (a confirmed simctl surface) is offered in the
teardown plan, activity teardown stays explicitly incomplete.
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


def session_path(run_dir: Path, frame: str) -> Path:
    return run_dir / "sessions" / f"{frame}.json"


def teardown_path(run_dir: Path, frame: str) -> Path:
    return run_dir / "sessions" / f"{frame}.teardown.json"


def frame_png_path(run_dir: Path, frame: str) -> Path:
    return run_dir / "frames" / f"{frame}.png"


def frame_record_path(run_dir: Path, frame: str) -> Path:
    return run_dir / "frames" / f"{frame}.json"


def evidence_path(run_dir: Path, name: str) -> Path:
    return run_dir / "evidence" / name


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


def poll_state_for(
    docs_dir: Path,
    *,
    want_sha: str,
    want_frame: str,
    timeout_s: float = POLL_TIMEOUT_S,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> tuple[dict, bytes, int]:
    """Await the CURRENT request's ready state.

    Stale shas/frames are ignored, `preparing` keeps polling, and a
    current `invalid`/`failure`/unknown status fails promptly (no full
    timeout wait). Raises FrameError on refusal or deadline.
    """
    deadline = clock() + timeout_s
    attempts = 0
    while True:
        attempts += 1
        state, raw = _read_state_dict(docs_dir)
        if (
            state is not None
            and state.get("request_sha256") == want_sha
            and state.get("frame") == want_frame
        ):
            status = state.get("status")
            if status == "ready":
                assert raw is not None
                return state, raw, attempts
            if status in ("invalid", "failure"):
                detail = ""
                err = state.get("error")
                if isinstance(err, dict) and err.get("code"):
                    detail = f": {err['code']}"
                raise FrameError(
                    f"app refused current request ({status}{detail}) "
                    f"after {attempts} poll(s)"
                )
            if status != "preparing":
                raise FrameError(
                    f"unknown status {status!r} for current request "
                    f"after {attempts} poll(s)"
                )
        if clock() >= deadline:
            raise FrameError(
                f"current ready state never arrived after {attempts} poll(s) "
                f"({timeout_s}s); no screenshot taken"
            )
        sleeper(interval_s)


def prepare_frame(
    run: Callable,
    udid: str,
    base_request: dict,
    frame: str,
    run_dir: Path,
    *,
    bid: str = req.SCREENSHOT_BID,
    pinned_totals: dict | None = None,
    timeout_s: float = POLL_TIMEOUT_S,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> dict[str, Any]:
    """Full per-frame preparation ending in app-attested ready.

    The derived request carries run_id (injected from the run directory
    name when the base lacks one): the app echoes it into capture-state
    run_id, and the cleanup hook verifies against it. Semantic hashes
    exclude run_id, so cross-run comparison is unaffected.
    """
    try:
        derived = req.build_frame_request(base_request, frame)
    except req.RequestError as exc:
        raise FrameError(f"invalid frame request: {exc}")
    if "run_id" not in derived:
        derived["run_id"] = run_dir.name
    elif derived["run_id"] != run_dir.name:
        raise FrameError(
            f"base run_id {derived['run_id']!r} != run directory "
            f"{run_dir.name!r}; per-frame requests must carry the actual "
            "run id so cleanup binding stays consistent"
        )
    errs = req.validate_request_dict(derived)
    if errs:
        raise FrameError(f"invalid frame request: {errs[0]}")
    raw = req.canonical_bytes(derived)
    digest = req.request_sha256_of_bytes(raw)

    requests_dir = run_dir / "requests"
    sessions_dir = run_dir / "sessions"
    requests_dir.mkdir(parents=True, exist_ok=True)
    sessions_dir.mkdir(parents=True, exist_ok=True)
    request_file = requests_dir / f"{frame}.{pf.REQUEST_FILENAME}"
    request_file.write_bytes(raw)

    container = get_container_data(run, udid, bid)
    docs = Path(container) / "Documents"
    provenance = app_provenance(run, udid, bid)
    try:
        docs.mkdir(parents=True, exist_ok=True)
        (docs / pf.REQUEST_FILENAME).write_bytes(raw)
    except OSError as exc:
        raise FrameError(f"cannot stage request in container {docs}: {exc}")
    clear_owned_state(docs)

    snap = snapshot_chrome(run, udid)
    ensure_clean_chrome(snap)
    try:
        apply_chrome(run, udid)
        launch_capture(run, udid, bid)
    except FrameError:
        try:
            restore_chrome(run, udid, snap, True)
        except FrameError as restore_exc:
            raise FrameError(f"launch failed; restore also failed: {restore_exc}")
        raise
    try:
        state, _raw_state, attempts = poll_state_for(
            docs, want_sha=digest, want_frame=frame,
            timeout_s=timeout_s, interval_s=interval_s,
            sleeper=sleeper, clock=clock,
        )
    except FrameError as exc:
        try:
            restore_chrome(run, udid, snap, True)
        except FrameError as restore_exc:
            raise FrameError(f"{exc}; restore also failed: {restore_exc}")
        raise
    verdict, v_errs = sc.validate_state_dict(state, derived, digest, pinned_totals)
    if verdict != sc.OK:
        try:
            restore_chrome(run, udid, snap, True)
        except FrameError as restore_exc:
            raise FrameError(
                f"state verdict {verdict}: {'; '.join(v_errs) or 'not ready'}; "
                f"restore also failed: {restore_exc}"
            )
        raise FrameError(
            f"state verdict {verdict}: {'; '.join(v_errs) or 'not ready'}"
        )
    session = {
        "schema_version": 1,
        "frame": frame,
        "mode": derived["mode"],
        "device_udid": udid,
        "run_id": derived["run_id"],
        "request_file": str(request_file),
        "request_sha256": digest,
        "request_semantic_sha256": req.semantic_sha256(derived),
        "container": container,
        "snapshot": snap,
        "status_bar_overridden_by_session": True,
        "state_verdict": "ready",
        "expected_totals": state["expected_totals"],
        "app_provenance": provenance,
        "poll_attempts": attempts,
    }
    session_path(run_dir, frame).write_text(
        json.dumps(session, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return session


def teardown_frame(
    run: Callable,
    udid: str,
    run_dir: Path,
    frame: str,
    *,
    bid: str = req.SCREENSHOT_BID,
    timeout_s: float = CLEANUP_TIMEOUT_S,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> dict[str, Any]:
    """Verified teardown: app-hook cleanup first, chrome+terminate always.

    Launches `SCREENSHOT_CLEANUP=<run_id> SCREENSHOT_CLEANUP_SHA=<sha>`,
    polls the ack for matching ids, and validates cleanup fields (ended
    activity ids incl. the real LA anchor when applicable, session
    directory actually removed). Chrome restore + terminate run
    afterwards no matter the ack outcome; exports are never touched.
    Status is "complete" only when everything verifies, else "partial".
    """
    try:
        session = json.loads(session_path(run_dir, frame).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise FrameError(f"session record missing/unreadable for {frame!r}: {exc}")
    if session.get("device_udid") != udid:
        raise FrameError(
            f"teardown device {udid!r} != session device "
            f"{session.get('device_udid')!r}; refusing cross-device cleanup"
        )
    run_id = session.get("run_id")
    request_sha = session.get("request_sha256")
    if not run_id or not request_sha:
        raise FrameError(
            f"session for {frame!r} has no run_id/request_sha256; "
            "re-run prepare-frame"
        )
    try:
        docs = Path(session["container"]) / "Documents"
    except KeyError as exc:
        raise FrameError(f"session record missing container path: {exc}")
    failures: list[str] = []
    try:
        launch_cleanup(run, udid, bid, run_id, request_sha)
        ack, ack_attempts = poll_cleanup_ack(
            docs, run_id=run_id, request_sha=request_sha,
            timeout_s=timeout_s, interval_s=interval_s,
            sleeper=sleeper, clock=clock,
        )
        expect_activity = _expected_activity_id(session, docs)
        ack_errs = validate_cleanup_ack(ack, expect_activity_id=expect_activity)
        app_cleanup: dict[str, Any] = {
            "status": ack.get("status"),
            "run_id": ack.get("run_id"),
            "request_sha256": ack.get("request_sha256"),
            "ended_activity_ids": ack.get("ended_activity_ids"),
            "removed_session": ack.get("removed_session"),
            "poll_attempts": ack_attempts,
        }
        if ack_errs:
            failures.extend(ack_errs)
    except CleanupRefused as exc:
        app_cleanup = {
            "status": exc.ack_status,
            "run_id": run_id,
            "request_sha256": request_sha,
            "error": str(exc),
        }
        failures.append(str(exc))
    except FrameError as exc:
        app_cleanup = {"status": "unverified", "error": str(exc)}
        failures.append(str(exc))
    snap = session.get("snapshot")
    if not isinstance(snap, dict) or not {"appearance", "content_size",
                                          "status_bar_list"} <= set(snap):
        snap = {"appearance": "light", "content_size": "large",
                "status_bar_list": "<unknown>"}
        session_overrode = False
    else:
        session_overrode = bool(session.get("status_bar_overridden_by_session"))
    chrome_restored = True
    try:
        restore_chrome(run, udid, snap, session_overrode)
    except FrameError as exc:
        failures.append(str(exc))
        chrome_restored = False
    app_terminated = True
    try:
        terminate_app(run, udid, bid)
    except FrameError as exc:
        failures.append(str(exc))
        app_terminated = False
    record = {
        "schema_version": 1,
        "frame": frame,
        "device_udid": udid,
        "run_id": run_id,
        "chrome_restored": chrome_restored,
        "app_terminated": app_terminated,
        "app_cleanup": app_cleanup,
        "status": "complete" if not failures else "partial",
        "failures": failures,
    }
    teardown_path(run_dir, frame).write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return record


def launch_cleanup(run: Callable, udid: str, bid: str, run_id: str, sha: str) -> str:
    argv = pf.cleanup_launch_argv(udid, bid, run_id, sha)
    return _check(run(argv), argv, "launch cleanup")


def poll_cleanup_ack(
    docs_dir: Path,
    *,
    run_id: str,
    request_sha: str,
    timeout_s: float = CLEANUP_TIMEOUT_S,
    interval_s: float = POLL_INTERVAL_S,
    sleeper: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> tuple[dict, int]:
    """Await the cleanup ack matching this invocation.

    Stale (foreign run_id/sha) acks are ignored, never accepted. A
    matching ack with status mismatch/failure/unknown fails promptly.
    Raises FrameError on refusal or deadline.
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
        ):
            status = ack.get("status")
            if status == "cleaned":
                return ack, attempts
            if status in ("mismatch", "failure"):
                detail = ""
                err = ack.get("error")
                if isinstance(err, dict) and err.get("code"):
                    detail = f": {err['code']}"
                raise CleanupRefused(
                    status,
                    f"cleanup refused ({status}{detail}) after {attempts} poll(s); "
                    "nothing was touched on device",
                )
            raise CleanupRefused(
                status, f"unknown cleanup status {status!r} after {attempts} poll(s)"
            )
        if clock() >= deadline:
            raise FrameError(
                f"cleanup ack never arrived after {attempts} poll(s) "
                f"({timeout_s}s)"
            )
        sleeper(interval_s)


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


def _expected_activity_id(session: dict, docs: Path) -> str | None:
    """Real LA anchor requiring explicit end-proof; None for pinned frames."""
    if session.get("mode") != req.MODE_REALTIME:
        return None
    state, _raw = _read_state_dict(docs)
    if state is None:
        raise FrameError("cannot verify activity teardown: state unreadable")
    la = state.get("live_activity")
    if not isinstance(la, dict) or not la.get("activity_id"):
        raise FrameError("cannot verify activity teardown: no live anchor in state")
    return la["activity_id"]


def _live_state_for_session(session: dict) -> tuple[dict, dict]:
    """Re-read and re-validate the live app state for a session.

    Returns (state, request_doc). Fails closed on view switches, stale
    sessions, or unreadable files: a ready session file alone never
    authorizes a capture.
    """
    try:
        request_raw = Path(session["request_file"]).read_bytes()
        request_doc = json.loads(request_raw.decode("utf-8"))
    except (OSError, ValueError, KeyError) as exc:
        raise FrameError(f"session request file unreadable: {exc}")
    if not isinstance(request_doc, dict):
        raise FrameError("session request file must contain a JSON object")
    try:
        docs = Path(session["container"]) / "Documents"
        state, _raw = _read_state_dict(docs)
    except KeyError as exc:
        raise FrameError(f"session record missing container path: {exc}")
    if state is None:
        raise FrameError("live capture state unreadable; app may have moved on")
    pin = session.get("expected_totals")
    if not isinstance(pin, dict):
        raise FrameError("session carries no pinned totals for revalidation")
    digest = req.request_sha256_of_bytes(request_raw)
    # Recompute over the exact staged bytes when available.
    verdict, v_errs = sc.validate_state_dict(state, request_doc, digest, pin)
    if verdict != sc.OK:
        raise FrameError(
            f"live state revalidation {verdict}: "
            f"{'; '.join(v_errs) or 'view switched or stale'}"
        )
    return state, request_doc


def capture_app_frame(
    run: Callable,
    udid: str,
    run_dir: Path,
    frame: str,
    *,
    expected_geometry: tuple[int, int] = req.PILOT_GEOMETRY,
    auto_teardown: bool = False,
    bid: str = req.SCREENSHOT_BID,
) -> dict[str, Any]:
    """Native export for app-clock frames after live revalidation.

    Refuses la-* frames (use record-external-frame), cross-device calls,
    and stale sessions: the live capture-state.json must match the session
    right now. Screenshot/geometry failures restore chrome too. With
    auto_teardown, teardown runs on success as well.
    """
    if frame in req.LA_FRAMES:
        raise FrameError(
            "la-* frames have no native in-app export; use record-external-frame "
            "with the genuine Lock Screen / Island PNG"
        )
    try:
        session = json.loads(session_path(run_dir, frame).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise FrameError(f"session record missing/unreadable for {frame!r}: {exc}")
    if session.get("state_verdict") != "ready":
        raise FrameError(f"session for {frame!r} is not ready; run prepare-frame first")
    if session.get("device_udid") != udid:
        raise FrameError(
            f"capture device {udid!r} != session device "
            f"{session.get('device_udid')!r}; refusing cross-device export"
        )
    _live_state_for_session(session)
    dest = frame_png_path(run_dir, frame)
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        argv = pf.screenshot_argv(udid, str(dest))
        _check(run(argv), argv, "io screenshot")
        try:
            dims = insp.png_dimensions(str(dest))
        except insp.InspectionError as exc:
            raise FrameError(str(exc))
        if dims != (expected_geometry[0], expected_geometry[1]):
            raise FrameError(
                f"screenshot geometry {dims} != expected {expected_geometry}; "
                "never stretch another device's capture"
            )
    except FrameError:
        try:
            teardown_frame(run, udid, run_dir, frame, bid=bid)
        except FrameError as teardown_exc:
            raise FrameError(f"export failed; teardown also failed: {teardown_exc}")
        raise
    request_doc = json.loads(Path(session["request_file"]).read_text(encoding="utf-8"))
    record = {
        "schema_version": 1,
        "frame": frame,
        "mode": session.get("mode"),
        "device_udid": session.get("device_udid", "unknown"),
        "run_id": session.get("run_id"),
        "deck_version": request_doc.get("deck_version"),
        "treatment": request_doc.get("treatment"),
        "request_sha256": session.get("request_sha256"),
        "request_semantic_sha256": session.get("request_semantic_sha256"),
        "screenshot_sha256": insp.sha256_file(str(dest)),
        "geometry": {"width": dims[0], "height": dims[1]},
        "expected_totals": session.get("expected_totals"),
        "capture": "native-simctl",
    }
    if isinstance(session.get("app_provenance"), dict):
        record["app_provenance"] = session["app_provenance"]
    frame_record_path(run_dir, frame).write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if auto_teardown:
        teardown_frame(run, udid, run_dir, frame, bid=bid)
    return record


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
) -> dict[str, Any]:
    """Register an externally produced PNG (genuine Lock Screen / Island capture).

    No device I/O. Fails unless the PNG has native geometry, the state is
    ready (with pin), and the human observation binds to the actual file
    hash with wall time inside ±2s.
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
    dest = frame_png_path(run_dir, frame)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest)
    try:
        session_doc = json.loads(
            session_path(run_dir, frame).read_text(encoding="utf-8")
        )
        session_provenance = session_doc.get("app_provenance")
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
    }
    if isinstance(session_provenance, dict):
        record["app_provenance"] = session_provenance
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


def finalize_run(
    run_dir: Path, provenance: dict | None = None
) -> tuple[dict, list[str]]:
    """Assemble run-manifest.json. Returns (manifest, pending_evidence).

    Every frame PNG is rehashed and rebound to its record (existence,
    hash, geometry, frame id); deck/treatment/geometry must agree across
    records. Missing/tampered files and record mismatches are fatal
    FrameErrors, never needs-inspection. Missing human evidence or
    missing/failed teardowns yield needs-inspection instead. Teardown
    records are required but report "partial" until the app-owned
    activity/session hook lands (pending core coordination).
    """
    records = [load_frame_record(run_dir, f) for f in req.PILOT_FRAMES]
    for expected, rec in zip(req.PILOT_FRAMES, records):
        if rec.get("frame") != expected:
            raise FrameError(
                f"frame record mismatch: file for {expected!r} claims "
                f"{rec.get('frame')!r}"
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
    pending: list[str] = []
    for la_frame in req.LA_FRAMES:
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
    for frame in req.PILOT_FRAMES:
        try:
            td = json.loads(teardown_path(run_dir, frame).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pending.append(f"{frame}: teardown not performed")
            continue
        if not isinstance(td, dict) or td.get("status") != "complete":
            reason = ""
            if isinstance(td, dict) and td.get("failures"):
                reason = f": {td['failures'][0]}"[:160]
            pending.append(f"{frame}: teardown not complete{reason}")
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
        "teardown verified per frame; app activity/session hook resolved "
        "via capture-cleanup.json ack"
    )
    (run_dir / "run-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest, pending
