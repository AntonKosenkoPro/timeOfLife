#!/usr/bin/env python3
"""Human-inspection gates: no fabricated observations, fail until supplied.

Two rules with teeth:
1. Live-Activity timer: the runner NEVER derives the observed timer from
   elapsed arithmetic or OCR. A human (or a future documented OCR step)
   supplies an observation record ``{"observed_elapsed_s",
   "screenshot_sha256"}`` read from the actual render; the sha MUST equal
   the actual PNG hash or the observation is bound to a different render.
   verify_la() checks |capture_at - started_at - observed| <= 2s.
   Timestamps must be timezone-aware ISO (naive input is refused, never
   silently assumed UTC). Numerics must be finite, non-negative, and never
   bool/NaN/inf.
2. Picker keyboard: intent flags (software_visible:true) are not proof.
   verify_picker() requires the actual capture file (hash-bound),
   an observed language equal to the request's keyboard language,
   keyboard_visible=true from inspection, docked presentation, and a
   non-empty evidence artifact (hashed into the returned evidence record).

Refuse final status until the artifact fields are provided.
"""

from __future__ import annotations

import hashlib
import math
from datetime import datetime
from pathlib import Path
from typing import Any

LA_TOLERANCE_S = 2.0


class InspectionError(ValueError):
    pass


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 64), b""):
            h.update(chunk)
    return h.hexdigest()


def is_strict_nonneg_number(v: Any) -> bool:
    """Finite non-negative int/float; bool/NaN/inf/str rejected."""
    return (
        isinstance(v, (int, float))
        and not isinstance(v, bool)
        and math.isfinite(v)
        and v >= 0
    )


def png_dimensions(path: str) -> tuple[int, int]:
    """Stdlib PNG IHDR parse (no PIL). Raises InspectionError on mismatch."""
    with open(path, "rb") as fh:
        sig = fh.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise InspectionError(f"{path} is not a PNG file")
        fh.read(4)
        ctype = fh.read(4)
        if ctype != b"IHDR":
            raise InspectionError(f"{path}: first chunk is not IHDR")
        data = fh.read(13)
        if len(data) != 13:
            raise InspectionError(f"{path}: truncated IHDR")
        width = int.from_bytes(data[0:4], "big")
        height = int.from_bytes(data[4:8], "big")
        return width, height


def parse_aware_iso(value: Any) -> datetime:
    """Parse ISO-8601; naive (tz-unaware) input is refused, never assumed UTC."""
    if not isinstance(value, str) or not value:
        raise InspectionError(f"timestamp must be a non-empty string, got {value!r}")
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise InspectionError(f"invalid ISO timestamp {value!r}")
    if dt.tzinfo is None:
        raise InspectionError(
            f"naive timestamp {value!r} refused: supply a timezone-aware ISO value"
        )
    return dt


def verify_la_observation(
    state_live_activity: dict,
    screenshot_path: str,
    screenshot_captured_at_iso: str,
    observation: dict | None,
) -> list[str]:
    """Validate a human-supplied LA timer reading. Empty list = pass.

    ``observation`` must be ``{"observed_elapsed_s": <strict number>,
    "screenshot_sha256": <actual PNG hash>}``. Missing observation keeps
    the frame in needs-inspection (pending), never a silent pass.
    """
    if not isinstance(observation, dict):
        return ["live-activity observation is missing: frame stays needs-inspection"]
    observed = observation.get("observed_elapsed_s")
    if not is_strict_nonneg_number(observed):
        return [
            "observed_elapsed_s must be a finite non-negative number "
            "(bool/NaN/inf rejected) read from the actual render"
        ]
    if not Path(screenshot_path).is_file():
        return [f"screenshot file not found: {screenshot_path}"]
    actual_sha = sha256_file(screenshot_path)
    claimed_sha = observation.get("screenshot_sha256")
    if not claimed_sha:
        return ["observation.screenshot_sha256 is required: no binding by default"]
    if claimed_sha != actual_sha:
        return ["screenshot hash mismatch: observation is bound to a different render"]
    if not isinstance(state_live_activity, dict):
        return ["state live_activity block is required before validation"]
    started = state_live_activity.get("started_at")
    if not started:
        return ["state live_activity.started_at (real anchor) is required"]
    try:
        capture_dt = parse_aware_iso(screenshot_captured_at_iso)
        start_dt = parse_aware_iso(started)
    except InspectionError as exc:
        return [str(exc)]
    wall_elapsed = (capture_dt - start_dt).total_seconds()
    if wall_elapsed < -1:
        return ["capture timestamp predates the real start anchor"]
    if abs(wall_elapsed - float(observed)) > LA_TOLERANCE_S:
        return [
            f"observed {observed}s vs wall {wall_elapsed:.1f}s "
            f"exceeds ±{LA_TOLERANCE_S:.0f}s tolerance"
        ]
    return []


def verify_picker_inspection(
    inspection: dict,
    *,
    screenshot_path: str,
    expected_language: str,
) -> tuple[list[str], dict]:
    """Picker keyboard proof. Returns (errs, evidence).

    ``evidence`` carries screenshot_sha256 + artifact_sha256 on success
    for manifest binding; ``{}`` when validation fails. keyboard_visible
    alone never counts as screen proof.
    """
    errs: list[str] = []
    if not isinstance(inspection, dict):
        return ["picker inspection record is required"], {}
    if not isinstance(expected_language, str) or not expected_language:
        return ["expected keyboard language must be a non-empty string"], {}
    if not Path(screenshot_path).is_file():
        return [f"screenshot file not found: {screenshot_path}"], {}
    actual_sha = sha256_file(screenshot_path)
    if inspection.get("screenshot_sha256") != actual_sha:
        errs.append(
            "inspection screenshot_sha256 must equal the actual capture file hash"
        )
    if inspection.get("keyboard_visible") is not True:
        errs.append("picker keyboard_visible must be true from actual screen inspection")
    observed_lang = inspection.get("keyboard_language_observed")
    if not isinstance(observed_lang, str) or not observed_lang:
        errs.append("keyboard_language_observed must be a non-empty string")
    elif observed_lang != expected_language:
        errs.append(
            f"observed keyboard language {observed_lang!r} != "
            f"requested {expected_language!r}"
        )
    if inspection.get("presentation_observed") != "docked":
        errs.append("presentation_observed must be 'docked' from the actual screen")
    artifact = inspection.get("evidence_artifact")
    artifact_sha: str | None = None
    if not artifact or not isinstance(artifact, str):
        errs.append("evidence_artifact path is required; refusing final status until provided")
    elif not Path(artifact).is_file():
        errs.append(f"evidence_artifact not found: {artifact}")
    elif Path(artifact).stat().st_size == 0:
        errs.append(f"evidence_artifact is empty: {artifact}")
    else:
        artifact_sha = sha256_file(artifact)
    if errs:
        return errs, {}
    return [], {"screenshot_sha256": actual_sha, "artifact_sha256": artifact_sha}
