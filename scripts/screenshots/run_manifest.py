#!/usr/bin/env python3
"""Run-manifest assembly + two-run semantic comparison (text only).

Comparison is semantic, never byte-equality of PNGs: two runs must agree
on deck/treatment/geometry, per-frame semantic request hashes (run_id is
volatile and excluded), and expected totals. Differing screenshot bytes
(caret blink, system chrome) are reported as `unreviewed_variance` for
explicit human review — pixel variance is never auto-adjudicated as
stable without actual evidence.
"""

from __future__ import annotations

from typing import Any

from request_schema import PILOT_FRAMES


class ManifestError(ValueError):
    pass


def assemble_run_manifest(
    run_id: str,
    device_udid: str,
    deck_version: str,
    treatment: str,
    geometry: tuple[int, int],
    frame_records: list[dict],
) -> dict[str, Any]:
    frames = [r.get("frame") for r in frame_records]
    if frames != list(PILOT_FRAMES):
        raise ManifestError(f"run manifest requires frames {list(PILOT_FRAMES)!r} in order")
    return {
        "schema_version": 1,
        "run_id": run_id,
        "device_udid": device_udid,
        "deck_version": deck_version,
        "treatment": treatment,
        "geometry": {"width": geometry[0], "height": geometry[1]},
        "frames": frame_records,
        "status": "needs-inspection",
    }


def compare_runs(first: dict, second: dict) -> dict[str, list[str]]:
    """Return {"errors": [...], "unreviewed_variance": [frames...]}."""
    errors: list[str] = []
    variance: list[str] = []
    for key in ("deck_version", "treatment", "geometry"):
        if first.get(key) != second.get(key):
            errors.append(
                f"run mismatch on {key}: {first.get(key)!r} vs {second.get(key)!r}"
            )
    fa = {f["frame"]: f for f in first.get("frames", [])}
    fb = {f["frame"]: f for f in second.get("frames", [])}
    for frame in PILOT_FRAMES:
        a, b = fa.get(frame), fb.get(frame)
        if not a or not b:
            errors.append(f"frame {frame!r} missing from one run")
            continue
        if a.get("request_semantic_sha256") != b.get("request_semantic_sha256"):
            errors.append(f"frame {frame!r} semantic request differs across runs")
        if a.get("expected_totals") != b.get("expected_totals"):
            errors.append(f"frame {frame!r} expected totals differ across runs")
        if a.get("screenshot_sha256") != b.get("screenshot_sha256"):
            variance.append(frame)
    return {"errors": errors, "unreviewed_variance": variance}
