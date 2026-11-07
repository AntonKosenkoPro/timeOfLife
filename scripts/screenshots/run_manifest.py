#!/usr/bin/env python3
"""Run-manifest assembly (text only, single pass).

Each manifest carries exact request-hash binding plus the semantic
request-hash projection (volatile run identity excluded) so a HUMAN
can compare a manual rerun frame-by-frame. There is no automatic
pass comparison: pixel variance is reviewable, never auto-approved
(single-pass decision 2026-11-04 — the retired `compare_runs` gate
was removed, not relaxed).
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
        # Provenance, never content (no automatic consumer compares it).
        "ci_approval_bypass": bool(ci_approval_bypass),
    }
    if na:
        # Explicit N/A (scoped availability with probe evidence) — present
        # only on N/A runs so v1 manifests keep their exact legacy shape.
        manifest["na_frames"] = na
        manifest["island_probe"] = island_probe
    return manifest
