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

from approval import ci_bypass_active


class ManifestError(ValueError):
    pass


def assemble_run_manifest(
    run_id: str,
    device_udid: str,
    deck_version: str,
    treatment: str,
    geometry: tuple[int, int],
    frame_records: list[dict],
    ci_approval_bypass: bool | None = None,
    na_frames: list[str] | None = None,
    island_probe: dict | None = None,
) -> dict[str, Any]:
    frames = [r.get("frame") for r in frame_records]
    na = sorted(na_frames) if na_frames else []
    if any(f not in ("la-compact", "la-expanded") for f in na):
        raise ManifestError(
            f"only island frames can be not-applicable, got {na!r}")
    want = [f for f in PILOT_FRAMES if f not in na]
    if frames != want:
        raise ManifestError(
            f"run manifest requires frames {want!r} in order "
            f"(N/A: {na!r})")
    if na and not isinstance(island_probe, dict):
        raise ManifestError(
            "N/A island frames require the attested island probe")
    if ci_approval_bypass is None:
        ci_approval_bypass = ci_bypass_active()
    manifest: dict[str, Any] = {
        "schema_version": 1,
        "run_id": run_id,
        "device_udid": device_udid,
        "deck_version": deck_version,
        "treatment": treatment,
        "geometry": {"width": geometry[0], "height": geometry[1]},
        "frames": frame_records,
        "status": "needs-inspection",
        # CI audit trail: true when this run's expansion gates were
        # satisfied by LIFIO_CAPTURE_CI=1 instead of a 5.4 approval file.
        # Provenance, never content: compare_runs ignores it.
        "ci_approval_bypass": bool(ci_approval_bypass),
    }
    if na:
        # Explicit N/A (scoped availability with probe evidence) — present
        # only on N/A runs so v1 manifests keep their exact legacy shape.
        manifest["na_frames"] = na
        manifest["island_probe"] = island_probe
    return manifest


def compare_runs(first: dict, second: dict) -> dict[str, list[str]]:
    """Return {"errors": [...], "unreviewed_variance": [frames...]}."""
    errors: list[str] = []
    variance: list[str] = []
    for key in ("deck_version", "treatment", "geometry"):
        if first.get(key) != second.get(key):
            errors.append(
                f"run mismatch on {key}: {first.get(key)!r} vs {second.get(key)!r}"
            )
    na_first = sorted(first.get("na_frames", []))
    na_second = sorted(second.get("na_frames", []))
    if na_first != na_second:
        errors.append(
            f"run mismatch on na_frames: {na_first!r} vs {na_second!r} "
            "(both passes must declare the same N/A scope explicitly)")
    probe_err = _compare_probes(first.get("island_probe"),
                                second.get("island_probe"))
    if probe_err:
        errors.append(probe_err)
    fa = {f["frame"]: f for f in first.get("frames", [])}
    fb = {f["frame"]: f for f in second.get("frames", [])}
    for frame in PILOT_FRAMES:
        if frame in na_first:
            continue  # explicitly N/A in both passes (checked above)
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


def _compare_probes(first: Any, second: Any) -> str | None:
    """Cross-pass island-probe consistency (both passes explicit).

    Volatile per-pass fields (run_id, session_nonce) are excluded; every
    attestation field must agree. A probe on exactly one side is a scope
    mismatch, never silently ignored.
    """
    if first is None and second is None:
        return None
    if (first is None) != (second is None):
        return ("run mismatch: island probe present on exactly one pass "
                "(both passes must declare N/A explicitly)")
    if not isinstance(first, dict) or not isinstance(second, dict):
        return "run mismatch: island probe must be an object on both passes"
    for key in ("device_key", "island_available", "geometry", "source",
                "reason"):
        if first.get(key) != second.get(key):
            return (f"run mismatch on island_probe.{key}: "
                    f"{first.get(key)!r} vs {second.get(key)!r}")
    ma = first.get("model") if isinstance(first.get("model"), dict) else {}
    mb = second.get("model") if isinstance(second.get("model"), dict) else {}
    if ma.get("deviceTypeIdentifier") != mb.get("deviceTypeIdentifier"):
        return ("run mismatch on island_probe.model.deviceTypeIdentifier: "
                f"{ma.get('deviceTypeIdentifier')!r} vs "
                f"{mb.get('deviceTypeIdentifier')!r}")
    return None
