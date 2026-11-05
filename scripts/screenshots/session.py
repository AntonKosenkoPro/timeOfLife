#!/usr/bin/env python3
"""Session protocol helpers (frozen v2 envelope, evidence/protocol.md).

Pure runner-side contract, stdlib only, no device I/O except atomic queue
files under caller-supplied tmp/out roots (never the repo). The app side
(Swift) implements the mirror; the golden fixture
(tests/fixtures/session_envelope_golden.json) pins the cross-language
contract: request_sha256 is sha256 over the raw request_json UTF-8 bytes
(trailing NL included), never over a re-serialized dictionary.

Envelope v2 exact keys:
  {schema_version:2, run_id, session_nonce:32-lower-hex,
   session_domain:pinned|realtime, seq:0-based-int, frame, mode,
   request_sha256, request_json}
request_json is the canonical schema-1 payload as a UTF-8 STRING.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import time
from pathlib import Path
from typing import Any

import request_schema as rs

SESSION_SCHEMA_VERSION = 2
SESSION_DOMAINS = ("pinned", "realtime")
PINNED_SESSION_FRAMES = ("track-running", "insights", "history", "add-entry")
REALTIME_SESSION_FRAMES = ("la-lock", "la-compact", "la-expanded")

NONCE_RE = re.compile(r"^[0-9a-f]{32}$")

# Fail-closed device catalog: dispatch keys mirror the workflow device
# matrix (iphone69/iphone63/ipad13, keys preserved). Geometry + island
# expectation are validated against it, and island attestation
# additionally requires the probe's ACTUAL simctl-reported
# deviceTypeIdentifier to be one of the cataloged models for the key — a
# different model (even same family / same geometry) cannot attest the
# key. Model identifiers below are the real host SimDeviceType strings
# (read-only `simctl list -j devicetypes`, Xcode 27.1: iPhone 18 Pro Max,
# iPhone 17, iPad Pro 13-inch (M5) 12GB + 16GB; the workflow looks up
# preinstalled sims by exact device name + runtime, so both M5 13-inch
# variants qualify). Geometry canvases
# (1320x2868/1206x2622/2064x2752) are PRESERVED, not SDK-verified: the
# devicetypes listing carries no dimension metadata, so native geometry
# verification is delegated to a separate native sim-probe worker after
# serialization — never claimed from the model name alone. Old 17 Pro Max
# / M4 identifiers are NOT accepted here (no legacy branches, no aliases).
# PENDING (owner frame decision): 18 Pro Max captures are review
# material until the owner approves the frame/bezel pairing; this catalog
# invents no art and leaves staging/verification untouched.
DEVICE_CATALOG: dict[str, dict[str, Any]] = {
    "iphone69": {"geometry": (1320, 2868), "island": True,
                 "sim": "iPhone 18 Pro Max",
                 "models": frozenset({
                     "com.apple.CoreSimulator.SimDeviceType."
                     "iPhone-18-Pro-Max"})},
    "iphone63": {"geometry": (1206, 2622), "island": True,
                 "sim": "iPhone 17",
                 "models": frozenset({
                     "com.apple.CoreSimulator.SimDeviceType.iPhone-17"})},
    "ipad13": {"geometry": (2064, 2752), "island": False,
               "sim": "iPad Pro 13-inch (M5)",
               "models": frozenset({
                   "com.apple.CoreSimulator.SimDeviceType."
                   "iPad-Pro-13-inch-M5-12GB",
                   "com.apple.CoreSimulator.SimDeviceType."
                   "iPad-Pro-13-inch-M5-16GB"})},
}

SIM_DEVICE_TYPE_PREFIX = "com.apple.CoreSimulator.SimDeviceType."
# deviceTypeIdentifier suffix → Dynamic Island presence. iPads uniformly
# lack the island (prefix rule — no iPad has or is announced with one);
# iPhones are enumerated explicitly and UNKNOWN models fail closed (extend
# with evidence, never guess). Factual pins: notch-only iPhones (SE all
# generations, 14/14 Plus, 16e) are False; 14 Pro and every 15/16 (except
# 16e)/17 incl. Air are True.
ISLAND_BY_MODEL_SUFFIX: dict[str, bool] = {
    "iPhone-SE": False,
    "iPhone-SE--2nd-generation-": False,
    "iPhone-SE-3rd-generation": False,
    "iPhone-14": False,
    "iPhone-14-Plus": False,
    "iPhone-14-Pro": True,
    "iPhone-14-Pro-Max": True,
    "iPhone-15": True,
    "iPhone-15-Plus": True,
    "iPhone-15-Pro": True,
    "iPhone-15-Pro-Max": True,
    "iPhone-16": True,
    "iPhone-16-Plus": True,
    "iPhone-16-Pro": True,
    "iPhone-16-Pro-Max": True,
    "iPhone-16e": False,
    "iPhone-17": True,
    "iPhone-17-Pro": True,
    "iPhone-17-Pro-Max": True,
    "iPhone-18-Pro": True,
    "iPhone-18-Pro-Max": True,
    "iPhone-Air": True,
}


def island_for_model(device_type_identifier: Any) -> bool:
    """Dynamic Island presence for a simctl deviceTypeIdentifier.

    Accepts the full identifier or the bare suffix. iPad identifiers match
    by prefix (no iPad ships an island); iPhones/SE match the explicit
    table. Anything else (Apple TV/Watch, unknown future iPhones) raises
    SessionError — extend the table with evidence, never guess.
    """
    if not isinstance(device_type_identifier, str) \
            or not device_type_identifier:
        raise SessionError("deviceTypeIdentifier must be a non-empty string")
    suffix = device_type_identifier
    if suffix.startswith(SIM_DEVICE_TYPE_PREFIX):
        suffix = suffix[len(SIM_DEVICE_TYPE_PREFIX):]
    if not suffix or "/" in suffix or suffix.startswith("."):
        raise SessionError(
            f"malformed deviceTypeIdentifier {device_type_identifier!r}")
    if suffix.startswith("iPad"):
        return False
    if suffix in ISLAND_BY_MODEL_SUFFIX:
        return ISLAND_BY_MODEL_SUFFIX[suffix]
    raise SessionError(
        f"unknown model {suffix!r} for island attestation; extend "
        "ISLAND_BY_MODEL_SUFFIX with evidence")


def normalize_model_identifier(device_type_identifier: Any) -> str:
    """Full SimDeviceType identifier (bare suffixes gain the prefix)."""
    if not isinstance(device_type_identifier, str) \
            or not device_type_identifier:
        raise SessionError("deviceTypeIdentifier must be a non-empty string")
    if "." in device_type_identifier:
        return device_type_identifier
    return SIM_DEVICE_TYPE_PREFIX + device_type_identifier


def check_catalog_model(device_key: Any, device_type_identifier: Any,
                        name: Any) -> list[str]:
    """Exact catalog proof for a probe model (shared probe/executor use).

    The ACTUAL simctl-reported identifier must be one of the cataloged
    models for the requested key; the human name is carried evidence
    (the preinstalled device name, e.g. "iPad Pro 13-inch (M5)", so its
    presence — not its value — is required). A different model, even same
    family and geometry, cannot attest the key. Never raises on input.
    """
    if not isinstance(device_key, str) or device_key not in DEVICE_CATALOG:
        return [f"unknown device_key {device_key!r}"]
    try:
        full_identifier = normalize_model_identifier(device_type_identifier)
    except SessionError as exc:
        return [str(exc)]
    allowed = DEVICE_CATALOG[device_key].get("models") or frozenset()
    if full_identifier not in allowed:
        return [f"model {full_identifier!r} is not cataloged for "
                f"{device_key!r} (exact catalog proof required; a "
                "different model cannot attest this key)"]
    if not isinstance(name, str) or not name or ".." in name \
            or name.startswith("/"):
        return ["probe model name must be a non-empty safe string"]
    return []

ENVELOPE_KEYS = frozenset((
    "schema_version", "run_id", "session_nonce", "session_domain",
    "seq", "frame", "mode", "request_sha256", "request_json",
))

# Payload fields allowed to differ between commands of one session besides
# the advancing frame (frame/mode advance per the domain story; run_id is
# volatile across passes and excluded from semantic comparison).
PAYLOAD_IMMUTABLE_KEYS = (
    "schema_version", "deck_version", "locale", "region", "timezone",
    "calendar", "week_rule", "reference_local_iso", "app_elapsed_s",
    "appearance", "dynamic_type", "keyboard", "status_bar", "treatment",
    "frames", "geometry", "configuration", "bundle_id", "expected_totals",
)


class SessionError(ValueError):
    """Fail-closed session protocol error."""


def new_nonce() -> str:
    """Fresh 32-lower-hex session nonce (CSPRNG; never logged with payload)."""
    return secrets.token_hex(16)


def validate_nonce(nonce: Any) -> list[str]:
    if not isinstance(nonce, str) or not NONCE_RE.match(nonce):
        return ["session_nonce must be 32 lower-hex characters"]
    return []


def frames_for_domain(domain: str, island_available: bool = True) -> list[str]:
    """Ordered frame story for a session domain.

    iPad (no Dynamic Island) realtime sessions carry only la-lock; Island
    N/A is recorded via a separate capability probe, never via sessions.
    """
    if domain == "pinned":
        return list(PINNED_SESSION_FRAMES)
    if domain == "realtime":
        if island_available:
            return list(REALTIME_SESSION_FRAMES)
        return ["la-lock"]
    raise SessionError(f"unknown session_domain {domain!r}")


def semantic_sha256_of_payload(payload: dict) -> str:
    """Semantic hash excluding volatile payload fields only (run_id).

    Envelope-only identities (nonce/domain/seq) never enter this projection.
    Single implementation point: request_schema owns the projection.
    """
    return rs.semantic_sha256(payload)


def build_envelope(payload: dict, *, run_id: str, session_nonce: str,
                   session_domain: str, seq: int) -> dict:
    """Build a v2 command envelope around a validated schema-1 payload.

    Raises SessionError fail-closed. The payload dict must already carry
    matching run_id/frame/mode; request_json is its canonical bytes decoded
    as UTF-8 (trailing NL preserved), and request_sha256 is sha256 over
    that exact string's UTF-8 bytes.
    """
    nonce_errs = validate_nonce(session_nonce)
    if nonce_errs:
        raise SessionError(nonce_errs[0])
    if session_domain not in SESSION_DOMAINS:
        raise SessionError(f"unknown session_domain {session_domain!r}")
    if isinstance(seq, bool) or not isinstance(seq, int) or seq < 0:
        raise SessionError("seq must be a non-negative int (0-based)")
    if not isinstance(payload, dict):
        raise SessionError("payload must be a JSON object")
    if payload.get("run_id") != run_id:
        raise SessionError("payload run_id must match the envelope run_id")
    errs = rs.validate_request_dict(payload)
    if errs:
        raise SessionError(f"invalid payload: {errs[0]}")
    frame = payload["frame"]
    if session_domain == "pinned" and frame not in PINNED_SESSION_FRAMES:
        raise SessionError(f"frame {frame!r} not allowed in pinned sessions")
    if session_domain == "realtime" and frame not in REALTIME_SESSION_FRAMES:
        raise SessionError(
            f"frame {frame!r} not allowed in realtime sessions")
    request_json = rs.canonical_bytes(payload).decode("utf-8")
    digest = hashlib.sha256(request_json.encode("utf-8")).hexdigest()
    return {
        "schema_version": SESSION_SCHEMA_VERSION,
        "run_id": run_id,
        "session_nonce": session_nonce,
        "session_domain": session_domain,
        "seq": seq,
        "frame": frame,
        "mode": payload["mode"],
        "request_sha256": digest,
        "request_json": request_json,
    }


def parse_envelope_payload(env: dict) -> dict:
    """Parse the inner request_json string; raises SessionError."""
    if not isinstance(env, dict):
        raise SessionError("envelope must be a JSON object")
    raw = env.get("request_json")
    if not isinstance(raw, str) or not raw:
        raise SessionError("envelope request_json must be a non-empty string")
    try:
        inner = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SessionError(f"envelope request_json malformed: {exc}")
    if not isinstance(inner, dict):
        raise SessionError("envelope request_json must decode to an object")
    return inner


def validate_envelope(env: Any) -> list[str]:
    """Strict v2 validation; returns diagnostics, never raises on input."""
    if not isinstance(env, dict):
        return ["envelope must be a JSON object"]
    errs: list[str] = []
    if env.get("schema_version") != SESSION_SCHEMA_VERSION:
        errs.append(f"schema_version must be {SESSION_SCHEMA_VERSION} "
                    "(v1 raw payloads rejected; no legacy branch)")
    if not isinstance(env.get("run_id"), str) or not env.get("run_id"):
        errs.append("run_id must be a non-empty string")
    elif not rs.RUN_ID_RE.match(env["run_id"]):
        errs.append("run_id must match [A-Za-z0-9_-]{1,64}")
    errs.extend(validate_nonce(env.get("session_nonce")))
    if env.get("session_domain") not in SESSION_DOMAINS:
        errs.append(f"session_domain must be one of {list(SESSION_DOMAINS)}")
    seq = env.get("seq")
    if isinstance(seq, bool) or not isinstance(seq, int) or seq < 0:
        errs.append("seq must be a non-negative int (0-based)")
    if env.get("frame") not in rs.PILOT_FRAMES:
        errs.append(f"frame must be one of {list(rs.PILOT_FRAMES)}")
    if env.get("mode") not in (rs.MODE_PINNED, rs.MODE_REALTIME):
        errs.append("mode must be a known capture mode")
    digest = env.get("request_sha256")
    if not isinstance(digest, str) or not re.match(r"^[0-9a-f]{64}$", digest):
        errs.append("request_sha256 must be 64-hex")
    try:
        inner = parse_envelope_payload(env)
    except SessionError as exc:
        return errs + [str(exc)]
    # Exact raw-UTF-8 hash rule: recompute over the transmitted string.
    try:
        actual = hashlib.sha256(
            env["request_json"].encode("utf-8")).hexdigest()
    except (UnicodeError, AttributeError):
        return errs + ["request_json is not UTF-8 encodable"]
    if isinstance(digest, str) and actual != digest:
        errs.append("request_sha256 mismatch: not sha256(request_json.utf8)")
    # Outer/inner binding.
    for key in ("run_id", "frame", "mode"):
        if env.get(key) != inner.get(key):
            errs.append(f"outer/inner {key} mismatch")
    inner_errs = rs.validate_request_dict(inner)
    if inner_errs:
        errs.append(f"inner payload invalid: {inner_errs[0]}")
    else:
        domain = env.get("session_domain")
        frame = env.get("frame")
        if domain == "pinned" and frame not in PINNED_SESSION_FRAMES:
            errs.append(f"frame {frame!r} not allowed in pinned sessions")
        if domain == "realtime" and frame not in REALTIME_SESSION_FRAMES:
            errs.append(f"frame {frame!r} not allowed in realtime sessions")
    return errs


def transcript_entry(env: dict) -> dict:
    """Accepted-command transcript row for acks/receipts."""
    inner = parse_envelope_payload(env)
    return {
        "seq": env["seq"],
        "frame": env["frame"],
        "request_sha256": env["request_sha256"],
        "request_semantic_sha256": semantic_sha256_of_payload(inner),
    }


def validate_transition(prev: dict | None, nxt: dict,
                        consumed_seqs: set[int]) -> list[str]:
    """Validate the next envelope against session history.

    Enforces monotonic seq, domain story order, immutable session inputs,
    and replay rejection (seq already consumed fails even byte-identical).
    Returns diagnostics; empty means acceptable as the next command.
    """
    errs = validate_envelope(nxt)
    if errs:
        return errs
    seq = nxt["seq"]
    if seq in consumed_seqs:
        return [f"replay: seq {seq} already consumed; "
                "re-publication fails closed even with identical bytes"]
    if prev is None:
        if seq != 0:
            return [f"first command of a session must carry seq 0, got {seq}"]
        return []
    if nxt.get("session_nonce") != prev.get("session_nonce"):
        return ["session_nonce changed mid-session"]
    if nxt.get("session_domain") != prev.get("session_domain"):
        return ["session_domain changed mid-session"]
    if nxt.get("run_id") != prev.get("run_id"):
        return ["run_id changed mid-session"]
    if seq != prev["seq"] + 1:
        return [f"seq must advance by exactly one "
                f"(prev {prev['seq']}, got {seq})"]
    story = frames_for_domain(nxt["session_domain"])
    try:
        want = story[story.index(prev["frame"]) + 1]
    except (ValueError, IndexError):
        return [f"frame {prev['frame']!r} has no successor in this session"]
    if nxt["frame"] != want:
        return [f"frame must advance {prev['frame']!r} -> {want!r}, "
                f"got {nxt['frame']!r}"]
    prev_inner = parse_envelope_payload(prev)
    next_inner = parse_envelope_payload(nxt)
    for key in PAYLOAD_IMMUTABLE_KEYS:
        if key == "expected_totals":
            continue  # compared structurally below via JSON dump
        if prev_inner.get(key) != next_inner.get(key):
            return [f"session-immutable payload field changed: {key}"]
    if (json.dumps(prev_inner.get("expected_totals"), sort_keys=True)
            != json.dumps(next_inner.get("expected_totals"), sort_keys=True)):
        return ["session-immutable payload field changed: expected_totals"]
    # expected_totals is immutable within a session; frame/mode advance only.
    return []


# --- Atomic file transport (runner-side model of the frozen contract) ---

SESSIONS_DIRNAME = "capture-sessions"
COMMAND_FILENAME = "command.json"
CONSUMED_TEMPLATE = "consumed-{seq}.json"
ENDED_FILENAME = "session-ended.json"


def _safe_sessions_root(sessions_root: Path) -> Path:
    if not isinstance(sessions_root, Path):
        sessions_root = Path(sessions_root)
    return sessions_root


def session_dir_for(sessions_root: Path, nonce: str) -> Path:
    """Owned session dir; validates nonce and rejects symlink escape."""
    if validate_nonce(nonce):
        raise SessionError(f"invalid session_nonce {nonce!r}")
    root = _safe_sessions_root(sessions_root)
    candidate = root / nonce
    # Reject traversal even from a crafted root: the final component must be
    # exactly the nonce.
    if candidate.name != nonce or candidate.parent != root:
        raise SessionError("session path escapes the owned namespace")
    if candidate.is_symlink():
        raise SessionError("session dir is a symlink; refusing escape")
    if root.is_symlink():
        raise SessionError("sessions root contains a symlink; refusing")
    return candidate


def queue_path_for(sessions_root: Path, nonce: str) -> Path:
    """Queue file path; same guards as the session dir."""
    return session_dir_for(sessions_root, nonce) / COMMAND_FILENAME


def session_command_relpath(nonce: str) -> str:
    """On-device relative queue path (app derives the same way)."""
    if validate_nonce(nonce):
        raise SessionError(f"invalid session_nonce {nonce!r}")
    return f"{SESSIONS_DIRNAME}/{nonce}/{COMMAND_FILENAME}"


def consumed_seqs(sessions_root: Path, nonce: str) -> set[int]:
    """Retained consumed seqs from consumed-*.json records."""
    session_dir = session_dir_for(sessions_root, nonce)
    found: set[int] = set()
    if not session_dir.is_dir():
        return found
    for child in sorted(session_dir.glob("consumed-*.json")):
        m = re.match(r"^consumed-(\d+)\.json$", child.name)
        if m:
            found.add(int(m.group(1)))
    return found


def _session_ended(session_dir: Path) -> bool:
    return (session_dir / ENDED_FILENAME).is_file()


def publish_command(sessions_root: Path, envelope: dict) -> Path:
    """Atomically publish one envelope (same-dir temp + os.replace).

    Fails closed when a command is already queued (one-in-flight), when the
    seq was already consumed (replay, even identical bytes), when the
    session already ended, or on path/symlink escape.
    """
    errs = validate_envelope(envelope)
    if errs:
        raise SessionError(f"invalid envelope: {errs[0]}")
    nonce = envelope["session_nonce"]
    session_dir = session_dir_for(sessions_root, nonce)
    if _session_ended(session_dir):
        raise SessionError("session already ended; stale commands rejected")
    if envelope["seq"] in consumed_seqs(sessions_root, nonce):
        raise SessionError(
            f"replay: seq {envelope['seq']} already consumed; "
            "re-publication fails closed even with identical bytes")
    session_dir.mkdir(parents=True, exist_ok=True)
    queue = session_dir / COMMAND_FILENAME
    if queue.exists() or queue.is_symlink():
        raise SessionError("one command already in flight; "
                           "await its ack before publishing")
    raw = (json.dumps(envelope, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False).encode("utf-8") + b"\n")
    tmp = session_dir / f".{COMMAND_FILENAME}.tmp-{os.getpid()}"
    try:
        tmp.write_bytes(raw)
        os.replace(tmp, queue)
    finally:
        try:
            if tmp.exists():
                tmp.unlink()
        except OSError:
            pass
    return queue


def claim_command(sessions_root: Path, nonce: str) -> dict | None:
    """Atomically claim the queued command BEFORE execution (app model).

    Renames command.json to the retained consumed-<seq>.json record and
    returns the envelope. Returns None when no command is queued
    (re-observing the retained record is a no-op, not an error).
    """
    session_dir = session_dir_for(sessions_root, nonce)
    queue = session_dir / COMMAND_FILENAME
    if queue.is_symlink():
        raise SessionError("queued command is a symlink; refusing escape")
    if not queue.is_file():
        return None
    try:
        raw = queue.read_bytes()
    except OSError as exc:
        raise SessionError(f"cannot read queued command: {exc}")
    try:
        env = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeError) as exc:
        # Partial writes fail closed; remove the corrupt file so the
        # session does not wedge on garbage (the seq stays unconsumed and
        # the runner must republish explicitly).
        try:
            queue.unlink()
        except OSError:
            pass
        raise SessionError(f"queued command malformed (partial write?): {exc}")
    errs = validate_envelope(env)
    if errs:
        try:
            queue.unlink()
        except OSError:
            pass
        raise SessionError(f"queued command invalid: {errs[0]}")
    if env.get("session_nonce") != nonce:
        try:
            queue.unlink()
        except OSError:
            pass
        raise SessionError("queued command targets another session")
    dest = session_dir / CONSUMED_TEMPLATE.format(seq=env["seq"])
    if dest.exists():
        # A retained record already exists for this seq: the queue file is
        # a NEW publication of an old seq -> explicit replay, fail closed.
        try:
            queue.unlink()
        except OSError:
            pass
        raise SessionError(
            f"replay: seq {env['seq']} already consumed; "
            "re-publication fails closed even with identical bytes")
    try:
        os.replace(queue, dest)
    except OSError as exc:
        raise SessionError(f"cannot claim queued command: {exc}")
    return env


def mark_session_ended(sessions_root: Path, nonce: str, final_seq: int) -> Path:
    """Record end-of-session; later publishes are stale and rejected."""
    session_dir = session_dir_for(sessions_root, nonce)
    session_dir.mkdir(parents=True, exist_ok=True)
    marker = session_dir / ENDED_FILENAME
    marker.write_text(json.dumps({"final_seq": final_seq,
                                  "session_nonce": nonce},
                                 sort_keys=True) + "\n", encoding="utf-8")
    return marker


def build_cleanup_argv(udid: str, bid: str, run_id: str, sha: str, *,
                       session_nonce: str, session_domain: str,
                       final_seq: int) -> list[str]:
    """Cleanup launch argv with session tokens (extends preflight grammar).

    Validation here is strict (SessionError); token spelling stays in
    preflight.cleanup_launch_argv as the single grammar point.
    """
    from preflight import cleanup_launch_argv as _base

    if validate_nonce(session_nonce):
        raise SessionError(f"invalid session_nonce {session_nonce!r}")
    if session_domain not in SESSION_DOMAINS:
        raise SessionError(f"unknown session_domain {session_domain!r}")
    if isinstance(final_seq, bool) or not isinstance(final_seq, int) \
            or final_seq < 0:
        raise SessionError("final_seq must be a non-negative int")
    return _base(udid, bid, run_id, sha, session_nonce=session_nonce,
                 session_domain=session_domain, final_seq=final_seq)


# Spawn-trail bound: only the last N classified command events are
# retained per session; older ones roll off with a truncation counter.
SPAWN_TRAIL_CAP = 20
SPAWN_OUTCOMES = ("ok", "timeout", "oserror")


class PhaseStats:
    """Monotonic runner timings + counters + spawn trail (task 2.1).

    Runner phases use time.monotonic only. App-side durations (seed,
    validation, mount, settle) are recorded separately via
    note_app_duration and NEVER subtracted from runner phases: the two
    clocks live in different domains.

    The spawn trail records the last SPAWN_TRAIL_CAP classified simctl
    command events (semantic category only — never raw argv, paths,
    nonces, launch args, or stderr) with the active phase,
    start-relative-ms, duration-ms, outcome, and return code where
    available. Older entries roll off with a truncation counter. It is
    diagnostics only: timeouts, deadlines, retries, counters, and
    receipt failure ordering are unchanged.
    """

    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._t0 = clock()
        self._starts: dict[str, float] = {}
        self._phase_stack: list[str] = []
        self.phases_ms: dict[str, float] = {}
        self.counters: dict[str, int] = {}
        self.app_durations_ms: dict[str, float] = {}
        self.spawn_trail: list[dict[str, Any]] = []
        self.spawn_dropped: int = 0

    def now(self) -> float:
        """Current runner-clock reading (seconds, monotonic domain)."""
        return self._clock()

    def current_phase(self) -> str | None:
        """Innermost started-but-unstopped phase, or None outside one."""
        return self._phase_stack[-1] if self._phase_stack else None

    def start(self, name: str) -> None:
        self._starts[name] = self._clock()
        self._phase_stack.append(name)

    def stop(self, name: str) -> float:
        if name not in self._starts:
            raise SessionError(f"phase {name!r} was never started")
        elapsed_ms = (self._clock() - self._starts.pop(name)) * 1000.0
        self.phases_ms[name] = self.phases_ms.get(name, 0.0) + elapsed_ms
        if name in self._phase_stack:
            idx = len(self._phase_stack) - 1 - \
                self._phase_stack[::-1].index(name)
            self._phase_stack.pop(idx)
        return elapsed_ms

    def count(self, name: str, n: int = 1) -> None:
        if not isinstance(n, int) or n < 0:
            raise SessionError("counter increment must be a non-negative int")
        self.counters[name] = self.counters.get(name, 0) + n

    def note_app_duration(self, name: str, duration_ms: float) -> None:
        """Record an app-clock duration (opaque; never mixed with phases)."""
        if not isinstance(duration_ms, (int, float)) or duration_ms < 0:
            raise SessionError("app duration must be non-negative")
        self.app_durations_ms[name] = float(duration_ms)

    def note_spawn(self, *, category: str, outcome: str,
                   t_start: float, t_end: float,
                   rc: int | None = None,
                   phase: str | None = None) -> dict[str, Any]:
        """Record one classified spawn event (runner clock only).

        category is a semantic label (e.g. "ui-appearance-query",
        "launch-cleanup") chosen by the caller — raw argv, paths,
        nonces, launch args, and stderr are NEVER accepted here, so
        they cannot leak into persisted stats. outcome is one of
        "ok" | "timeout" | "oserror". t_start/t_end are runner-clock
        readings (same domain as phases); skew clamps to 0.0 rather
        than recording negatives. Only the last SPAWN_TRAIL_CAP
        entries are retained; older ones roll off with spawn_dropped.
        """
        if not isinstance(category, str) or not category:
            raise SessionError("spawn category must be a non-empty string")
        if outcome not in SPAWN_OUTCOMES:
            raise SessionError(
                f"spawn outcome must be one of {list(SPAWN_OUTCOMES)}")
        if not isinstance(t_start, (int, float)) or \
                not isinstance(t_end, (int, float)):
            raise SessionError("spawn clock readings must be numbers")
        if rc is not None and (isinstance(rc, bool)
                               or not isinstance(rc, int)):
            raise SessionError("spawn rc must be an int or None")
        start_rel_ms = max(0.0, (t_start - self._t0) * 1000.0)
        duration_ms = max(0.0, (t_end - t_start) * 1000.0)
        entry: dict[str, Any] = {
            "category": category,
            "phase": phase if phase is not None else (
                self.current_phase() or "unknown"),
            "start_rel_ms": float(start_rel_ms),
            "duration_ms": float(duration_ms),
            "outcome": outcome,
            "rc": rc,
        }
        self.spawn_trail.append(entry)
        overflow = len(self.spawn_trail) - SPAWN_TRAIL_CAP
        if overflow > 0:
            del self.spawn_trail[0:overflow]
            self.spawn_dropped += overflow
        return entry

    def to_dict(self) -> dict[str, Any]:
        return {
            "phases_ms": dict(self.phases_ms),
            "counters": dict(self.counters),
            "app_durations_ms": dict(self.app_durations_ms),
            "spawn_trail": [dict(e) for e in self.spawn_trail],
            "spawn_dropped": self.spawn_dropped,
        }
