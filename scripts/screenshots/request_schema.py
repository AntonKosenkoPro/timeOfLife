#!/usr/bin/env python3
"""Capture-request schema (pilot stage): validation + deterministic bytes.

Interface confirmed with core iOS worker (2026-10-30); application-side
parsing/ready-state owned by core. This module is runner-side only and
uses stdlib.

Per-frame request files carry the full base context PLUS the chosen
``frame`` + derived ``mode`` so every launch starts a fresh session from
the same base request.
"""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

SCHEMA_VERSION = 1
PILOT_DECK_VERSION = "en-austin-1"
SCREENSHOT_BID = "com.antonkosenko.timeoflifeapp.screenshots"
SCREENSHOT_CONFIGURATION = "Screenshot"

PILOT_FRAMES = (
    "track-running",
    "insights",
    "history",
    "add-entry",
    "la-lock",
    "la-compact",
    "la-expanded",
)

APP_CLOCK_FRAMES = PILOT_FRAMES[:4]
LA_FRAMES = PILOT_FRAMES[4:]
MODE_PINNED = "app-clock-pinned"
MODE_REALTIME = "live-activity-realtime"

# Pilot pins (task 1.4). Totals intentionally NOT pinned here: core owns
# the exact totals dictionary; runner must not claim totals verified.
PILOT_LOCALE = "en"
PILOT_REGION = "US"
PILOT_TIMEZONE = "America/Chicago"
PILOT_REFERENCE_LOCAL_ISO = "2026-10-20T09:41:00"
PILOT_APP_ELAPSED_S = 754
PILOT_APPEARANCE = "light"
PILOT_DYNAMIC_TYPE = "large"
PILOT_KEYBOARD_LANGUAGE = "en-US"
PILOT_TREATMENT = "light-v1"
PILOT_GEOMETRY = (1320, 2868)

# Capture-matrix geometries (design §5): pilot 6.9-inch iPhone plus the two
# expansion targets. Non-pilot geometries require 5.4 approval via the
# "ipad" device-matrix gate (covers 6.5-inch iPhone + 13-inch iPad).
MATRIX_GEOMETRIES = {
    (1320, 2868): "iphone-6.9",
    (1242, 2688): "iphone-6.5",
    (2064, 2752): "ipad-13",
}

# Software-keyboard language per locale (BCP 47). Pilot en stays en-US;
# expansion locales use their own keyboard. Enforced by schema validation;
# non-English requests additionally require 5.4 approval at the CLI gate.
KEYBOARD_FOR_LOCALE = {
    "en": "en-US",
    "ru": "ru-RU",
    "zh-Hans": "zh-Hans-CN",
    "es-419": "es-MX",
    "pt-BR": "pt-BR",
}

# Locale-native week membership differs (design §3): ru/Moscow week holds
# fewer reference-week entries, so its pinned week total is 12300 s while
# every other deck pins 23100 s. today/all/category/text-shape invariants
# hold across all five decks.
EXPECTED_WEEK_SECONDS = {
    "en": 23100,
    "ru": 12300,
    "zh-Hans": 23100,
    "es-419": 23100,
    "pt-BR": 23100,
}

# Known-but-gated enums: valid identifiers that the pilot stage must
# refuse without 5.4 approval (checked by approval gate, not here).
KNOWN_LOCALES = ("en", "ru", "zh-Hans", "es-419", "pt-BR")
KNOWN_REGIONS = ("US", "RU", "CN", "MX", "BR")
KNOWN_TIMEZONES = (
    "America/Chicago",
    "Europe/Moscow",
    "Asia/Shanghai",
    "America/Mexico_City",
    "America/Sao_Paulo",
)
LOCALE_PAIRING = {
    "en": ("US", "America/Chicago"),
    "ru": ("RU", "Europe/Moscow"),
    "zh-Hans": ("CN", "Asia/Shanghai"),
    "es-419": ("MX", "America/Mexico_City"),
    "pt-BR": ("BR", "America/Sao_Paulo"),
}

