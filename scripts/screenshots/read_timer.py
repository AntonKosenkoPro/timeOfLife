#!/usr/bin/env python3
"""Live Activity timer reader (macOS Vision OCR, stdlib + Swift bridge only).

Reads the system timer digits from an LA PNG's actual pixels via macOS
Vision text recognition and writes the hash-bound observation JSON
``{"observed_elapsed_s", "screenshot_sha256"}`` consumed by
``capture.py record-external-frame`` / ``verify-la``. This is the
documented OCR step anticipated by ``inspection.py``: the value still
comes from the render, never from elapsed arithmetic.

Per-frame regions of interest (normalized, top-left origin) exclude the
known chrome confounders measured on the retained pilot27-r2 renders
(validation only — those pre-2026-11-02 frames are SUPERSEDED drafts,
never approval sources):
- la-lock: bottom banner zone, y in [0.60, 1.00] (excludes the giant
  09:41 lock clock and the "Sat 1 Jan" date at the top).
- la-compact: island strip, y in [0.00, 0.08] with x-center >= 0.20
  (excludes the 09:41 status-bar clock at the left).
- la-expanded: card zone, y in [0.00, 0.10] (the expanded card covers
  the status bar, so timer-shaped text there is the system timer).

Fail-closed (exit 2 with a diagnostic, never a guess): non-LA frame,
missing/non-PNG input, naive ``--captured-at``, Vision unavailable or
erroring, no timer-shaped text in the ROI, or two different timer values
in the ROI.

``--captured-at`` is validated as a timezone-aware ISO timestamp (same
rule as ``inspection.parse_aware_iso``) for call-site symmetry with
``record-external-frame``; the reading itself comes purely from pixels.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import inspection as inspection_mod
import request_schema as req

EXIT_OK = 0
EXIT_FAIL = 2

SWIFT_TIMEOUT_S = 180

# Timer shapes the system renders: M:SS / MM:SS, or H:MM:SS past the hour.
# Vision sometimes emits "." or ";" for the colon, or pads with spaces, so
# those are accepted; anything else must fail loudly, never be coerced.
TIMER_RE = re.compile(
    r"(\d{1,3})\s*[:;.]\s*(\d{2})(?:\s*[:;.]\s*(\d{2}))?"
)

# ROI per LA frame: (x_center_min, x_center_max, y_center_min, y_center_max)
# in normalized top-left-origin coordinates. None means unconstrained.
ROI_FOR_FRAME: dict[str, tuple[float | None, float | None, float, float]] = {
    "la-lock": (None, None, 0.60, 1.00),
    "la-compact": (0.20, None, 0.00, 0.08),
    "la-expanded": (None, None, 0.00, 0.10),
}


class ReadTimerError(ValueError):
    """Fail-closed timer-reading error with a human-readable diagnostic."""


def parse_timer_text(text: str) -> int | None:
    """Parse system-timer text to elapsed seconds; None when not timer-shaped.

    Two groups are M:SS (minutes 0-59); three groups are H:MM:SS. Seconds
    (and MM) must be 00-59: out-of-range values are rejected rather than
    wrapped, so a misread can never silently become an observation.
    """
    if not isinstance(text, str):
        return None
    match = TIMER_RE.search(text)
    if not match:
        return None
    first, second, third = match.groups()
    if third is None:
        minutes, seconds = int(first), int(second)
        if minutes > 59 or seconds > 59:
            return None
        return minutes * 60 + seconds
    hours, minutes, seconds = int(first), int(second), int(third)
    if hours > 99 or minutes > 59 or seconds > 59:
        return None
    return hours * 3600 + minutes * 60 + seconds


def observation_in_roi(
    bbox: list | tuple,
    roi: tuple[float | None, float | None, float, float],
) -> bool:
    """True when the observation's bbox center falls inside the ROI."""
    try:
        x, y, w, h = (float(v) for v in bbox)
    except (TypeError, ValueError):
        return False
    x_min, x_max, y_min, y_max = roi
    cx, cy = x + w / 2.0, y + h / 2.0
    if x_min is not None and cx < x_min:
        return False
    if x_max is not None and cx > x_max:
        return False
    return y_min <= cy <= y_max


