#!/usr/bin/env python3
"""capture-state.json validation (runner side; app composition by core).

Exit-style result: ok / pending / failed. `preparing` is pending, never
success. `ready` requires full shape including build identity, counts,
sha binding, totals pinned against the independently recorded dictionary
(no pin -> ready refused; core dictionary pending), and (for the three
la-* frames) realtime metadata with canonical keys `started_at` /
`request_acknowledged_at` (aware ISO, naive refused).
"""

from __future__ import annotations

import json
import math
import re

from inspection import parse_aware_iso
from request_schema import (
    LA_FRAMES,
    PILOT_DECK_VERSION,
    SCREENSHOT_BID,
    SCREENSHOT_CONFIGURATION,
)

HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_ENTRIES = 55
PENDING = "pending"
OK = "ok"
FAILED = "failed"

TOTALS_SCALARS = ("all_seconds", "today_seconds", "week_seconds")
TOTALS_MAPS = ("category_seconds", "text_seconds")
TOTALS_KEYS = frozenset((*TOTALS_SCALARS, *TOTALS_MAPS))


class StateError(ValueError):
    pass


def _need(cond: bool, msg: str, errs: list[str]) -> None:
    if not cond:
        errs.append(msg)


def is_strict_nonneg_number(v: object) -> bool:
    return (
        isinstance(v, (int, float))
        and not isinstance(v, bool)
        and math.isfinite(v)
        and v >= 0
    )


def validate_totals_shape(totals: object) -> list[str]:
    """Strict shape check; rejects bool/NaN/inf, wrong keys, empty maps."""
    errs: list[str] = []
    if not isinstance(totals, dict):
        return ["expected_totals must be an object"]
    if set(totals.keys()) != TOTALS_KEYS:
        return [f"expected_totals keys must be exactly {sorted(TOTALS_KEYS)}"]
    for key in TOTALS_SCALARS:
        if not is_strict_nonneg_number(totals.get(key)):
            errs.append(
                f"expected_totals.{key} must be a finite non-negative number "
                "(bool/NaN/inf rejected)"
            )
    for key in TOTALS_MAPS:
        v = totals.get(key)
        if not isinstance(v, dict) or len(v) == 0:
            errs.append(f"expected_totals.{key} must be a non-empty object")
            continue
        for name, secs in v.items():
            if not isinstance(name, str) or not name:
                errs.append(f"expected_totals.{key} has an invalid entry name")
            if not is_strict_nonneg_number(secs):
                errs.append(
                    f"expected_totals.{key}[{name!r}] must be a finite "
                    "non-negative number"
                )
    return errs


def validate_state_dict(
    state: dict,
    request: dict,
    request_sha256: str,
    pinned_totals: dict | None = None,
) -> tuple[str, list[str]]:
    errs: list[str] = []
    if not isinstance(state, dict):
        return FAILED, ["state must be a JSON object"]
    status = state.get("status")
    if status == "preparing":
        return PENDING, ["app reports preparing; keep polling, no screenshot yet"]
    if status not in ("ready", "invalid", "failure"):
        return FAILED, [f"unknown status {status!r}"]
    if status in ("invalid", "failure"):
        errs.append(f"app refused preparation with status {status!r}")
        if status == "failure":
            err = state.get("error")
            _need(
                isinstance(err, dict)
                and isinstance(err.get("code"), str)
                and err["code"],
                "failure state must carry error.code",
                errs,
            )
        return FAILED, errs or [f"status {status!r} is not capturable"]

    # status == ready from here.
    _need(
        state.get("request_sha256") == request_sha256,
        "request_sha256 mismatch: stale or foreign session",
        errs,
    )
    _need(
        isinstance(state.get("request_sha256"), str)
        and bool(HEX64.match(state.get("request_sha256") or "")),
        "request_sha256 must be 64-hex",
        errs,
    )
    _need(
        state.get("deck_version") == request.get("deck_version") == PILOT_DECK_VERSION,
        "deck_version must match the approved pilot request",
        errs,
    )
    _need(
        state.get("frame") == request.get("frame"),
        "state frame must match the requested frame",
        errs,
    )
    counts = state.get("counts")
    _need(
        isinstance(counts, dict) and counts.get("entries") == EXPECTED_ENTRIES,
        f"counts.entries must be {EXPECTED_ENTRIES}",
        errs,
    )
    totals = state.get("expected_totals")
    errs.extend(validate_totals_shape(totals))
    if pinned_totals is None:
        errs.append(
            "expected_totals pin missing (core dictionary pending): "
            "ready refused without an independently pinned dictionary"
        )
    else:
        pin_errs = validate_totals_shape(pinned_totals)
        if pin_errs:
            errs.append(f"pinned totals dictionary is malformed: {pin_errs[0]}")
        elif totals != pinned_totals:
            if isinstance(totals, dict):
                for key in sorted(TOTALS_KEYS):
                    if totals.get(key) != pinned_totals.get(key):
                        errs.append(
                            f"expected_totals.{key} differs from pinned dictionary"
                        )
            else:
                errs.append("expected_totals differs from pinned dictionary")
    build = state.get("build")
    _need(isinstance(build, dict), "ready state must carry build identity", errs)
    if isinstance(build, dict):
        _need(
            build.get("configuration") == SCREENSHOT_CONFIGURATION,
            f"build.configuration must be {SCREENSHOT_CONFIGURATION!r}",
            errs,
        )
        _need(
            build.get("bundle_id") == SCREENSHOT_BID,
            f"build.bundle_id must be {SCREENSHOT_BID!r}",
            errs,
        )
    if state.get("frame") in LA_FRAMES:
        la = state.get("live_activity")
        _need(
            isinstance(la, dict), "live-activity ready requires live_activity block", errs
        )
        if isinstance(la, dict):
            _need(bool(la.get("activity_id")), "live_activity.activity_id required", errs)
            for key in ("started_at", "request_acknowledged_at"):
                anchor = la.get(key)
                if not anchor:
                    errs.append(f"live_activity.{key} (real anchor) required")
                    continue
                try:
                    parse_aware_iso(anchor)
                except ValueError as exc:
                    errs.append(f"live_activity.{key}: {exc}")
    if isinstance(state.get("error"), dict) and state["error"].get("code"):
        errs.append("ready state must not carry error")
    return (OK, []) if not errs else (FAILED, errs)


