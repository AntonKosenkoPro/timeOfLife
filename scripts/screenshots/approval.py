#!/usr/bin/env python3
"""Pilot approval gate (task 4.5): hash-bound, file-verified, never inferred.

An approval is valid ONLY when: decision == 'approved', the retained
directory resolves outside the repo (symlink escapes rejected via the
shared output guard), approval.retained_location resolves to that same
directory, the retained pilot_manifest.json parses and its deck/treatment/
frames content matches the approval (not just independent known hashes),
the manifest hash matches the file bytes, and all seven source frame
hashes match files that EXIST under the retained location. Passing unit
tests, a green build, or invoking apply never counts as approval.

The CLI in capture.py only VALIDATES approvals; nothing here writes
decision:'approved' automatically.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import output_guard as guard
from request_schema import PILOT_DECK_VERSION, PILOT_FRAMES, PILOT_TREATMENT


class ApprovalError(ValueError):
    pass


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _manifest_content_errors(manifest: Any, approval: dict) -> list[str]:
    errs: list[str] = []
    if not isinstance(manifest, dict):
        return ["retained pilot_manifest.json must contain a JSON object"]
    if manifest.get("deck_version") != approval.get("deck_version"):
        errs.append("retained manifest deck_version differs from approval deck_version")
    if manifest.get("treatment") != approval.get("treatment"):
        errs.append("retained manifest treatment differs from approval treatment")
    if manifest.get("frames") != list(PILOT_FRAMES):
        errs.append("retained manifest frames differ from the approved 7-frame story")
    return errs


def verify_approval(
    approval: dict,
    retained_dir: str,
    expect_deck: str = PILOT_DECK_VERSION,
    expect_treatment: str = PILOT_TREATMENT,
) -> list[str]:
    errs: list[str] = []
    if not isinstance(approval, dict):
        return ["approval must be a JSON object"]
    if approval.get("decision") != "approved":
        return ["approval decision is not 'approved'; expansion stays blocked"]
    try:
        retained = guard.resolve_out_root(retained_dir or "")
    except guard.GuardError as exc:
        return [f"retained directory rejected: {exc}"]
    if not retained.is_dir():
        return [f"retained directory not found: {retained}"]
    claimed_location = approval.get("retained_location")
    if not claimed_location or not isinstance(claimed_location, str):
        return ["approval.retained_location is required"]
    try:
        claimed = guard.resolve_out_root(claimed_location)
    except guard.GuardError as exc:
        return [f"approval retained_location rejected: {exc}"]
    if claimed != retained:
        return [
            f"approval retained_location {claimed} != verified directory {retained}"
        ]
    if approval.get("deck_version") != expect_deck:
        errs.append(f"approval deck_version must be {expect_deck!r}")
    if approval.get("treatment") != expect_treatment:
        errs.append(f"approval treatment must be {expect_treatment!r}")
    manifest_path = retained / "pilot_manifest.json"
    manifest_hash = approval.get("pilot_manifest_sha256")
    if not manifest_hash:
        errs.append("pilot_manifest_sha256 is required")
    elif not manifest_path.is_file():
        errs.append(f"retained pilot_manifest.json not found in {retained}")
    else:
        actual = sha256_bytes(manifest_path.read_bytes())
        if actual != manifest_hash:
            errs.append("pilot manifest hash mismatch: recapture invalidates approval")
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errs.append(f"retained pilot_manifest.json malformed: {exc}")
        else:
            errs.extend(_manifest_content_errors(manifest, approval))
    frame_hashes = approval.get("frame_hashes")
    if not isinstance(frame_hashes, dict):
        errs.append("frame_hashes must be an object keyed by frame id")
        return errs
    for frame in PILOT_FRAMES:
        want = frame_hashes.get(frame)
        if not want:
            errs.append(f"frame_hashes missing {frame!r}")
            continue
        fp = retained / "frames" / f"{frame}.png"
        if not fp.is_file():
            errs.append(f"retained frame file missing: {fp}")
            continue
        actual = sha256_bytes(fp.read_bytes())
        if actual != want:
            errs.append(f"retained frame {frame!r} hash mismatch: needs re-approval")
    return errs


def gate_kind(kind: str, approval_path: str | None, retained_dir: str | None) -> list[str]:
    """Pilot captures proceed; iPad/non-English/montage require approval."""
    if kind == "pilot":
        return []
    if kind not in ("ipad", "non-english", "montage"):
        return [f"unknown gate kind {kind!r}"]
    if not approval_path or not retained_dir:
        return [
            f"{kind} requires --approval <approval.json> + --retained-dir; "
            "5.4 owner approval is the only key"
        ]
    try:
        approval = json.loads(Path(approval_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"cannot read approval file: {exc}"]
    return verify_approval(approval, retained_dir)


def gates_for_request(
    locale: str | None,
    geometry: tuple[int, int] | None,
    approval_path: str | None,
    retained_dir: str | None,
) -> list[str]:
    """Approval gates for one capture request.

    - Non-English locale -> 'non-english' gate (5.4 approval required).
    - Non-pilot geometry -> 'ipad' device-matrix gate (covers 6.5-inch
      iPhone + 13-inch iPad; pilot 1320x2868 proceeds without approval).
    Both gates may apply at once; every applicable gate must pass.
    Schema validation stays separate: passing validation never implies
    approval, and this gate never validates request shape.
    """
    from request_schema import PILOT_GEOMETRY

    errs: list[str] = []
    if isinstance(locale, str) and locale != "en":
        errs.extend(gate_kind("non-english", approval_path, retained_dir))
    if geometry is not None and tuple(geometry) != tuple(PILOT_GEOMETRY):
        errs.extend(gate_kind("ipad", approval_path, retained_dir))
    return errs


def load_json_object(path: str) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))
