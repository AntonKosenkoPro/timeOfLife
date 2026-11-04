#!/usr/bin/env python3
"""Early selection validation for the device-affine workflow (task 6.1).

Stdlib only. Validates configurable device/locale/runtime selections
before expensive macOS work. Values are compared against fixed catalogs
and never evaluated as executable source: injection-shaped inputs fail
closed as unknown/malformed.

Retained default catalog (matches `.github/workflows/app-screenshots.yml`
device catalog step + `request_schema.KNOWN_LOCALES` + panels `LOCALES`):
devices iphone69/iphone63/ipad13, five locales, runtime iOS 27.0
(baseline toolchain Xcode 27.1 per evidence/baseline.md; no new external
dependency, so no fresh ctx7 fetch was needed beyond evidence/research.md).
"""

from __future__ import annotations

import json
import re

SUPPORTED_DEVICES = ("iphone69", "iphone63", "ipad13")

DEVICE_CATALOG = {
    "iphone69": {"sim": "iPhone 17 Pro Max",
                 "geometry": "1320x2868", "island": 1},
    "iphone63": {"sim": "iPhone 17",
                 "geometry": "1206x2622", "island": 1},
    "ipad13": {"sim": "iPad Pro 13-inch (M5)",
               "geometry": "2064x2752", "island": 0},
}

SUPPORTED_LOCALES = ("en", "ru", "zh-Hans", "es-419", "pt-BR")

# Single automated pass per device-locale (owner decision 2026-11-04,
# §9): the ONLY pass constant in the workflow helpers. Artifact/status
# code and the device worker both read this (no duplicate tuple); a
# manual rerun re-invokes the same single-pass flow with a fresh run
# identity, never a second automatic pass.
PASSES = ("r1",)

DEFAULT_DEVICES = list(SUPPORTED_DEVICES)
DEFAULT_LOCALES = list(SUPPORTED_LOCALES)
DEFAULT_RUNTIME = "iOS 27.0"

PASSES_PER_PAIR = len(PASSES)

RUNTIME_RE = re.compile(r"^iOS \d+\.\d+$")


class InputError(ValueError):
    """Fail-closed selection validation error."""


def _parse_json_list(raw: object, name: str) -> list:
    if not isinstance(raw, str) or not raw.strip():
        raise InputError(f"{name} must be a non-empty JSON list string")
    try:
        val = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise InputError(f"{name} must be a JSON list, got {raw!r}: {exc}")
    if not isinstance(val, list) or not val:
        raise InputError(f"{name} must be a non-empty JSON list, got {raw!r}")
    for item in val:
        if not isinstance(item, str) or not item:
            raise InputError(
                f"{name} must be a non-empty JSON list of strings, "
                f"got {raw!r}")
    return val


def _reject_duplicates(values: list, name: str) -> None:
    seen: set = set()
    dupes: set = set()
    for v in values:
        if v in seen:
            dupes.add(v)
        seen.add(v)
    if dupes:
        raise InputError(
            f"{name} has duplicate entries {sorted(dupes)}; "
            "each entry must appear once")


def parse_device_selection(raw: object) -> list[str]:
    """Validate a devices JSON list against the supported catalog."""
    values = _parse_json_list(raw, "devices")
    _reject_duplicates(values, "devices")
    for v in values:
        if v not in SUPPORTED_DEVICES:
            raise InputError(
                f"unknown device {v!r}; catalog: {list(SUPPORTED_DEVICES)}")
    return list(values)


def parse_locale_selection(raw: object) -> list[str]:
    """Validate a languages JSON list against the supported locales."""
    values = _parse_json_list(raw, "languages")
    _reject_duplicates(values, "languages")
    for v in values:
        if v not in SUPPORTED_LOCALES:
            raise InputError(
                f"unknown language {v!r}; locales: {list(SUPPORTED_LOCALES)}")
    return list(values)


def validate_runtime(raw: object) -> str:
    """Validate an iOS runtime string (grammar only, never executed)."""
    if not isinstance(raw, str):
        raise InputError(f"ios_runtime must be a string, got {raw!r}")
    text = raw.strip()
    if not RUNTIME_RE.match(text):
        raise InputError(
            f"ios_runtime must look like 'iOS 27.0', got {raw!r}")
    return text


def island_for_device(device: str) -> int:
    """Explicit 1/0 island token for a validated device (iPad probe gate)."""
    try:
        return DEVICE_CATALOG[device]["island"]
    except KeyError:
        raise InputError(
            f"unknown device {device!r}; catalog: {list(SUPPORTED_DEVICES)}")


def validate_selection(devices_raw: object, locales_raw: object,
                       runtime_raw: object) -> dict:
    """Validate all three selections; returns a summary for job outputs."""
    devices = parse_device_selection(devices_raw)
    locales = parse_locale_selection(locales_raw)
    runtime = validate_runtime(runtime_raw)
    pair_count = len(devices) * len(locales)
    return {
        "devices": devices,
        "locales": locales,
        "runtime": runtime,
        "worker_count": len(devices),
        "pair_count": pair_count,
        "pass_count": pair_count * PASSES_PER_PAIR,
    }