def validate_session_ack(
    state: dict,
    envelope: dict,
    pinned_totals: dict | None = None,
) -> tuple[str, list[str]]:
    """Validate a frozen-v2 session ack against its command envelope.

    Checks full identity binding (nonce/run/domain/seq/frame/mode/hash) plus
    the accepted-command transcript, then delegates payload-level ready
    checks to validate_state_dict with the inner payload. `preparing` stays
    pending (identity still bound); v1 states without session identity are
    rejected here (no legacy branch) — use validate_state_dict for those.
    """
    errs: list[str] = []
    schema = state.get("schema_version") if isinstance(state, dict) else None
    if type(schema) is not int or schema != 2:
        # Unsupported shapes fail closed even when every binding matches:
        # holding the right nonce/seq/hash is no exception to the schema.
        return FAILED, ["ack schema_version must be integer 2 "
                        "(unsupported shape rejected; no legacy branch)"]
    if not isinstance(state, dict):
        return FAILED, ["state must be a JSON object"]
    if not isinstance(envelope, dict):
        return FAILED, ["envelope must be a JSON object"]
    import session as sess

    env_errs = sess.validate_envelope(envelope)
    if env_errs:
        return FAILED, [f"envelope invalid: {env_errs[0]}"]
    for key in ("session_nonce", "run_id", "session_domain", "seq",
                "frame", "mode", "request_sha256"):
        if state.get(key) != envelope.get(key):
            return FAILED, [f"ack {key} {state.get(key)!r} != command "
                            f"{envelope.get(key)!r}: stale or foreign ack"]
    transcript = state.get("transcript")
    if not isinstance(transcript, list) or not transcript:
        return FAILED, ["ack carries no accepted-command transcript"]
    covered = any(isinstance(row, dict)
                  and row.get("seq") == envelope["seq"]
                  and row.get("frame") == envelope["frame"]
                  and row.get("request_sha256") == envelope["request_sha256"]
                  for row in transcript)
    if not covered:
        return FAILED, ["ack transcript does not cover the active command"]
    status = state.get("status")
    if status == "preparing":
        return PENDING, ["app reports preparing; keep polling, no screenshot yet"]
    if status not in ("ready",):
        # Session failures/invalid states surface here with identity bound;
        # the runner treats them as terminal for the active command.
        detail = ""
        err = state.get("error")
        if isinstance(err, dict) and err.get("code"):
            detail = f": {err['code']}"
        return FAILED, [f"session command {status}{detail}"]
    try:
        inner = sess.parse_envelope_payload(envelope)
    except sess.SessionError as exc:
        return FAILED, [str(exc)]
    return validate_state_dict(state, inner, envelope["request_sha256"],
                               pinned_totals)


def load_state_file(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except FileNotFoundError:
        raise StateError(f"state file not found: {path}")
    except json.JSONDecodeError as exc:
        raise StateError(f"malformed state JSON in {path}: {exc}")
    if not isinstance(obj, dict):
        raise StateError("state file must contain a JSON object")
    return obj


def load_pinned_totals(path: str) -> dict:
    """Load the independently pinned totals dictionary file."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except FileNotFoundError:
        raise StateError(f"pinned totals file not found: {path}")
    except json.JSONDecodeError as exc:
        raise StateError(f"malformed pinned totals JSON in {path}: {exc}")
    if not isinstance(obj, dict):
        raise StateError("pinned totals file must contain a JSON object")
    errs = validate_totals_shape(obj)
    if errs:
        raise StateError(f"pinned totals file malformed: {errs[0]}")
    return obj
