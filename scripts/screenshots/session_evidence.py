#!/usr/bin/env python3
"""Pure run-evidence validator shared by finalizer/panels (tasks 4.4/4.6).

Single chokepoint: validate_run_evidence(run_dir, manifest,
required_frames=None) -> list[str]. Structural checks only (identity,
transcript + combined host/app receipt, paths/symlinks, N/A probe,
pending-vs-genuine presence); numeric LA tolerance stays in inspection.py
and per-frame state checks stay in state_check.py — never duplicated here.

Fail closed everywhere: missing/partial receipts, uncovered transcripts,
identity drift, symlink/traversal escape, fabricated N/A pixels, and
genuine claims without observation binding are all errors. Honest pending
handoff stubs are NOT errors (status stays needs-inspection downstream).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import inspection as insp
import request_schema as rs

HEX64_LEN = 64


def _is_hex64(v: Any) -> bool:
    return isinstance(v, str) and len(v) == HEX64_LEN and all(
        c in "0123456789abcdef" for c in v)


def _load_json(path: Path) -> tuple[Any, str | None]:
    try:
        return json.loads(path.read_bytes().decode("utf-8")), None
    except (OSError, ValueError, UnicodeError) as exc:
        return None, f"unreadable JSON at {path}: {exc}"


def _no_traversal(value: Any) -> bool:
    return isinstance(value, str) and ".." not in value and \
        not value.startswith(("/", "~"))


def validate_run_evidence(run_dir: Any, manifest: Any,
                          required_frames: Any = None) -> list[str]:
    """Validate on-disk session evidence for a run. Returns error strings."""
    errs: list[str] = []
    if isinstance(run_dir, str):
        run_dir = Path(run_dir)
    if not isinstance(run_dir, Path) or not run_dir.is_dir():
        return [f"run_dir {run_dir!r} is not a directory"]
    # Symlinked run roots escape the owned out-root; refuse.
    if run_dir.is_symlink():
        return [f"run_dir {run_dir} is a symlink; refusing escape"]
    if not isinstance(manifest, dict):
        return ["manifest must be a JSON object"]
    frames = manifest.get("frames")
    if not isinstance(frames, list) or not frames:
        return ["manifest frames must be a non-empty list"]
    by_frame = {r.get("frame"): r for r in frames if isinstance(r, dict)}
    if required_frames is None:
        required = [r.get("frame") for r in frames
                    if isinstance(r, dict) and isinstance(r.get("frame"), str)]
    elif not isinstance(required_frames, list) or not all(
            isinstance(f, str) for f in required_frames):
        return ["required_frames must be a list of frame ids"]
    else:
        required = list(required_frames)
    for frame in required:
        if frame not in rs.PILOT_FRAMES:
            errs.append(f"unknown required frame {frame!r}")
        elif frame not in by_frame:
            errs.append(f"required frame {frame!r} missing from manifest")
    if errs:
        return errs

    receipts = _index_receipts(run_dir, errs)
    probe = _load_island_probe(run_dir, errs)
    requirement = _island_requirement(by_frame, manifest, errs)
    _check_na_metadata(manifest, requirement, errs)
    if requirement == "na-required" and probe is None:
        # A no-island device class requires an attested N/A probe whenever
        # island frames are out of scope — even for partial required_frames
        # subsets (app frames + lock). Missing attestation fails; N/A is
        # never inferred from absent files, and dropping na_frames metadata
        # cannot waive this.
        errs.append(
            "no-island device run requires an attested N/A island probe "
            "(capability attestation missing; N/A never inferred)")
    if probe is not None:
        _check_probe_binding(probe, by_frame, receipts, manifest, errs)

    for frame in required:
        rec = by_frame[frame]
        if frame in ("la-compact", "la-expanded") \
                and requirement == "na-required":
            # Island evidence on a no-island device is fabrication whether
            # or not a probe is filed: N/A means no pixels, never pixels.
            if ((run_dir / "frames" / f"{frame}.png").exists()
                    or (run_dir / "frames" / f"{frame}.json").exists()):
                errs.append(
                    f"{frame}: island pixels filed for a no-island device "
                    "(fabricated evidence refused; N/A requires a probe, "
                    "never pixels)")
                continue
        if probe is not None and frame in ("la-compact", "la-expanded"):
            # N/A island frames must have NO pixels or records filed: a
            # filed island PNG/JSON beside an N/A probe is fabricated
            # evidence, never a pass (consolidates the panels-side guard
            # into this shared helper; panels must not weaken it).
            if ((run_dir / "frames" / f"{frame}.png").exists()
                    or (run_dir / "frames" / f"{frame}.json").exists()):
                errs.append(
                    f"{frame}: island pixels filed despite an N/A probe "
                    "(fabricated evidence refused)")
                continue
        _check_frame_record(run_dir, frame, rec, errs)
        # N/A island frames: probe present + no PNG filed (see below).
        if _is_na_frame(run_dir, frame, probe):
            continue
        _check_frame_png(run_dir, frame, rec, errs)
        _check_genuine_binding(frame, rec, errs)
        _check_session_binding(run_dir, frame, rec, receipts, errs)
    _check_shared_anchor(by_frame, required, errs)
    if manifest.get("status") == "complete":
        _check_complete_status(run_dir, manifest, by_frame, errs)
    return errs


def _check_shared_anchor(by_frame: dict, required: list[str],
                         errs: list[str]) -> None:
    """One real-time anchor across the examined genuine states.

    All genuine (`external-lock-screen`) LA records under examination must
    share one live-activity start instant: separate capture times and
    observations are per-state, but the activity identity is per-session.
    Pending stubs carry no window and are excluded; a single examined
    genuine state is trivially consistent (unity cannot be judged from
    one). Fabricated N/A island records never reach here (rejected
    earlier).
    """
    anchors = set()
    for frame in required:
        rec = by_frame.get(frame)
        if not isinstance(rec, dict):
            continue
        if rec.get("capture") != "external-lock-screen":
            continue
        cw = rec.get("capture_window")
        if isinstance(cw, dict) and cw.get("started_at"):
            anchors.add(cw["started_at"])
    if len(anchors) > 1:
        errs.append("genuine live-activity states span "
                    f"{len(anchors)} start anchors; one anchor per "
                    "real-time session")


def _check_complete_status(run_dir: Path, manifest: dict, by_frame: dict,
                           errs: list[str]) -> None:
    """A `complete` manifest must match complete disk evidence.

    `complete` is a whole-manifest claim, so this examines ALL manifest
    frames plus every filed on-disk frame record — independent of the
    caller's required_frames subset (the subset only scopes per-frame
    source validation: hashes, geometry, receipts, bindings). A narrowed
    app-frames-only check with `complete` status and pending LA on disk
    fails here. Manifest-only status flips (or invented genuine claims)
    fail even when every hash still matches: any filed frame whose DISK
    record is a pending stub, or claims genuine pixels without a bound
    capture window + observation, blocks `complete`. Disk is the evidence;
    the manifest status only repeats it.
    """
    filed = {p.stem for p in (run_dir / "frames").glob("*.json")
             if not p.is_symlink()}
    for frame in sorted(set(by_frame) | filed):
        path = run_dir / "frames" / f"{frame}.json"
        obj, err = _load_json(path)
        if err is not None or not isinstance(obj, dict):
            errs.append(f"{frame}: complete status with unreadable "
                        "disk record")
            continue
        if obj.get("capture") == "external-lock-screen-pending":
            errs.append(f"{frame}: complete status with a pending disk "
                        "stub (human handoff outstanding)")
        elif obj.get("capture") == "external-lock-screen":
            cw = obj.get("capture_window")
            if not isinstance(cw, dict) or "captured_at_iso" not in cw \
                    or "observed_elapsed_s" not in cw \
                    or not obj.get("observation_sha256"):
                errs.append(f"{frame}: complete status without bound "
                            "genuine proof on disk")


def _index_receipts(run_dir: Path, errs: list[str]) -> dict[str, dict]:
    receipts: dict[str, dict] = {}
    sessions = run_dir / "sessions"
    if not sessions.is_dir():
        errs.append("sessions directory missing: no session receipts")
        return receipts
    for child in sorted(sessions.glob("*.receipt.json")):
        if child.is_symlink():
            errs.append(f"receipt {child.name} is a symlink; refusing escape")
            continue
        obj, err = _load_json(child)
        if err is not None:
            errs.append(err)
            continue
        if not isinstance(obj, dict):
            errs.append(f"receipt {child.name} must be a JSON object")
            continue
        nonce = obj.get("session_nonce")
        if not isinstance(nonce, str) or not nonce:
            errs.append(f"receipt {child.name} carries no session_nonce")
            continue
        if nonce in receipts:
            errs.append(f"duplicate receipt for session {nonce}")
        receipts[nonce] = obj
    return receipts


def _load_island_probe(run_dir: Path, errs: list[str]) -> dict | None:
    probe_path = run_dir / "sessions" / "island-probe.json"
    if not probe_path.exists():
        return None
    if probe_path.is_symlink():
        errs.append("island probe is a symlink; refusing escape")
        return None
    obj, err = _load_json(probe_path)
    if err is not None:
        errs.append(err)
        return None
    if not isinstance(obj, dict):
        errs.append("island probe must be a JSON object")
        return None
    if obj.get("island_available") is not False:
        errs.append("island probe must declare island_available=false")
        return None
    if not obj.get("reason"):
        errs.append("island probe must carry a reason")
        return None
    return obj


def _island_requirement(by_frame: dict, manifest: Any,
                        errs: list[str]) -> str | None:
    """Derive the run's island requirement from device identity.

    Returns "na-required" for no-island catalog devices, "island-capable"
    otherwise, or None (with errors) when the device class is
    indeterminable. The requirement derives from the frame records'
    unanimous device_key — never from na_frames metadata presence, so
    dropping N/A metadata cannot waive attestation.
    """
    import session as sess

    records = [r for r in by_frame.values() if isinstance(r, dict)]
    keys = {r.get("device_key") for r in records}
    if len(keys) != 1 or not isinstance(next(iter(keys)), str):
        errs.append("frame records must agree on one device_key")
        return None
    key = next(iter(keys))
    entry = sess.DEVICE_CATALOG.get(key)
    if entry is None:
        errs.append(f"unknown device_key {key!r}; "
                    "island requirement indeterminable")
        return None
    manifest_geo = manifest.get("geometry")
    catalog_geo = {"width": entry["geometry"][0],
                   "height": entry["geometry"][1]}
    if isinstance(manifest_geo, dict) and manifest_geo != catalog_geo:
        errs.append(f"manifest geometry {manifest_geo!r} contradicts "
                    f"device_key {key!r}")
        return None
    return "na-required" if entry.get("island") is False else "island-capable"


def _check_na_metadata(manifest: Any, requirement: str | None,
                       errs: list[str]) -> None:
    """Validate manifest na_frames claims without ever waiving the probe.

    na_frames, when present, must contain only island frames; an
    island-capable device must not claim any N/A; a no-island device must
    claim both island frames or none (partial N/A scope is incoherent —
    N/A is device-scoped). Absent metadata never waives the device-derived
    probe requirement (enforced separately).
    """
    na = manifest.get("na_frames", [])
    if na is None:
        na = []
    if not isinstance(na, list) or any(not isinstance(f, str) for f in na):
        errs.append("manifest na_frames must be a list of frame ids")
        return
    if any(f not in ("la-compact", "la-expanded") for f in na):
        errs.append(f"only island frames can be not-applicable, got {na!r}")
        return
    if na and requirement == "island-capable":
        errs.append(f"manifest claims N/A {na!r} on an island-capable "
                    "device (false manifest claim)")
    if na and requirement == "na-required" and set(na) != {"la-compact",
                                                          "la-expanded"}:
        errs.append(f"manifest N/A scope {na!r} is partial; a no-island "
                    "device needs both island frames N/A with a probe")


def _check_probe_binding(probe: dict, by_frame: dict, receipts: dict,
                         manifest: dict, errs: list[str]) -> None:
    """Strict N/A probe binding: the probe must attest the OWNED device.

    A catalog key or CLI flag alone is never sufficient: the probe must
    carry the actual simctl-reported model identifier (source simctl-list)
    mapping to no-island, and must join the run on run_id, device_key,
    geometry, and the realtime session nonce. Both passes carry their own
    probe explicitly (validators are per-run; cross-pass consistency lives
    in run_manifest.compare_runs, volatile run_id/nonce excluded).
    """
    import session as sess

    records = [r for r in by_frame.values() if isinstance(r, dict)]
    run_ids = {r.get("run_id") for r in records}
    keys = {r.get("device_key") for r in records}
    if probe.get("run_id") not in run_ids or len(run_ids) != 1:
        errs.append("island probe run_id does not bind this run")
    if probe.get("device_key") not in keys or len(keys) != 1:
        errs.append("island probe device_key does not bind this run")
        return
    key = probe.get("device_key")
    entry = sess.DEVICE_CATALOG.get(key) if isinstance(key, str) else None
    if entry is None or entry.get("island") is not False:
        errs.append(f"island probe device_key {key!r} is not a "
                    "no-island catalog device")
    if probe.get("geometry") != manifest.get("geometry"):
        errs.append("island probe geometry does not match the manifest")
    model = probe.get("model")
    if not isinstance(model, dict) or not model.get("deviceTypeIdentifier"):
        errs.append("island probe carries no actual model attestation "
                    "(deviceTypeIdentifier required)")
    else:
        for model_err in sess.check_catalog_model(
                key, model.get("deviceTypeIdentifier"), model.get("name")):
            errs.append(f"island probe model rejected: {model_err}")
        try:
            attested = sess.island_for_model(
                model["deviceTypeIdentifier"])
        except sess.SessionError as exc:
            errs.append(f"island probe model unattested: {exc}")
        else:
            if attested is not False:
                errs.append("island probe model reports an island; "
                            "N/A refused")
    udids = {r.get("device_udid") for r in records}
    if len(udids) != 1 or not isinstance(next(iter(udids)), str) \
            or next(iter(udids)) in ("", "unknown"):
        errs.append("frame records must agree on one known device UDID "
                    "for probe binding")
    elif not isinstance(model, dict) or model.get("udid") != next(iter(udids)):
        errs.append("island probe udid does not match the run's device "
                    "UDID (producer mismatch)")
    if probe.get("source") != "simctl-list":
        errs.append("island probe source must be simctl-list "
                    "(actual device query, not a flag)")
    realtime_nonces = {n for n, r in receipts.items()
                       if isinstance(r, dict)
                       and r.get("session_domain") == "realtime"}
    if probe.get("session_nonce") not in realtime_nonces:
        errs.append("island probe session_nonce joins no realtime receipt "
                    "of this run")


def _is_na_frame(run_dir: Path, frame: str, probe: dict | None) -> bool:
    """True when an island frame is legitimately N/A (probe, no pixels)."""
    if frame not in ("la-compact", "la-expanded"):
        return False
    if probe is None:
        return False
    png = run_dir / "frames" / f"{frame}.png"
    rec = run_dir / "frames" / f"{frame}.json"
    # N/A frames must have NO png filed; a filed PNG is fabrication.
    return not png.exists() and not rec.exists()


def _check_frame_record(run_dir: Path, frame: str, rec: Any,
                        errs: list[str]) -> None:
    if not isinstance(rec, dict):
        errs.append(f"frame record for {frame!r} must be an object")
        return
    if rec.get("frame") != frame:
        errs.append(f"frame record mismatch: wanted {frame!r}, "
                    f"got {rec.get('frame')!r}")
    path = run_dir / "frames" / f"{frame}.json"
    if path.is_symlink():
        errs.append(f"frame record {frame} is a symlink; refusing escape")
    elif not path.is_file():
        # la-compact/la-expanded may be N/A (handled by caller); every
        # other frame requires its record file.
        if frame not in ("la-compact", "la-expanded"):
            errs.append(f"frame record file missing for {frame!r}")
    for key in ("screenshot_path", "png", "png_src"):
        if key in rec and not _no_traversal(rec[key]):
            errs.append(f"frame {frame!r} carries escaping path in {key!r}")
    nonce = rec.get("session_nonce")
    if nonce is not None and (
            not isinstance(nonce, str) or not nonce or ".." in nonce
            or "/" in nonce):
        errs.append(f"frame {frame!r} carries an unsafe session_nonce")
    # On-disk record file must agree with the manifest claim EXACTLY
    # (normalized dict equality over every key): any manifest-only
    # invention — capture flip, invented window/observation, dropped
    # pending_reason, re-keying — fails closed even when all binding
    # hashes still match. Disk is the evidence; the manifest only repeats
    # it.
    if path.is_file() and not path.is_symlink():
        obj, err = _load_json(path)
        if err is not None:
            errs.append(err)
        elif isinstance(obj, dict):
            if obj != rec:
                only_manifest = sorted(set(rec) - set(obj))
                only_disk = sorted(set(obj) - set(rec))
                differing = sorted(k for k in set(rec) & set(obj)
                                   if rec[k] != obj[k])
                errs.append(
                    f"frame {frame!r}: manifest disagrees with on-disk "
                    f"record (manifest-only {only_manifest}; "
                    f"disk-only {only_disk}; differing {differing})")
            for key in ("screenshot_path", "png", "png_src"):
                if key in obj and not _no_traversal(obj[key]):
                    errs.append(f"frame {frame!r} on-disk record carries "
                                f"escaping path in {key!r}")


def _check_frame_png(run_dir: Path, frame: str, rec: dict,
                     errs: list[str]) -> None:
    png = run_dir / "frames" / f"{frame}.png"
    if png.is_symlink():
        errs.append(f"screenshot for {frame!r} is a symlink; refusing escape")
        return
    if not png.is_file():
        errs.append(f"screenshot file missing for {frame!r}")
        return
    try:
        dims = insp.png_dimensions(str(png))
    except insp.InspectionError as exc:
        errs.append(f"screenshot for {frame!r} unreadable: {exc}")
        return
    claimed = rec.get("geometry") or {}
    if (dims[0], dims[1]) != (claimed.get("width"), claimed.get("height")):
        errs.append(f"screenshot geometry {dims} != record for {frame!r}")
        return
    actual = insp.sha256_file(str(png))
    if actual != rec.get("screenshot_sha256"):
        errs.append(f"screenshot for {frame!r} changed after capture "
                    "(tampered or stale observation binding)")


def _check_genuine_binding(frame: str, rec: dict, errs: list[str]) -> None:
    capture = rec.get("capture")
    if capture == "external-lock-screen-pending":
        if not rec.get("pending_reason"):
            errs.append(f"{frame}: pending stub carries no reason "
                        "(handoff never silent)")
        return
    if capture == "external-lock-screen":
        cw = rec.get("capture_window")
        if not isinstance(cw, dict) or "captured_at_iso" not in cw \
                or "observed_elapsed_s" not in cw:
            errs.append(f"{frame}: genuine claim without capture_window "
                        "binding")
            return
        if not rec.get("observation_sha256"):
            errs.append(f"{frame}: genuine claim without observation_sha256")
            return
        # Genuine observations are numerically re-validated here (wall
        # elapsed vs observed within ±2s), not merely checked for
        # presence: a self-consistent-looking invented window with a
        # mismatched duration still fails.
        try:
            wall = (insp.parse_aware_iso(cw["captured_at_iso"])
                    - insp.parse_aware_iso(cw["started_at"])).total_seconds()
        except (insp.InspectionError, KeyError, TypeError) as exc:
            errs.append(f"{frame}: capture window malformed: {exc}")
            return
        observed = cw.get("observed_elapsed_s")
        if not insp.is_strict_nonneg_number(observed) or abs(
                wall - float(observed)) > insp.LA_TOLERANCE_S:
            errs.append(
                f"{frame}: capture window observation {observed!r}s vs wall "
                f"{wall:.1f}s exceeds tolerance (hash-bound evidence "
                "required)")
        return
    # Native captures need no observation binding here; the numeric LA
    # tolerance for app-supplied observations stays in inspection.py.


def _check_session_binding(run_dir: Path, frame: str, rec: dict,
                           receipts: dict[str, dict],
                           errs: list[str]) -> None:
    nonce = rec.get("session_nonce")
    domain = rec.get("session_domain")
    seq = rec.get("seq")
    sha = rec.get("request_sha256")
    if not isinstance(nonce, str) or not nonce:
        errs.append(f"frame {frame!r} missing session_nonce "
                    "(not a session capture?)")
        return
    if domain not in ("pinned", "realtime"):
        errs.append(f"frame {frame!r} carries unknown session_domain")
        return
    if isinstance(seq, bool) or not isinstance(seq, int) or seq < 0:
        errs.append(f"frame {frame!r} carries an invalid seq")
        return
    if not _is_hex64(sha):
        errs.append(f"frame {frame!r} carries an invalid request_sha256")
        return
    receipt = receipts.get(nonce)
    if receipt is None:
        errs.append(f"frame {frame!r}: no session receipt for nonce "
                    f"{nonce[:8]}…")
        return
    if receipt.get("run_id") != rec.get("run_id"):
        errs.append(f"frame {frame!r}: receipt run_id "
                    f"{receipt.get('run_id')!r} != record "
                    f"{rec.get('run_id')!r}")
        return
    if receipt.get("session_domain") != domain:
        errs.append(f"frame {frame!r}: receipt domain "
                    f"{receipt.get('session_domain')!r} != record "
                    f"{domain!r}")
        return
    if receipt.get("status") != "complete":
        errs.append(f"frame {frame!r}: session receipt "
                    f"{receipt.get('status')!r} (partial cleanup contaminates; "
                    "frame cannot finalize as complete)")
        return
    transcript = receipt.get("transcript")
    if not isinstance(transcript, list) or not transcript:
        errs.append(f"frame {frame!r}: receipt carries no transcript")
        return
    covered = any(isinstance(row, dict) and row.get("seq") == seq
                  and row.get("frame") == frame
                  and row.get("request_sha256") == sha
                  for row in transcript)
    if not covered:
        errs.append(f"frame {frame!r} seq {seq} not covered by the session "
                    "transcript")
        return
    app = receipt.get("app_cleanup")
    if not isinstance(app, dict) or app.get("status") != "cleaned" \
            or app.get("removed_session") is not True:
        errs.append(f"frame {frame!r}: app cleanup unverified "
                    "(session store/activity removal unproven)")
        return
    if app.get("removed_session_queue") is not True:
        errs.append(f"frame {frame!r}: app cleanup does not prove "
                    "owned-queue removal (removed_session_queue != true; "
                    "fixed receipts stay fixed)")
    host = receipt.get("runner_verified")
    if not isinstance(host, dict) or not host.get("chrome_restored") \
            or not host.get("process_terminated") \
            or not host.get("lease_released"):
        errs.append(f"frame {frame!r}: runner host receipt incomplete "
                    "(chrome/process/lease restoration unproven)")