RUN_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class RequestError(ValueError):
    """Fail-closed request validation error."""


def _is_str(v: Any) -> bool:
    return isinstance(v, str)


def is_la_frame(frame: str) -> bool:
    return frame in LA_FRAMES


def mode_for_frame(frame: str) -> str:
    return MODE_REALTIME if is_la_frame(frame) else MODE_PINNED


def validate_request_dict(req: dict) -> list[str]:
    """Return a list of diagnostics; empty means valid."""
    errs: list[str] = []
    if not isinstance(req, dict):
        return ["request must be a JSON object"]
    if req.get("schema_version") != SCHEMA_VERSION:
        errs.append(f"schema_version must be {SCHEMA_VERSION}")
    if req.get("deck_version") not in (PILOT_DECK_VERSION,):
        # Other deck versions do not exist yet; never fall back.
        errs.append(f"deck_version must be {PILOT_DECK_VERSION!r} at pilot stage")
    locale = req.get("locale")
    region = req.get("region")
    timezone = req.get("timezone")
    if locale not in KNOWN_LOCALES:
        errs.append(f"unknown locale {locale!r}")
    if region not in KNOWN_REGIONS:
        errs.append(f"unknown region {region!r}")
    if timezone not in KNOWN_TIMEZONES:
        errs.append(f"unknown timezone {timezone!r}")
    if (
        _is_str(locale)
        and _is_str(region)
        and _is_str(timezone)
        and locale in LOCALE_PAIRING
        and LOCALE_PAIRING[locale] != (region, timezone)
    ):
        errs.append(
            f"locale/region/timezone mismatch: {locale!r} requires "
            f"{LOCALE_PAIRING[locale]!r}, got ({region!r}, {timezone!r})"
        )
    if req.get("calendar") != "gregorian":
        errs.append("calendar must be 'gregorian'")
    if req.get("week_rule") != "locale-native":
        errs.append("week_rule must be 'locale-native'")
    if req.get("reference_local_iso") != PILOT_REFERENCE_LOCAL_ISO:
        errs.append(f"reference_local_iso must be {PILOT_REFERENCE_LOCAL_ISO!r}")
    if req.get("app_elapsed_s") != PILOT_APP_ELAPSED_S:
        errs.append(f"app_elapsed_s must be {PILOT_APP_ELAPSED_S}")
    if req.get("appearance") != PILOT_APPEARANCE:
        errs.append(f"appearance must be {PILOT_APPEARANCE!r}")
    if req.get("dynamic_type") != PILOT_DYNAMIC_TYPE:
        errs.append(f"dynamic_type must be {PILOT_DYNAMIC_TYPE!r}")
    kb = req.get("keyboard")
    if not isinstance(kb, dict):
        errs.append("keyboard must be an object")
    else:
        expected_kb = KEYBOARD_FOR_LOCALE.get(locale) if _is_str(locale) else None
        if expected_kb is None:
            expected_kb = PILOT_KEYBOARD_LANGUAGE
        if kb.get("language") != expected_kb:
            errs.append(f"keyboard.language must be {expected_kb!r} for locale {locale!r}")
        if kb.get("software_visible") is not True:
            errs.append("keyboard.software_visible must be true")
        if kb.get("presentation") != "docked":
            errs.append("keyboard.presentation must be 'docked'")
    sb = req.get("status_bar")
    if not isinstance(sb, dict):
        errs.append("status_bar must be an object")
    else:
        if sb.get("time") != "9:41":
            errs.append("status_bar.time must be '9:41'")
        if sb.get("battery") != 100:
            errs.append("status_bar.battery must be 100")
        if sb.get("network") != "wifi":
            errs.append("status_bar.network must be 'wifi'")
    if req.get("treatment") != PILOT_TREATMENT:
        errs.append(f"treatment must be {PILOT_TREATMENT!r}")
    frames = req.get("frames")
    if not isinstance(frames, list) or list(frames) != list(PILOT_FRAMES):
        errs.append(f"frames must be exactly {list(PILOT_FRAMES)!r} in order")
    frame = req.get("frame")
    if frame not in PILOT_FRAMES:
        errs.append(f"frame must be one of {list(PILOT_FRAMES)!r}")
    mode = req.get("mode")
    if _is_str(frame) and mode != mode_for_frame(frame):
        errs.append(f"mode for frame {frame!r} must be {mode_for_frame(frame)!r}")
    run_id = req.get("run_id")
    if run_id is not None and (
        not _is_str(run_id) or not RUN_ID_RE.match(run_id)
    ):
        errs.append("run_id must match [A-Za-z0-9_-]{1,64} when present")
    return errs


