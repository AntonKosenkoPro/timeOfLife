#!/usr/bin/env python3
"""Pilot capture CLI (runner side, stdlib only).

Subcommands (validation/gate/execution CLI; nothing auto-approves):
  validate-request  fail-closed request check (exit 0 valid, 2 invalid)
  write-request     derive per-frame request file (deterministic bytes+sha)
  preflight         plan simctl argv + guards (dry-run default; --execute
                    requires LIFIO_CAPTURE_LEASE=1 and touches one device)
  check-state       validate app capture-state.json against the request
                    (+ optional --pinned-totals; ready refused without a pin)
  verify-la         validate human-supplied LA timer observation (±2s, hash-bound)
  verify-picker     require picker keyboard inspection artifact (hash+language bound)
  check-approval    hash/file-verified approval gate
  plan-run          full 7-frame pilot plan for two runs (no device I/O;
                    --geometry/--approval/--retained-dir gate expansion)
  locale-totals     print the canonical pinned totals for one locale
  prepare-frame     lease-gated: stage request, apply chrome, launch, poll ready
  capture-app-frame lease-gated: native export for app-clock frames after ready
  record-external-frame
                    register a genuine la-* PNG + capture window
                    (no device I/O; observation-bound, no OCR)
  finalize-run      assemble run-manifest.json (complete|needs-inspection)
  finalize-two-runs semantic comparison of two runs (never byte-equal PNGs)
  teardown-frame    lease-gated: exact chrome restore + terminate from the
                    frame's own session; persists a partial teardown record
                    (app hook pending core)
  run-frame         lease-gated composite holding one device lock across
                    prepare -> capture (auto-teardown) for one app-clock frame

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
import run_manifest as manifest_mod
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


def cmd_verify_la(args: argparse.Namespace) -> int:
    try:
        state = state_mod.load_state_file(args.state)
    except state_mod.StateError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    la = state.get("live_activity") if isinstance(state, dict) else None
    if not isinstance(la, dict):
        print("needs-inspection: live_activity block missing from state",
              file=sys.stderr)
        return EXIT_PENDING
    observation = None
    if args.observation is not None:
        try:
            observation = json.loads(Path(args.observation).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"invalid: cannot read observation: {exc}", file=sys.stderr)
            return EXIT_INVALID
        if not isinstance(observation, dict):
            print("invalid: observation file must contain a JSON object",
                  file=sys.stderr)
            return EXIT_INVALID
    errs = inspection_mod.verify_la_observation(
        la, args.screenshot, args.captured_at, observation,
    )
    if errs:
        first = errs[0]
        code = EXIT_PENDING if ("needs-inspection" in first or "missing" in first) else EXIT_INVALID
        for e in errs:
            print(f"failed: {e}", file=sys.stderr)
        return code
    print("la-observation-valid")
    return EXIT_OK


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
        plans = [
            preflight_mod.plan_run(
                base, list(req.PILOT_FRAMES), args.device, str(out_root),
                f"{args.run_id}-r{i+1}", geometry=geometry,
            )
            for i in range(args.runs)
        ]
    except ValueError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    if args.runs != 2:
        print("invalid: pilot requires exactly two full runs", file=sys.stderr)
        return EXIT_INVALID
    print(json.dumps({"runs": plans}, indent=2))
    return EXIT_OK


def _release_lock(lock_path, run_id: str) -> bool:
    """Release the device lock; False (with diagnostic) when it fails."""
    try:
        guard.release_lock(lock_path, run_id)
    except guard.GuardError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        return False
    return True


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


def cmd_prepare_frame(args: argparse.Namespace) -> int:
    refused = _require_lease()
    if refused is not None:
        return refused
    if not args.device or args.device == "booted":
        print("invalid: explicit simulator UDID required (no 'booted' auto-pick)",
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
    blocked = _gate_or_block(
        base.get("locale"), None,
        getattr(args, "approval", None), getattr(args, "retained_dir", None),
    )
    if blocked is not None:
        return blocked
    try:
        pin = _load_pin(args.pinned_totals)
    except _Exit as e:
        return e.code
    try:
        lock_path = guard.acquire_lock(args.device, args.run_id)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        session = exec_mod.prepare_frame(
            exec_mod.default_run, args.device, base, args.frame,
            exec_mod.run_dir_for(str(out_root), args.run_id),
            bid=args.bid, pinned_totals=pin,
            timeout_s=args.timeout, interval_s=args.interval,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        _release_lock(lock_path, args.run_id)
        return EXIT_INVALID
    if _release_lock(lock_path, args.run_id):
        print(json.dumps(session, indent=2, sort_keys=True))
        return EXIT_OK
    return EXIT_INVALID


def cmd_capture_app_frame(args: argparse.Namespace) -> int:
    refused = _require_lease()
    if refused is not None:
        return refused
    if not args.device or args.device == "booted":
        print("invalid: explicit simulator UDID required (no 'booted' auto-pick)",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        geometry = req.parse_geometry(args.geometry)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    blocked = _gate_or_block(
        None, geometry,
        getattr(args, "approval", None), getattr(args, "retained_dir", None),
    )
    if blocked is not None:
        return blocked
    try:
        lock_path = guard.acquire_lock(args.device, args.run_id)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        record = exec_mod.capture_app_frame(
            exec_mod.default_run, args.device,
            exec_mod.run_dir_for(str(out_root), args.run_id),
            args.frame, expected_geometry=geometry,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        _release_lock(lock_path, args.run_id)
        return EXIT_INVALID
    if _release_lock(lock_path, args.run_id):
        print(json.dumps(record, indent=2, sort_keys=True))
        return EXIT_OK
    return EXIT_INVALID


def cmd_record_external_frame(args: argparse.Namespace) -> int:
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        request = req.load_request_file(args.request)
        raw = Path(args.request).read_bytes()
        state = state_mod.load_state_file(args.state)
    except (req.RequestError, state_mod.StateError) as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        pin = _load_pin(args.pinned_totals)
    except _Exit as e:
        return e.code
    try:
        geometry = req.parse_geometry(args.geometry)
    except req.RequestError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    blocked = _gate_or_block(
        request.get("locale"), geometry,
        getattr(args, "approval", None), getattr(args, "retained_dir", None),
    )
    if blocked is not None:
        return blocked
    try:
        record = exec_mod.record_external_frame(
            run_dir=exec_mod.run_dir_for(str(out_root), args.run_id),
            frame=args.frame, png_src=args.png,
            captured_at_iso=args.captured_at,
            observation_path=args.observation, state=state, request=request,
            request_sha256=req.request_sha256_of_bytes(raw),
            pinned_totals=pin, expected_geometry=geometry,
            device_udid=args.device,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        return EXIT_INVALID
    print(json.dumps(record, indent=2, sort_keys=True))
    return EXIT_OK


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


def cmd_finalize_two_runs(args: argparse.Namespace) -> int:
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    manifests = []
    for suffix in ("-r1", "-r2"):
        path = exec_mod.run_dir_for(
            str(out_root), args.run_id_base + suffix) / "run-manifest.json"
        try:
            manifests.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"invalid: cannot read {path}: {exc}", file=sys.stderr)
            return EXIT_INVALID
    res = manifest_mod.compare_runs(manifests[0], manifests[1])
    reviewed: set[str] = set()
    if args.variance_review is not None:
        try:
            review = json.loads(Path(args.variance_review).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"invalid: cannot read variance review: {exc}", file=sys.stderr)
            return EXIT_INVALID
        if not isinstance(review, dict):
            print("invalid: variance review must be an object", file=sys.stderr)
            return EXIT_INVALID
        for frame, entry in review.items():
            if not isinstance(entry, dict) or not entry.get("reviewer") or not entry.get("date"):
                print(f"invalid: variance review for {frame!r} needs reviewer+date",
                      file=sys.stderr)
                return EXIT_INVALID
            reviewed.add(frame)
    unreviewed = [f for f in res["unreviewed_variance"] if f not in reviewed]
    verdict = {
        "run_id_base": args.run_id_base,
        "errors": res["errors"],
        "unreviewed_variance": unreviewed,
        "reviewed_variance": sorted(reviewed & set(res["unreviewed_variance"])),
        "provenance": [m.get("provenance") for m in manifests],
        "status": "complete" if not res["errors"] and not unreviewed else (
            "failed" if res["errors"] else "needs-inspection"),
    }
    print(json.dumps(verdict, indent=2, sort_keys=True))
    if res["errors"]:
        return EXIT_INVALID
    return EXIT_OK if not unreviewed else EXIT_PENDING


def cmd_teardown_frame(args: argparse.Namespace) -> int:
    refused = _require_lease()
    if refused is not None:
        return refused
    if not args.device or args.device == "booted":
        print("invalid: explicit simulator UDID required (no 'booted' auto-pick)",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        out_root = guard.ensure_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        lock_path = guard.acquire_lock(args.device, args.run_id)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        record = exec_mod.teardown_frame(
            exec_mod.default_run, args.device,
            exec_mod.run_dir_for(str(out_root), args.run_id),
            args.frame, bid=args.bid,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        _release_lock(lock_path, args.run_id)
        return EXIT_INVALID
    ok = _release_lock(lock_path, args.run_id)
    print(json.dumps(record, indent=2, sort_keys=True))
    if record.get("status") != "partial":
        for f in record.get("failures", []):
            print(f"failed: {f}", file=sys.stderr)
        return EXIT_INVALID
    return EXIT_OK if ok else EXIT_INVALID


def cmd_run_frame(args: argparse.Namespace) -> int:
    """Composite holding one device lock across prepare/capture/teardown."""
    refused = _require_lease()
    if refused is not None:
        return refused
    if not args.device or args.device == "booted":
        print("invalid: explicit simulator UDID required (no 'booted' auto-pick)",
              file=sys.stderr)
        return EXIT_INVALID
    if args.frame in req.LA_FRAMES:
        print("invalid: run-frame serves app-clock frames only; "
              "la-* frames use prepare-frame + record-external-frame + "
              "teardown-frame", file=sys.stderr)
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
    run_dir = exec_mod.run_dir_for(str(out_root), args.run_id)
    try:
        lock_path = guard.acquire_lock(args.device, args.run_id)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    code = EXIT_OK
    try:
        exec_mod.prepare_frame(
            exec_mod.default_run, args.device, base, args.frame, run_dir,
            bid=args.bid, pinned_totals=pin,
            timeout_s=args.timeout, interval_s=args.interval,
        )
        record = exec_mod.capture_app_frame(
            exec_mod.default_run, args.device, run_dir, args.frame,
            expected_geometry=geometry, auto_teardown=True, bid=args.bid,
        )
    except exec_mod.FrameError as exc:
        print(f"failed: {exc}", file=sys.stderr)
        code = EXIT_INVALID
    else:
        print(json.dumps(record, indent=2, sort_keys=True))
    if not _release_lock(lock_path, args.run_id):
        code = EXIT_INVALID
    return code


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

    p = sub.add_parser("verify-la")
    p.add_argument("--state", required=True)
    p.add_argument("--screenshot", required=True)
    p.add_argument("--captured-at", required=True)
    p.add_argument("--observation", required=False, default=None)
    p.set_defaults(fn=cmd_verify_la)

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
    p.add_argument("--runs", type=int, default=2)
    p.add_argument("--geometry", required=False, default="1320x2868",
                   help="WxH; non-pilot matrix sizes require 5.4 ipad approval")
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-English/iPad plans)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.set_defaults(fn=cmd_plan_run)

    p = sub.add_parser("prepare-frame")
    p.add_argument("--device", required=True)
    p.add_argument("--request", required=True, help="base request (pilot_manifest.json)")
    p.add_argument("--frame", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--bid", required=False, default=req.SCREENSHOT_BID)
    p.add_argument("--pinned-totals", required=False, default=None)
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-English requests)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.add_argument("--timeout", type=float, default=exec_mod.POLL_TIMEOUT_S)
    p.add_argument("--interval", type=float, default=exec_mod.POLL_INTERVAL_S)
    p.set_defaults(fn=cmd_prepare_frame)

    p = sub.add_parser("capture-app-frame")
    p.add_argument("--device", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--frame", required=True)
    p.add_argument("--geometry", required=False, default="1320x2868")
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-pilot geometries)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.set_defaults(fn=cmd_capture_app_frame)

    p = sub.add_parser("record-external-frame")
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--frame", required=True)
    p.add_argument("--png", required=True)
    p.add_argument("--captured-at", required=True)
    p.add_argument("--observation", required=True)
    p.add_argument("--state", required=True)
    p.add_argument("--request", required=True)
    p.add_argument("--pinned-totals", required=False, default=None)
    p.add_argument("--geometry", required=False, default="1320x2868")
    p.add_argument("--device", required=False, default="unknown")
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

    p = sub.add_parser("finalize-two-runs")
    p.add_argument("--out", required=True)
    p.add_argument("--run-id-base", required=True)
    p.add_argument("--variance-review", required=False, default=None)
    p.set_defaults(fn=cmd_finalize_two_runs)

    p = sub.add_parser("teardown-frame")
    p.add_argument("--device", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--frame", required=True)
    p.add_argument("--bid", required=False, default=req.SCREENSHOT_BID)
    p.set_defaults(fn=cmd_teardown_frame)

    p = sub.add_parser("run-frame")
    p.add_argument("--device", required=True)
    p.add_argument("--request", required=True, help="base request (pilot_manifest.json)")
    p.add_argument("--frame", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--bid", required=False, default=req.SCREENSHOT_BID)
    p.add_argument("--pinned-totals", required=False, default=None)
    p.add_argument("--geometry", required=False, default="1320x2868")
    p.add_argument("--approval", required=False, default=None,
                   help="5.4 approval file (required for non-English/iPad frames)")
    p.add_argument("--retained-dir", required=False, default=None)
    p.add_argument("--timeout", type=float, default=exec_mod.POLL_TIMEOUT_S)
    p.add_argument("--interval", type=float, default=exec_mod.POLL_INTERVAL_S)
    p.set_defaults(fn=cmd_run_frame)

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
