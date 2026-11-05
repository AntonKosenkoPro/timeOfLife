#!/usr/bin/env python3
"""Pilot capture CLI (runner side, stdlib only).

Subcommands (validation/gate/execution CLI; nothing auto-approves):
  validate-request  fail-closed request check (exit 0 valid, 2 invalid)
  write-request     derive per-frame request file (deterministic bytes+sha)
  make-request      emit a base request file from pins (--locale/--geometry)
  preflight         plan simctl argv + guards (dry-run default; --execute
                    requires LIFIO_CAPTURE_LEASE=1 and touches one device)
  check-state       validate app capture-state.json against the request
                    (+ optional --pinned-totals; ready refused without a pin)
  verify-picker     require picker keyboard inspection artifact (hash+language bound)
  check-approval    hash/file-verified approval gate
  plan-run          single-pass 7-frame pilot plan (no device I/O;
                    --geometry/--approval/--retained-dir gate expansion;
                    no --runs selector per the single-pass contract)
  locale-totals     print the canonical pinned totals for one locale
  run-session       lease-gated composite owning one device lease for a
                    whole session domain (pinned XOR realtime); the only
                    capture path (task 8.5 removed the temporary v1
                    per-frame verbs prepare/capture/teardown/run-frame and
                    the record-pending-frame verb)
  record-external-frame
                    register a genuine la-* PNG + capture window
                    (no device I/O, no OCR).
                    Session stubs derive bindings from trusted disk
                    (explicit session args verified, --request rejected).
  finalize-run      assemble run-manifest.json (complete|needs-inspection)
                    session-receipt gated; legacy per-frame runs rejected
                    (single pass; the retired finalize-two-runs automatic
                    comparison verb fails closed — human inspection governs
                    manual reruns via preserved semantic hashes)

Real device/simulator operations are lease-gated: without
LIFIO_CAPTURE_LEASE=1 the CLI only plans/validates and never spawns
simctl against a device. iOS lease handoff: main tells when to set it.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import approval as approval_mod
import executor as exec_mod
import inspection as inspection_mod
import output_guard as guard
import preflight as preflight_mod
import request_schema as req
import state_check as state_mod

EXIT_OK = 0
EXIT_INVALID = 2
EXIT_PENDING = 3

LEASE_ENV = "LIFIO_CAPTURE_LEASE"


def _read_json(path: str) -> object:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def cmd_validate_request(args: argparse.Namespace) -> int:
    try:
        obj = req.load_request_file(args.request)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    errs = req.validate_request_dict(obj)
    if errs:
        for e in errs:
            print(f"invalid: {e}", file=sys.stderr)
        return EXIT_INVALID
    print("valid")
    return EXIT_OK


def cmd_write_request(args: argparse.Namespace) -> int:
    try:
        base = req.load_request_file(args.request)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    # Base file carries no frame/mode; the derived per-frame request below
    # is authoritative.
    try:
        derived = req.build_frame_request(base, args.frame)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    errs = req.validate_request_dict(derived)
    if errs:
        for e in errs:
            print(f"invalid: {e}", file=sys.stderr)
        return EXIT_INVALID
    raw = req.canonical_bytes(derived)
    Path(args.out).write_bytes(raw)
    print(req.request_sha256_of_bytes(raw))
    return EXIT_OK


def cmd_make_request(args: argparse.Namespace) -> int:
    try:
        geometry = req.parse_geometry(args.geometry)
        base = req.build_base_request(args.locale, geometry)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    # Probe-validate: every derived per-frame request must pass schema.
    probe = dict(base, frame="track-running", mode=req.MODE_PINNED)
    errs = req.validate_request_dict(probe)
    if errs:
        for e in errs:
            print(f"invalid: {e}", file=sys.stderr)
        return EXIT_INVALID
    raw = req.canonical_bytes(base)
    Path(args.out).write_bytes(raw)
    print(req.request_sha256_of_bytes(raw))
    return EXIT_OK


def cmd_preflight(args: argparse.Namespace) -> int:
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    if not args.device or args.device == "booted":
        print("invalid: explicit simulator UDID required (no 'booted' auto-pick)",
              file=sys.stderr)
        return EXIT_INVALID
    plan = {
        "device_udid": args.device,
        "out_root": str(out_root),
        "snapshot_commands": preflight_mod.snapshot_commands(args.device),
        "apply_commands": preflight_mod.apply_commands(args.device),
        "launch_argv": preflight_mod.launch_argv(args.device),
        "container_doc": "<container-data>/Documents/capture-request.json "
        "(copy ONLY this file via get_app_container data)",
        "restore_policy": (
            "re-apply snapshotted appearance/content_size exactly; "
            "status_bar clear only when session applied the override on a "
            "previously clean list; abort on preexisting overrides"
        ),
        "lock_file": str(guard.lock_path_for(args.device)),
        "unsupported_note": (
            "no locale/timezone/keyboard simctl commands emitted: no confirmed "
            "surface (waiver in evidence-runner.md); app-side request carries them"
        ),
    }
    if args.execute:
        if os.environ.get(LEASE_ENV) != "1":
            print(
                f"refused: --execute requires {LEASE_ENV}=1 (iOS lease not handed over)",
                file=sys.stderr,
            )
            return EXIT_INVALID
        # Lease present: run read-only snapshot queries only in this phase.
        for argv in plan["snapshot_commands"]:
            try:
                proc = subprocess.run(argv, capture_output=True, text=True, timeout=30)
            except (OSError, subprocess.SubprocessError) as exc:
                print(f"snapshot failed for {' '.join(argv)}: {exc}", file=sys.stderr)
                return EXIT_INVALID
            print(f"$ {' '.join(argv)}\n{proc.stdout.strip()}")
        print("snapshot-only execute done; mutating apply deferred to handoff run")
        return EXIT_OK
    print(json.dumps(plan, indent=2))
    return EXIT_OK


def _load_pin(path: str | None) -> dict | None:
    if path is None:
        return None
    try:
        return state_mod.load_pinned_totals(path)
    except state_mod.StateError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        raise _Exit(EXIT_INVALID)


class _Exit(Exception):
    def __init__(self, code: int):
        self.code = code


def _gate_or_block(
    locale: str | None,
    geometry: tuple[int, int] | None,
    approval: str | None,
    retained_dir: str | None,
) -> int | None:
    """Enforce 5.4 expansion gates; prints blocked diagnostics. None when open."""
    gate_errs = approval_mod.gates_for_request(
        locale, geometry, approval, retained_dir,
    )
    if gate_errs:
        for e in gate_errs:
            print(f"blocked: {e}", file=sys.stderr)
        return EXIT_INVALID
    return None


def cmd_check_state(args: argparse.Namespace) -> int:
    try:
        request = req.load_request_file(args.request)
        raw = Path(args.request).read_bytes()
        state = state_mod.load_state_file(args.state)
    except (req.RequestError, state_mod.StateError) as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    blocked = _gate_or_block(
        request.get("locale"), None,
        getattr(args, "approval", None), getattr(args, "retained_dir", None),
    )
    if blocked is not None:
        return blocked
    try:
        pin = _load_pin(args.pinned_totals)
    except _Exit as e:
        return e.code
    # Bind sha to exact request file bytes on disk.
    digest = req.request_sha256_of_bytes(raw)
    verdict, errs = state_mod.validate_state_dict(state, request, digest, pin)
    for e in errs:
        print(f"{verdict}: {e}", file=sys.stderr if verdict == "failed" else sys.stdout)
    if verdict == state_mod.OK:
        print("ready")
        return EXIT_OK
    if verdict == state_mod.PENDING:
        return EXIT_PENDING
    return EXIT_INVALID


def cmd_verify_picker(args: argparse.Namespace) -> int:
    try:
        obj = _read_json(args.inspection)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"invalid: cannot read inspection: {exc}", file=sys.stderr)
        return EXIT_INVALID
    if not isinstance(obj, dict):
        print("invalid: inspection file must contain a JSON object", file=sys.stderr)
        return EXIT_INVALID
    try:
        request = req.load_request_file(args.request)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    kb = request.get("keyboard")
    expected_language = kb.get("language") if isinstance(kb, dict) else None
    if not isinstance(expected_language, str) or not expected_language:
        print("invalid: request carries no keyboard.language to bind against",
              file=sys.stderr)
        return EXIT_INVALID
    errs, evidence = inspection_mod.verify_picker_inspection(
        obj, screenshot_path=args.screenshot, expected_language=expected_language,
    )
    if errs:
        for e in errs:
            print(f"failed: {e}", file=sys.stderr)
        return EXIT_PENDING if "refusing final" in " ".join(errs) else EXIT_INVALID
    print(json.dumps(evidence, indent=2, sort_keys=True))
    return EXIT_OK


def cmd_check_approval(args: argparse.Namespace) -> int:
    errs = approval_mod.gate_kind(args.kind, args.approval, args.retained_dir)
    if errs:
        for e in errs:
            print(f"blocked: {e}", file=sys.stderr)
        return EXIT_INVALID
    print("approval-ok")
    return EXIT_OK


def cmd_plan_run(args: argparse.Namespace) -> int:
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        base = req.load_request_file(args.request)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    # Strip per-frame keys: plan derives them fresh each frame.
    base = {k: v for k, v in base.items() if k not in ("frame", "mode")}
    probe = dict(base)
    probe.update({"frame": "track-running", "mode": req.MODE_PINNED})
    errs = req.validate_request_dict(probe)
    if errs:
        for e in errs:
            print(f"invalid: {e}", file=sys.stderr)
        return EXIT_INVALID
    try:
        geometry = req.parse_geometry(args.geometry)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    gate_errs = approval_mod.gates_for_request(
        base.get("locale"), geometry, args.approval, args.retained_dir,
    )
    if gate_errs:
        for e in gate_errs:
            print(f"blocked: {e}", file=sys.stderr)
        return EXIT_INVALID
    try:
        plan = preflight_mod.plan_run(
            base, list(req.PILOT_FRAMES), args.device, str(out_root),
            args.run_id, geometry=geometry,
        )
    except ValueError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    print(json.dumps({"runs": [plan]}, indent=2))
    return EXIT_OK


def _require_lease() -> int | None:
    if os.environ.get(LEASE_ENV) != "1":
        print(
            f"refused: this verb mutates a simulator and requires {LEASE_ENV}=1 "
            "(iOS lease not handed over)",
            file=sys.stderr,
        )
        return EXIT_INVALID
    return None


def _load_base_request(path: str) -> dict | None:
    try:
        base = req.load_request_file(path)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return None
    return {k: v for k, v in base.items() if k not in ("frame", "mode")}


def _load_frame_stub(run_dir: Path, frame: str) -> dict | None:
    """Trusted on-disk session stub for (run, frame), if session-bound."""
    try:
        obj = json.loads(
            (run_dir / "frames" / f"{frame}.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(obj, dict) or not obj.get("session_nonce"):
        return None
    return obj


def _verify_receipt_covers(run_dir: Path, stub: dict) -> str | None:
    """Require a complete session receipt covering the stub command.

    Returns an error string, or None when covered. A stub without a
    complete covering receipt is stale or foreign: genuine evidence must
    never register onto it.
    """
    nonce = stub.get("session_nonce")
    try:
        receipt = json.loads(
            (run_dir / "sessions" / f"{nonce}.receipt.json").read_text(
                encoding="utf-8"))
    except (OSError, ValueError):
        return (f"no session receipt for nonce {nonce!r}; stub is stale "
                "or foreign")
    if not isinstance(receipt, dict):
        return "session receipt must be a JSON object"
    if receipt.get("status") != "complete":
        return (f"session receipt {receipt.get('status')!r}; stub belongs "
                "to a contaminated session")
    covered = any(
        isinstance(row, dict) and row.get("seq") == stub.get("seq")
        and row.get("frame") == stub.get("frame")
        and row.get("request_sha256") == stub.get("request_sha256")
        for row in (receipt.get("transcript") or []))
    if not covered:
        return "stub command not covered by the session transcript"
    return None


def cmd_record_external_frame(args: argparse.Namespace) -> int:
    """Genuine registration is session-stub-only (task 8.5).

    The v1 file-args path is removed: without a trusted on-disk session
    stub for (run, frame) there is nothing to register onto, with or
    without explicit session args or --request.
    """
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    run_dir = exec_mod.run_dir_for(str(out_root), args.run_id)
    stub = _load_frame_stub(run_dir, args.frame)
    explicit = {
        "session_nonce": getattr(args, "session_nonce", None),
        "session_domain": getattr(args, "session_domain", None),
        "seq": getattr(args, "seq", None),
        "device_key": getattr(args, "device_key", None),
    }
    if stub is None:
        print("invalid: no trusted on-disk session stub for "
              f"{args.frame!r} in run {args.run_id!r} (stale, missing, "
              "or foreign; v1 file-args registration removed)",
              file=sys.stderr)
        return EXIT_INVALID
    return _cmd_record_external_session(args, run_dir, stub, explicit)


def _cmd_record_external_session(args: argparse.Namespace, run_dir: Path,
                                 stub: dict, explicit: dict) -> int:
    """Session genuine registration from trusted stub bindings only.

    No user-inventable metadata: nonce/domain/seq/device_key come from the
    on-disk pending stub; the request payload comes from the staged
    envelope; receipt coverage is required. Explicit session args are
    accepted only when strictly equal to the stub (stale/missing/foreign
    stubs rejected). --request is forbidden here (omit it; the envelope
    is authoritative). The live state file must pass the full
    session-ack validation (integer schema 2 and every binding plus
    transcript and ready checks). --device/--geometry/--run-id must match
    the stub exactly (no re-keying). The validated state is archived per
    frame and its path stored on the export record, without weakening the
    fail-closed checks.
    """
    import session as sess

    for key, value in explicit.items():
        if value is not None and value != stub.get(key):
            print(f"invalid: explicit {key} {value!r} != trusted stub "
                  f"{stub.get(key)!r} (stale or foreign)", file=sys.stderr)
            return EXIT_INVALID
    if getattr(args, "request", None):
        print("invalid: --request is forbidden for session frames "
              "(omit it; nonce/domain/seq/device_key derive from the "
              "trusted stub and the payload from its staged envelope)",
              file=sys.stderr)
        return EXIT_INVALID
    nonce = stub["session_nonce"]
    try:
        env = json.loads((run_dir / "requests" / f"session-{nonce}-"
                          f"{stub['seq']}-{args.frame}.envelope.json")
                         .read_bytes().decode("utf-8"))
    except (OSError, ValueError, UnicodeError) as exc:
        print(f"invalid: staged envelope unreadable: {exc}", file=sys.stderr)
        return EXIT_INVALID
    env_errs = sess.validate_envelope(env)
    if env_errs:
        print(f"invalid: staged envelope rejected: {env_errs[0]}",
              file=sys.stderr)
        return EXIT_INVALID
    for key in ("run_id", "session_nonce", "session_domain", "seq",
                "frame", "mode", "request_sha256"):
        if env.get(key) != stub.get(key):
            print(f"invalid: envelope {key} != trusted stub "
                  "(stale or foreign command)", file=sys.stderr)
            return EXIT_INVALID
    receipt_err = _verify_receipt_covers(run_dir, stub)
    if receipt_err is not None:
        print(f"invalid: {receipt_err}", file=sys.stderr)
        return EXIT_INVALID
    try:
        inner = sess.parse_envelope_payload(env)
    except sess.SessionError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        pin = _load_pin(args.pinned_totals)
    except _Exit as e:
        return e.code
    try:
        state = state_mod.load_state_file(args.state)
    except state_mod.StateError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    # Full-tuple state validation: integer schema 2 plus ALL of nonce,
    # run, domain, seq, frame, mode, hash, and transcript coverage, plus
    # the payload-level ready checks. A raw v1 state (no session
    # identity) or any unsupported shape fails here even when its
    # sha/frame happen to match — sha/frame alone are insufficient
    # because the cross-session nonce is excluded from the payload hash.
    verdict, verdict_errs = state_mod.validate_session_ack(state, env, pin)
    if verdict != state_mod.OK:
        print(f"invalid: live state rejected ({verdict}): "
              f"{'; '.join(verdict_errs) or 'not ready'}", file=sys.stderr)
        return EXIT_INVALID
    # CLI-supplied provenance must match the trusted stub exactly:
    # external registration can never re-key device, geometry, or run.
    if args.device != stub.get("device_udid"):
        print(f"invalid: --device {args.device!r} != trusted stub device "
              f"{stub.get('device_udid')!r} (re-keying refused)",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        geometry = req.parse_geometry(args.geometry)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    stub_geo = stub.get("geometry") or {}
    if (geometry[0], geometry[1]) != (stub_geo.get("width"),
                                      stub_geo.get("height")):
        print(f"invalid: --geometry {geometry[0]}x{geometry[1]} != "
              f"trusted stub geometry (re-keying refused)", file=sys.stderr)
        return EXIT_INVALID
    if args.run_id != stub.get("run_id"):
        print(f"invalid: --run-id {args.run_id!r} != trusted stub run "
              f"{stub.get('run_id')!r} (stale or foreign)", file=sys.stderr)
        return EXIT_INVALID
    blocked = _gate_or_block(
        inner.get("locale"), geometry,
        getattr(args, "approval", None), getattr(args, "retained_dir", None),
    )
    if blocked is not None:
        return blocked
    try:
        archived_rel = _archive_state_file(run_dir, args.frame, args.state)
    except OSError as exc:
        print(f"invalid: cannot archive trusted state: {exc}",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        record = exec_mod.record_external_frame(
            run_dir=run_dir,
            frame=args.frame, png_src=args.png,
            captured_at_iso=args.captured_at,
            state=state, request=inner,
            request_sha256=env["request_sha256"],
            pinned_totals=pin, expected_geometry=geometry,
            device_udid=args.device,
            mask=getattr(args, "mask", None),
            session_binding={"session_nonce": stub["session_nonce"],
                             "session_domain": stub["session_domain"],
                             "seq": stub["seq"]},
            device_key=stub.get("device_key"),
            state_archive=archived_rel,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        return EXIT_INVALID
    print(json.dumps(record, indent=2, sort_keys=True))
    return EXIT_OK


def _archive_state_file(run_dir: Path, frame: str, src: str) -> str:
    """Keep the validated live state per frame (audit copy).

    Returns the run-relative POSIX path stored on the export record. When
    the source already lives inside the run dir it is referenced as-is
    (never copied onto itself); otherwise its exact bytes are archived
    under states/. Fail-closed checks that admitted the state are never
    weakened by this bookkeeping.
    """
    dest_dir = run_dir / "states"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{frame}.capture-state.json"
    src_path = Path(src).expanduser()
    try:
        if src_path.resolve() == dest.resolve():
            return str(dest.relative_to(run_dir).as_posix())
    except OSError:
        pass
    try:
        if src_path.resolve().is_relative_to(run_dir.resolve()):
            return str(src_path.resolve().relative_to(
                run_dir.resolve()).as_posix())
    except (OSError, ValueError):
        pass
    dest.write_bytes(src_path.read_bytes())
    return str(dest.relative_to(run_dir).as_posix())


def cmd_finalize_run(args: argparse.Namespace) -> int:
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    provenance = None
    if args.provenance is not None:
        try:
            provenance = json.loads(Path(args.provenance).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"invalid: cannot read provenance: {exc}", file=sys.stderr)
            return EXIT_INVALID
        if not isinstance(provenance, dict):
            print("invalid: provenance file must contain a JSON object",
                  file=sys.stderr)
            return EXIT_INVALID
    try:
        manifest, pending = exec_mod.finalize_run(
            exec_mod.run_dir_for(str(out_root), args.run_id),
            provenance=provenance,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        return EXIT_INVALID
    print(json.dumps(manifest, indent=2, sort_keys=True))
    if pending:
        for p in pending:
            print(f"needs-inspection: {p}", file=sys.stderr)
        return EXIT_PENDING
    return EXIT_OK


def cmd_run_session(args: argparse.Namespace) -> int:
    """Lease-gated composite owning one device lease for a whole session.

    Runs a single frozen-v2 domain (pinned XOR realtime): sequential
    locales and the two domains per locale are composed by the
    workflow wrapper, which then calls the existing finalize-run.
    The device lock is held inside run_session across
    all frame commands of this session (never pre-acquired here).

    With --hold-open (realtime only), the session stays RUNNING with its
    verified anchor after the frame loop while the live-capture driver
    runs the button dance (consent grant, Home/compact re-probe, powerx2
    lock capture); the explicit session cleanup finishes it. Bounded by
    the existing POLL/CLEANUP-scale hold window; no deadline increases.
    """
    if args.hold_open and args.domain != "realtime":
        print("invalid: --hold-open is realtime-only "
              "(pinned sessions end immediately after export)",
              file=sys.stderr)
        return EXIT_INVALID
    refused = _require_lease()
    if refused is not None:
        return refused
    if not args.device or args.device == "booted":
        print("invalid: explicit simulator UDID required (no 'booted' auto-pick)",
              file=sys.stderr)
        return EXIT_INVALID
    if not args.device_key:
        print("invalid: --device-key is required "
              "(iphone69|iphone63|ipad13; validated against the catalog)",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    base = _load_base_request(args.request)
    if base is None:
        return EXIT_INVALID
    try:
        pin = _load_pin(args.pinned_totals)
    except _Exit as e:
        return e.code
    if pin is None:
        print("invalid: --pinned-totals is required for session capture "
              "(ready refused without an independently pinned dictionary)",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        geometry = req.parse_geometry(args.geometry)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    blocked = _gate_or_block(
        base.get("locale"), geometry,
        getattr(args, "approval", None), getattr(args, "retained_dir", None),
    )
    if blocked is not None:
        return blocked
    island = getattr(args, "island", None)
    island_available = None
    if island is not None:
        if island not in ("1", "0"):
            print("invalid: --island must be '1' or '0' when given",
                  file=sys.stderr)
            return EXIT_INVALID
        island_available = island == "1"
    run_dir = exec_mod.run_dir_for(str(out_root), args.run_id)
    hid = exec_mod.ArgentHidBackend(args.device) if args.hold_open else None
    try:
        summary = exec_mod.run_session(
            exec_mod.default_run, args.device, base, args.domain, run_dir,
            device_key=args.device_key, bid=args.bid, pinned_totals=pin,
            geometry=geometry, island_available=island_available,
            timeout_s=args.timeout, interval_s=args.interval,
            hold_open=args.hold_open, hid=hid,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        return EXIT_INVALID
    print(json.dumps(summary, indent=2, sort_keys=True))
    return EXIT_OK


def cmd_locale_totals(args: argparse.Namespace) -> int:
    """Print the canonical pinned totals for one locale (no device I/O)."""
    try:
        totals = req.load_pinned_totals_for_locale(args.locale)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    if args.out:
        Path(args.out).write_text(
            json.dumps(totals, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(args.out)
        return EXIT_OK
    print(json.dumps(totals, sort_keys=True, separators=(",", ":"),
                     ensure_ascii=False))
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="capture.py", description="Pilot capture runner (lease-gated)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("validate-request")
    p.add_argument("--request", required=True)
    p.set_defaults(fn=cmd_validate_request)

    p = sub.add_parser("write-request")
    p.add_argument("--request", required=True)
    p.add_argument("--frame", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(fn=cmd_write_request)

    p = sub.add_parser("make-request")
    p.add_argument("--locale", required=True,
                   choices=list(req.KNOWN_LOCALES))
    p.add_argument("--geometry", required=False, default="1320x2868",
                   help="WxH; must be a supported matrix size")
    p.add_argument("--out", required=True)
    p.set_defaults(fn=cmd_make_request)

    p = sub.add_parser("preflight")
    p.add_argument("--device", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--request", required=False, default=None)
    p.add_argument("--execute", action="store_true")
    p.set_defaults(fn=cmd_preflight)

    p = sub.add_parser("check-state")
    p.add_argument("--request", required=True)
    p.add_argument("--state", required=True)
    p.add_argument("--pinned-totals", required=False, default=None)
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-English requests)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.set_defaults(fn=cmd_check_state)

    p = sub.add_parser("verify-picker")
    p.add_argument("--inspection", required=True)
    p.add_argument("--screenshot", required=True)
    p.add_argument("--request", required=True)
    p.set_defaults(fn=cmd_verify_picker)

    p = sub.add_parser("check-approval")
    p.add_argument("--kind", required=True,
                   choices=["pilot", "ipad", "non-english", "montage"])
    p.add_argument("--approval", required=False, default=None)
    p.add_argument("--retained-dir", required=False, default=None)
    p.set_defaults(fn=cmd_check_approval)

    p = sub.add_parser("plan-run")
    p.add_argument("--request", required=True)
    p.add_argument("--device", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--geometry", required=False, default="1320x2868",
                   help="WxH; non-pilot matrix sizes require 5.4 ipad approval")
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-English/iPad plans)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.set_defaults(fn=cmd_plan_run)

    p = sub.add_parser("record-external-frame")
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--frame", required=True)
    p.add_argument("--png", required=True)
    p.add_argument("--captured-at", required=True)
    p.add_argument("--state", required=True)
    p.add_argument("--session-nonce", required=False, default=None,
                   help="session frames only; must match the trusted stub")
    p.add_argument("--session-domain", required=False, default=None,
                   choices=["pinned", "realtime"],
                   help="session frames only; must match the trusted stub")
    p.add_argument("--seq", required=False, default=None, type=int,
                   help="session frames only; must match the trusted stub")
    p.add_argument("--device-key", required=False, default=None,
                   help="session frames only; must match the trusted stub")
    p.add_argument("--pinned-totals", required=False, default=None)
    p.add_argument("--geometry", required=False, default="1320x2868")
    p.add_argument("--device", required=False, default="unknown")
    p.add_argument("--mask", required=False, default=None,
                   choices=["default", "black"],
                   help="external capture mask policy (default: per-frame; "
                        "la-compact/la-expanded require --mask=black)")
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-English/iPad frames)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.set_defaults(fn=cmd_record_external_frame)

    p = sub.add_parser("finalize-run")
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--provenance", required=False, default=None,
                   help="JSON file {commit_base: str, dirty: bool}")
    p.set_defaults(fn=cmd_finalize_run)

    p = sub.add_parser("run-session")
    p.add_argument("--device", required=True)
    p.add_argument("--device-key", required=True,
                   help="catalog key (iphone69|iphone63|ipad13); geometry and "
                        "island expectation are validated against it")
    p.add_argument("--request", required=True, help="base request file")
    p.add_argument("--domain", required=True,
                   choices=["pinned", "realtime"])
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--geometry", required=False, default="1320x2868")
    p.add_argument("--pinned-totals", required=True)
    p.add_argument("--island", required=False, default=None,
                   choices=["1", "0"],
                   help="explicit island token; must agree with --device-key")
    p.add_argument("--bid", required=False, default=req.SCREENSHOT_BID)
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-English/iPad runs)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.add_argument("--timeout", type=float, default=exec_mod.POLL_TIMEOUT_S)
    p.add_argument("--interval", type=float, default=exec_mod.POLL_INTERVAL_S)
    p.add_argument("--hold-open", action="store_true",
                   help="realtime only: hold the session RUNNING with its "
                        "verified anchor for the live-capture button dance "
                        "(consent, compact re-probe, lock capture) before "
                        "the explicit session cleanup")
    p.set_defaults(fn=cmd_run_session)

    p = sub.add_parser("locale-totals")
    p.add_argument("--locale", required=True,
                   choices=["en", "ru", "zh-Hans", "es-419", "pt-BR"])
    p.add_argument("--out", required=False, default=None)
    p.set_defaults(fn=cmd_locale_totals)

    return ap


def main(argv: list[str] | None = None) -> int:
    ap = build_parser()
    args = ap.parse_args(argv)
    return int(args.fn(args))


if __name__ == "__main__":
    raise SystemExit(main())