def build_frame_request(base: dict, frame: str) -> dict:
    """Derive a per-frame request from the shared base (fresh session each)."""
    if frame not in PILOT_FRAMES:
        raise RequestError(f"unknown frame {frame!r}")
    derived = dict(base)
    derived["frame"] = frame
    derived["mode"] = mode_for_frame(frame)
    return derived


def canonical_bytes(req: dict) -> bytes:
    """Deterministic serialization; file stores these bytes + trailing NL."""
    return (
        json.dumps(req, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode(
            "utf-8"
        )
        + b"\n"
    )


def request_sha256_of_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def semantic_sha256(req: dict) -> str:
    """Hash of the request minus volatile run_id (cross-run comparison)."""
    semantic = {k: v for k, v in req.items() if k != "run_id"}
    return request_sha256_of_bytes(canonical_bytes(semantic))


def load_request_file(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except FileNotFoundError:
        raise RequestError(f"request file not found: {path}")
    except json.JSONDecodeError as exc:
        raise RequestError(f"malformed request JSON in {path}: {exc}")
    if not isinstance(obj, dict):
        raise RequestError(f"request file {path} must contain a JSON object")
    return obj


def decks_dir() -> str:
    """Absolute path of the versioned deck directory (5 totals files)."""
    from pathlib import Path as _Path

    here = _Path(__file__).resolve().parent
    root = here.parent.parent
    return str(root / "openspec" / "changes" / "app-store-screenshot-pilot" / "decks")


def totals_path_for_locale(locale: str) -> str:
    """Canonical pinned-totals file for a locale; fail-closed on unknown."""
    from pathlib import Path as _Path

    if locale not in KNOWN_LOCALES:
        raise RequestError(f"unknown locale {locale!r}")
    return str(_Path(decks_dir()) / f"totals-{locale}.json")


def load_pinned_totals_for_locale(locale: str) -> dict:
    """Load the independently pinned totals dictionary for a locale.

    Shape-checked lightly here (full numerics live in state_check);
    raises RequestError fail-closed on missing/malformed files.
    """
    path = totals_path_for_locale(locale)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except FileNotFoundError:
        raise RequestError(f"pinned totals file not found for {locale!r}: {path}")
    except json.JSONDecodeError as exc:
        raise RequestError(f"malformed pinned totals JSON for {locale!r}: {exc}")
    if not isinstance(obj, dict):
        raise RequestError(f"pinned totals for {locale!r} must contain a JSON object")
    for key in ("all_seconds", "today_seconds", "week_seconds",
                "category_seconds", "text_seconds"):
        if key not in obj:
            raise RequestError(f"pinned totals for {locale!r} missing {key!r}")
    return obj


def parse_geometry(text: str) -> tuple[int, int]:
    """Parse 'WxH' into a tuple; raises RequestError fail-closed."""
    try:
        w, h = text.split("x")
        geometry = (int(w), int(h))
    except ValueError:
        raise RequestError(f"geometry must look like 1320x2868, got {text!r}")
    if geometry not in MATRIX_GEOMETRIES:
        raise RequestError(
            f"unsupported geometry {geometry}; "
            f"supported: {sorted(MATRIX_GEOMETRIES)}"
        )
    return geometry


def is_pilot_geometry(geometry: tuple[int, int]) -> bool:
    return tuple(geometry) == tuple(PILOT_GEOMETRY)
