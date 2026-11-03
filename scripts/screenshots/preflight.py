#!/usr/bin/env python3
"""Preflight command planning (argv lists only; no device I/O here).

Supported commands are limited to what installed ``simctl help`` confirms
(read 2026-10-30, re-verified 2026-11-02, no ctx7, no device touched):
- ``status_bar <device> [list|clear|override ...]`` with --time,
  --dataNetwork, --wifiMode, --wifiBars, --cellularMode, --cellularBars,
  --batteryState, --batteryLevel.
- ``io <device> screenshot [--type png]`` native-resolution PNG export
  (plus ``--mask=black`` for the island frames only, see below).
- ``ui <device> appearance|content_size`` with no-arg query form.
- ``get_app_container <device> <bid> data`` for the Documents drop.
- ``launch --terminate-running-process <device> <bid> [argv...]``.

Screenshot mask policy (probe-proven on this toolchain): the Dynamic
Island compact/expanded presentations need ``--mask=black`` so the
island cutout renders its true pixels; every other frame uses the
simctl default (no ``--mask`` flag). ``screenshot_argv`` is the only
place a mask flag is ever emitted, and only ``black`` is allowed.

Deliberately NOT emitted: any global locale/timezone/keyboard preference
commands (no confirmed simctl surface). Locale/timezone/keyboard travel
app-side inside capture-request.json; picker keyboard visibility is proven
by human inspection evidence (see inspection.py), never by intent flags.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from request_schema import PILOT_GEOMETRY, SCREENSHOT_BID

REQUEST_FILENAME = "capture-request.json"
STATE_FILENAME = "capture-state.json"
CLEANUP_FILENAME = "capture-cleanup.json"
LAUNCH_ARGV = ["SCREENSHOT_REQUEST", REQUEST_FILENAME]

# status_bar override pinned to pilot chrome (flag names from help text,
# re-verified 2026-11-02 via `xcrun simctl help status_bar`: --cellularMode
# active + --cellularBars 0-4, --batteryState charging|charged|discharging).
# discharging + full cellular/wifi renders the required 9:41 + full cellular
# + full wifi + 100% non-charging battery (charged showed a charging bolt,
# missing cellular flags left empty dots — 9.3 matrix held until fixed).
STATUS_BAR_OVERRIDE_ARGV = [
    "xcrun",
    "simctl",
    "status_bar",
    "{udid}",
    "override",
    "--time",
    "9:41",
    "--batteryState",
    "discharging",
    "--batteryLevel",
    "100",
    "--wifiMode",
    "active",
    "--wifiBars",
    "3",
    "--cellularMode",
    "active",
    "--cellularBars",
    "4",
    "--dataNetwork",
    "wifi",
]


def _fill(argv: list[str], udid: str) -> list[str]:
    return [a.format(udid=udid) for a in argv]


def snapshot_commands(udid: str) -> list[list[str]]:
    """Read-only queries; safe to run, never mutate."""
    return [
        ["xcrun", "simctl", "status_bar", udid, "list"],
        ["xcrun", "simctl", "ui", udid, "appearance"],
        ["xcrun", "simctl", "ui", udid, "content_size"],
    ]


def apply_commands(udid: str) -> list[list[str]]:
    """Mutating commands for the pilot session (lease-gated at execution)."""
    return [
        ["xcrun", "simctl", "ui", udid, "appearance", "light"],
        ["xcrun", "simctl", "ui", udid, "content_size", "large"],
        _fill(STATUS_BAR_OVERRIDE_ARGV, udid),
    ]


def restore_commands(
    udid: str,
    prior_appearance: str,
    prior_content_size: str,
    session_applied_status_bar_override: bool,
    prior_status_bar_list_was_empty: bool,
) -> list[list[str]]:
    """Restore exactly what was snapshotted.

    status_bar `clear` is emitted ONLY when this session applied the
    override AND the prior list was empty. Preexisting overrides must
    abort the run upfront (see plan_run); they are never blanket-cleared.
    """
    cmds = [
        ["xcrun", "simctl", "ui", udid, "appearance", prior_appearance],
        ["xcrun", "simctl", "ui", udid, "content_size", prior_content_size],
    ]
    if session_applied_status_bar_override and prior_status_bar_list_was_empty:
        cmds.append(["xcrun", "simctl", "status_bar", udid, "clear"])
    return cmds


def container_documents_path(container_data_path: str) -> str:
    return str(Path(container_data_path) / "Documents" / REQUEST_FILENAME)


def launch_argv(udid: str, bid: str = SCREENSHOT_BID) -> list[str]:
    # Fresh session per frame: terminate any running copy first.
    return [
        "xcrun",
        "simctl",
        "launch",
        "--terminate-running-process",
        udid,
        bid,
    ] + LAUNCH_ARGV


def cleanup_launch_argv(udid: str, bid: str, run_id: str, sha: str) -> list[str]:
    """Exact app-hook tokens (ScreenshotRequest screenshotToken grammar).

    `KEY=value` argv form; the app verifies both against the last
    capture-state.json before touching anything.
    """
    return [
        "xcrun",
        "simctl",
        "launch",
        "--terminate-running-process",
        udid,
        bid,
        f"SCREENSHOT_CLEANUP={run_id}",
        f"SCREENSHOT_CLEANUP_SHA={sha}",
    ]


def screenshot_argv(
    udid: str, dest_png: str, mask: str | None = None
) -> list[str]:
    """Native screenshot export; mask is None (simctl default) or 'black'.

    Only 'black' is emitted, and only for the island frames resolved by
    mask_for_frame(). Anything else fails closed: the mask policy is
    probe-proven, never guessed per invocation.
    """
    if mask is None:
        return ["xcrun", "simctl", "io", udid, "screenshot", "--type=png", dest_png]
    if mask != "black":
        raise ValueError(
            f"unsupported screenshot mask {mask!r}; only 'black' is probe-proven"
        )
    return [
        "xcrun", "simctl", "io", udid, "screenshot",
        "--type=png", "--mask=black", dest_png,
    ]


def mask_for_frame(frame: str) -> str | None:
    """Probe-proven mask per frame: 'black' for island frames, else None."""
    return "black" if frame in ("la-compact", "la-expanded") else None


def resolve_screenshot_mask(frame: str, mask: str | None = None) -> str | None:
    """Resolve an explicit mask override ('black'/'default'/None) per frame.

    None means the per-frame default from mask_for_frame(); 'default'
    forces the simctl default even for island frames. Anything else
    fails closed.
    """
    if mask is None:
        return mask_for_frame(frame)
    if mask == "default":
        return None
    if mask == "black":
        return "black"
    raise ValueError(
        f"unsupported screenshot mask {mask!r}; want 'black', 'default', or omit"
    )


def plan_run(
    base_request: dict,
    frames: list[str],
    udid: str,
    out_root: str,
    run_id: str,
    geometry: tuple[int, int] = PILOT_GEOMETRY,
) -> dict[str, Any]:
    """Pure plan for one full pilot run (7 frames); touches no device."""
    from request_schema import MATRIX_GEOMETRIES, PILOT_FRAMES, build_frame_request

    if list(frames) != list(PILOT_FRAMES):
        raise ValueError(
            f"pilot accepts exactly {list(PILOT_FRAMES)!r} in order; got {frames!r}"
        )
    if tuple(geometry) not in MATRIX_GEOMETRIES:
        raise ValueError(
            f"unsupported geometry {geometry}; supported: {sorted(MATRIX_GEOMETRIES)}"
        )
    if not udid or udid == "booted":
        raise ValueError("explicit simulator UDID is required (no auto-pick)")
    run_dir = str(Path(out_root) / "runs" / run_id)
    steps = []
    for frame in frames:
        mask = mask_for_frame(frame)
        steps.append(
            {
                "frame": frame,
                "request_file": f"{run_dir}/requests/{frame}.{REQUEST_FILENAME}",
                "container_dest": f"<container-data>/Documents/{REQUEST_FILENAME}",
                "launch_argv": launch_argv(udid),
                "state_file": f"<container-data>/Documents/{STATE_FILENAME}",
                "screenshot_argv": screenshot_argv(
                    udid, f"{run_dir}/frames/{frame}.png", mask,
                ),
                "screenshot_mask": mask or "default",
                "frame_request": build_frame_request(base_request, frame),
            }
        )
    from approval import ci_bypass_active

    return {
        "run_id": run_id,
        "device_udid": udid,
        "out_root": out_root,
        "run_dir": run_dir,
        "ci_approval_bypass": ci_bypass_active(),
        "geometry": {"width": geometry[0], "height": geometry[1]},
        "snapshot_commands": snapshot_commands(udid),
        "apply_commands": apply_commands(udid),
        "preexisting_override_policy": (
            "abort when `status_bar list` is non-empty; "
            "never blanket-clear foreign overrides"
        ),
        "steps": steps,
    }