def select_timer_value(
    observations: list[dict], frame: str
) -> tuple[int, list[dict]]:
    """Pick the single system-timer value inside the frame's ROI.

    Returns (elapsed_s, roi_candidates). Raises ReadTimerError when the
    ROI holds no timer-shaped text (unreadable) or two different timer
    values (ambiguous): both fail loudly with the observed texts listed.
    """
    try:
        roi = ROI_FOR_FRAME[frame]
    except KeyError:
        raise ReadTimerError(
            f"unknown LA frame {frame!r}; want one of {sorted(ROI_FOR_FRAME)}"
        )
    if not isinstance(observations, list):
        raise ReadTimerError("OCR result must be a list of observations")
    roi_obs = [
        o for o in observations
        if isinstance(o, dict)
        and isinstance(o.get("text"), str)
        and observation_in_roi(o.get("bbox"), roi)
    ]
    parsed: list[tuple[int, dict]] = []
    for obs in roi_obs:
        value = parse_timer_text(obs["text"])
        if value is not None:
            parsed.append((value, obs))
    if not parsed:
        seen = [o.get("text") for o in roi_obs] or [
            o.get("text") for o in observations
            if isinstance(o, dict) and isinstance(o.get("text"), str)
        ]
        raise ReadTimerError(
            f"no timer-shaped text in the {frame} ROI "
            f"(saw {seen!r}); refusing to guess"
        )
    distinct = sorted({v for v, _ in parsed})
    if len(distinct) > 1:
        detail = [(v, o.get("text"), o.get("bbox")) for v, o in parsed]
        raise ReadTimerError(
            f"ambiguous timer values {distinct} in the {frame} ROI "
            f"({detail!r}); refusing to pick one"
        )
    return distinct[0], roi_obs


def run_ocr(png_path: str) -> list[dict]:
    """Run the Vision Swift bridge; return validated observation dicts."""
    swift = shutil.which("swift")
    if swift is None:
        raise ReadTimerError(
            "the `swift` driver was not found on PATH; "
            "read_timer requires macOS with Xcode installed"
        )
    bridge = HERE / "read_timer_vision.swift"
    if not bridge.is_file():
        raise ReadTimerError(f"Vision bridge missing: {bridge}")
    try:
        proc = subprocess.run(
            [swift, str(bridge), png_path],
            capture_output=True, text=True, timeout=SWIFT_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        raise ReadTimerError(
            f"Vision OCR timed out after {SWIFT_TIMEOUT_S}s for {png_path}"
        )
    except OSError as exc:
        raise ReadTimerError(f"cannot launch Vision OCR: {exc}")
    if proc.returncode != 0:
        raise ReadTimerError(
            f"Vision OCR failed for {png_path}: "
            f"{proc.stderr.strip()[:300] or f'exit {proc.returncode}'}"
        )
    try:
        observations = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise ReadTimerError(f"Vision OCR returned malformed JSON: {exc}")
    if not isinstance(observations, list) or any(
        not isinstance(o, dict)
        or not isinstance(o.get("text"), str)
        or not isinstance(o.get("bbox"), list)
        or len(o.get("bbox")) != 4
        for o in observations
    ):
        raise ReadTimerError("Vision OCR returned malformed observations")
    return observations


def read_timer(frame: str, png_path: str, captured_at_iso: str) -> dict:
    """OCR the system timer and return the hash-bound observation dict."""
    if frame not in req.LA_FRAMES or frame not in ROI_FOR_FRAME:
        raise ReadTimerError(
            f"frame must be one of {sorted(ROI_FOR_FRAME)}; got {frame!r}"
        )
    try:
        inspection_mod.parse_aware_iso(captured_at_iso)
    except inspection_mod.InspectionError as exc:
        raise ReadTimerError(str(exc))
    if not Path(png_path).is_file():
        raise ReadTimerError(f"screenshot file not found: {png_path}")
    try:
        inspection_mod.png_dimensions(png_path)
    except inspection_mod.InspectionError as exc:
        raise ReadTimerError(str(exc))
    observations = run_ocr(png_path)
    elapsed_s, roi_obs = select_timer_value(observations, frame)
    observation = {
        "observed_elapsed_s": elapsed_s,
        "screenshot_sha256": inspection_mod.sha256_file(png_path),
    }
    print(
        f"ocr: {len(observations)} text line(s), {len(roi_obs)} in {frame} "
        f"ROI -> {elapsed_s}s",
        file=sys.stderr,
    )
    return observation


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="read_timer.py",
        description="Read the Live Activity system timer from a PNG via "
                    "macOS Vision OCR and write the hash-bound observation JSON.",
    )
    ap.add_argument("--frame", required=True,
                    help="one of la-lock, la-compact, la-expanded")
    ap.add_argument("--png", required=True, help="genuine LA screenshot PNG")
    ap.add_argument("--captured-at", required=True,
                    help="timezone-aware ISO capture timestamp "
                         "(validated; the reading comes from pixels)")
    ap.add_argument("--out", required=True, help="observation JSON to write")
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        observation = read_timer(args.frame, args.png, args.captured_at)
    except ReadTimerError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        return EXIT_FAIL
    raw = (
        json.dumps(observation, sort_keys=True,
                   separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        + b"\n"
    )
    try:
        Path(args.out).write_bytes(raw)
    except OSError as exc:
        print(f"failed: cannot write {args.out}: {exc}", file=sys.stderr)
        return EXIT_FAIL
    print(raw.decode("utf-8"), end="")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
