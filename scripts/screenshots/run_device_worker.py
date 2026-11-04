#!/usr/bin/env python3
"""Device-worker outer loop (workflow side, stdlib only).

Owns the outer loop + statuses for ONE device worker: selected locales
in order, a SINGLE automated pass per locale, pinned session then
realtime session per pass via the frozen `capture.py run-session` CLI,
then the existing `finalize-run`. Per-locale request/totals files come
from the existing `make-request` / `locale-totals` verbs, so deck and
treatment policies stay with the runner CLI, not here. There is no
automatic second pass and no automatic pass comparison: a manual rerun
re-invokes this same single-pass flow with a FRESH invocation identity
(see below), and human inspection compares across reruns.

Layout contract (`--out` is the shots ROOT): every session/finalize
verb for a locale runs with `--out shots/<device>/<locale>` (via
wa.locale_artifact_dir), so each locale artifact is independently
uploadable with `runs/<run-id>/run-manifest.json` exactly where the
panels packaging harvest reads it. Requests/diagnostics live inside
their locale dir; the device-wide `worker-summary.json` lives at the
device root (`shots/<device>/`), never inside one locale artifact.

Explicitly NOT owned here (YAML worker steps do them once per worker):
simulator create/boot/install/delete. No `simctl` string appears in
this module. The normal Screenshot build always happens in the build
job; the `--provenance` file it produces is only forwarded to
`finalize-run`. Manifest pins (Xcode/sdk build IDs via
build_artifact) wire into that provenance file in later 6.2
integration — this worker never interprets provenance.

Lease: `LIFIO_CAPTURE_LEASE=1` must be present in this process;
it is passed explicitly to every child. Without it the worker
refuses to drive any session.

Outcome contract: `finalize-run` rc 3 is honest needs-inspection
(status ok with a note, work continues); any other nonzero child rc,
or a launch OSError/timeout, is fatal session failure. A fatal
failure contaminates the worker: the current pass is failed, every
later pair is unattempted, earlier artifacts are preserved (never
deleted), and the worker stops. `--cancel-file` presence stops
cleanly with unattempted statuses.

Run identity: every execute() mints one fresh invocation identifier
(`uuid4` hex, or an explicit `--invocation-id` that must match the
strict run-id shape) and namespaces the locale run id as
`<device>-<locale>-r1-<invocation>`. A hardcoded `device-locale-r1`
alone cannot distinguish a manual rerun from the original, so status
records and `runs/<run-id>/` manifests always carry the exact actual
run id, and exactly one manifest lands per clean pair output for the
packaging harvest to discover (never a hardcoded run id to guess).
Reused output is refused: a locale cell holding ANY prior content
(statuses, runs/, requests, diagnostics, foreign files, symlinks)
belongs to a previous invocation and fails the worker closed instead
of being silently overwritten or merged with history.

Interruption boundary: KeyboardInterrupt is converted to
failed/unattempted statuses plus a best-effort summary, then
re-raised so the process still exits abnormally. SIGTERM handling is
not implemented here; forced runner/host termination may leave
missing receipts, so evidence stays incomplete, affected pairs read
as incomplete, and the runner `finally` owns simulator cleanup. A
summary that cannot be written fails visibly (never converts failure
to success); the status files on disk stay authoritative.

Capacity honesty: describe_capacity() only counts workers vs slots;
actual GitHub queueing is observed on the run page, never proven here.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import output_guard as guard
import workflow_artifacts as wa
import workflow_inputs as wi

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_INVALID = 2
EXIT_CANCELLED = 4

LEASE_ENV = "LIFIO_CAPTURE_LEASE"
MAX_PARALLEL_DEFAULT = 5
# Single automated pass per device-locale (owner decision 2026-11-04,
# §9): the tuple lives in workflow_inputs (selection/catalog
# authority); this module never defines its own.
DOMAINS = ("pinned", "realtime")


def describe_capacity(devices: list, max_parallel: int = MAX_PARALLEL_DEFAULT
                      ) -> dict:
    """Count device workers against slots. Honest labeling only: excess
    workers queue on GitHub runners; actual queueing is observed on the
    run page, not proven here."""
    devices = list(devices)
    excess = max(0, len(devices) - max_parallel)
    return {
        "worker_count": len(devices),
        "max_parallel": max_parallel,
        "excess": excess,
        "note": ("GitHub queues device workers beyond max-parallel slots; "
                 "actual queueing is observed on the run page, "
                 "not proven here."),
    }


def default_capture_py() -> Path:
    return HERE / "capture.py"


def make_request_argv(capture_py: Path, locale: str, geometry: str,
                      out: Path) -> list[str]:
    return [sys.executable, str(capture_py), "make-request",
            "--locale", locale, "--geometry", geometry, "--out", str(out)]


def totals_argv(capture_py: Path, locale: str, out: Path) -> list[str]:
    return [sys.executable, str(capture_py), "locale-totals",
            "--locale", locale, "--out", str(out)]


def session_argv(capture_py: Path, *, device: str, device_key: str,
                 request: Path, domain: str, out: Path, run_id: str,
                 geometry: str, pinned_totals: Path, island: str,
                 approval: str | None = None,
                 retained_dir: str | None = None) -> list[str]:
    argv = [sys.executable, str(capture_py), "run-session",
            "--device", device, "--device-key", device_key,
            "--request", str(request), "--domain", domain,
            "--out", str(out), "--run-id", run_id,
            "--geometry", geometry, "--pinned-totals", str(pinned_totals),
            "--island", island]
    if approval is not None or retained_dir is not None:
        # Callers pass both or neither (validated in execute); a lone
        # flag here would silently weaken the gate, so refuse instead.
        if approval is None or retained_dir is None:
            raise ValueError(
                "approval pair incomplete: --approval and --retained-dir "
                "must travel together")
        argv += ["--approval", approval, "--retained-dir", retained_dir]
    return argv


def finalize_argv(capture_py: Path, out: Path, run_id: str,
                  provenance: str | None = None) -> list[str]:
    argv = [sys.executable, str(capture_py), "finalize-run",
            "--out", str(out), "--run-id", run_id]
    if provenance is not None:
        argv += ["--provenance", provenance]
    return argv


def default_run(argv: list[str], env: dict) -> object:
    return subprocess.run(argv, capture_output=True, text=True, env=env)


def _stderr_tail(proc: object, limit: int = 300) -> str:
    err = getattr(proc, "stderr", "") or ""
    return " ".join(err.strip().split())[-limit:]


def execute(*, device_key: str, device_udid: str, locales: list[str],
            out_dir: Path, capture_py: Path,
            provenance: str | None = None,
            cancel_file: str | None = None,
            approval: str | None = None,
            retained_dir: str | None = None,
            invocation_id: str | None = None,
            run=default_run, env: dict | None = None) -> tuple[int, dict]:
    """Run one device worker over a shots root. Returns (exit_code,
    summary). Pure subprocess-driven; inject `run`/`env` for
    deterministic tests.

    `invocation_id` namespaces this run (manual reruns MUST arrive
    with a fresh one — a bare device-locale-r1 cannot tell reruns
    apart). When None, a fresh uuid4-hex id is minted per call, so
    two execute() calls never share run identities by accident.
    """
    child_env = dict(os.environ if env is None else env)
    shots_root = Path(out_dir)
    capture_py = Path(capture_py)
    try:
        invocation = (wa.validate_run_id(invocation_id)
                      if invocation_id is not None
                      else uuid.uuid4().hex[:12])
    except wa.ArtifactError as exc:
        return (EXIT_INVALID,
                {"device": device_key, "locales": list(locales),
                 "pairs": {}, "canonical_pairs": [],
                 "effective_complete": False, "cancelled": False,
                 "invocation_id": None,
                 "error": f"invalid invocation id: {exc}"})
    summary: dict = {"device": device_key, "locales": list(locales),
                     "pairs": {}, "canonical_pairs": [],
                     "effective_complete": False, "cancelled": False,
                     "invocation_id": invocation,
                     "error": ""}
    records: list[dict] = []
    done: set[tuple[str, str]] = set()
    device_dir = shots_root / device_key if isinstance(device_key, str) \
        else shots_root

    def locale_dir(locale: str) -> Path:
        return wa.locale_artifact_dir(shots_root, device_key, locale)

    def run_id_for(locale: str, pass_name: str) -> str:
        return f"{device_key}-{locale}-{pass_name}-{invocation}"

    def emit(locale: str, pass_name: str, status: str, reason: str,
             run_id: str | None = None) -> dict:
        rec = wa.status_record(device=device_key, locale=locale,
                               pass_name=pass_name, status=status,
                               reason=reason,
                               run_id=run_id or run_id_for(locale,
                                                           pass_name))
        wa.write_status(locale_dir(locale), rec)
        records.append(rec)
        done.add((locale, pass_name))
        pair = summary["pairs"].setdefault(
            locale, {p: None for p in wi.PASSES})
        pair[pass_name] = status
        return rec

    def stop_remaining(reason: str) -> None:
        for loc in locales:
            for p in wi.PASSES:
                if (loc, p) not in done:
                    emit(loc, p, wa.STATUS_UNATTEMPTED, reason)

    def finish(code: int) -> tuple[int, dict]:
        try:
            canonical = wa.worker_summary(device_key, locales, records)
            summary["canonical_pairs"] = canonical["pairs"]
        except wa.ArtifactError as exc:
            summary["canonical_pairs"] = []
            summary["error"] = (summary["error"]
                                or f"canonical summary failed: {exc}")
        summary["effective_complete"] = (
            bool(summary["canonical_pairs"])
            and all(p.get("complete")
                    for p in summary["canonical_pairs"]))
        try:
            device_dir.mkdir(parents=True, exist_ok=True)
            (device_dir / "worker-summary.json").write_text(
                json.dumps(summary, sort_keys=True, indent=2,
                           ensure_ascii=False) + "\n", encoding="utf-8")
        except OSError as exc:
            summary["error"] = (summary["error"]
                                or f"worker-summary unwritable: {exc}; "
                                "status files on disk are authoritative")
            if code == EXIT_OK:
                code = EXIT_FAILED
        return code, summary

    def cancelled() -> bool:
        return bool(cancel_file) and Path(cancel_file).exists()

    def fail_closed(code: int, error: str) -> tuple[int, dict]:
        summary["error"] = error
        return code, summary

    # Shared validation before ANY side effect (mirrors the CLI parsing
    # so direct execute() callers get the same gate as main()).
    if not isinstance(device_key, str) or \
            device_key not in wi.SUPPORTED_DEVICES:
        return fail_closed(
            EXIT_INVALID,
            f"unknown device {device_key!r}; "
            f"catalog: {list(wi.SUPPORTED_DEVICES)}")
    if not isinstance(locales, list) or not locales:
        return fail_closed(EXIT_INVALID,
                           "locales must be a non-empty list")
    if any(not isinstance(loc, str) or not loc for loc in locales):
        return fail_closed(
            EXIT_INVALID, "locales must be a non-empty list of strings")
    if len(set(locales)) != len(locales):
        return fail_closed(EXIT_INVALID,
                           "locales has duplicate entries; "
                           "each locale must appear once")
    for loc in locales:
        if loc not in wi.SUPPORTED_LOCALES:
            return fail_closed(
                EXIT_INVALID,
                f"unknown language {loc!r}; "
                f"locales: {list(wi.SUPPORTED_LOCALES)}")
    # Audit hole 1: the invocation piece alone can satisfy
    # [A-Za-z0-9_-]{1,64} while the composite actual run id
    # <device>-<locale>-r1-<invocation> exceeds 64 (e.g. a 64-char
    # invocation under iphone69-zh-Hans). Every selected actual run id
    # pre-validates here — before ANY mkdir, spawn, or status write —
    # so an overlong identity rejects cleanly (code 2, zero
    # children/files) instead of failing late inside status_record
    # after capture work already ran.
    for loc in locales:
        for p in wi.PASSES:
            try:
                wa.validate_run_id(f"{device_key}-{loc}-{p}-{invocation}")
            except wa.ArtifactError as exc:
                return fail_closed(
                    EXIT_INVALID,
                    f"run id for {device_key}/{loc}/{p} rejected: {exc}; "
                    "rerun with a shorter --invocation-id")
    if not device_udid or device_udid == "booted":
        return fail_closed(
            EXIT_INVALID,
            "explicit simulator UDID required (no 'booted' auto-pick)")
    try:
        guard.resolve_out_root(str(shots_root))
    except guard.GuardError as exc:
        return fail_closed(EXIT_INVALID, f"output root rejected: {exc}")
    if child_env.get(LEASE_ENV) != "1":
        return fail_closed(
            EXIT_INVALID,
            f"refused: capture work requires {LEASE_ENV}=1 in the worker "
            "environment (passed explicitly to every session child)")
    if not capture_py.is_file():
        return fail_closed(EXIT_INVALID,
                           f"capture CLI not found: {capture_py}")
    if provenance is not None and not Path(provenance).is_file():
        return fail_closed(EXIT_INVALID,
                           f"provenance file not found: {provenance}")
    # Expansion approval travels as a pair or not at all: a lone flag
    # would silently weaken the 5.4 gate, so reject before device work.
    # Missing pair + gated locale stays blocked downstream (existing
    # run-session gates); this worker never auto-opens gates and never
    # reads LIFIO_CAPTURE_CI.
    if (approval is None) != (retained_dir is None):
        return fail_closed(
            EXIT_INVALID,
            "approval pair incomplete: --approval and --retained-dir "
            "must be given together (no silent fallback)")
    if approval is not None and not Path(approval).is_file():
        return fail_closed(EXIT_INVALID,
                           f"approval file not found: {approval}")
    if retained_dir is not None and not Path(retained_dir).is_dir():
        return fail_closed(EXIT_INVALID,
                           f"retained dir not found: {retained_dir}")
    # Audit hole 2: statuses/runs-only detection missed requests-only
    # orphans (and foreign files/dangling symlinks), letting
    # make-request overwrite the non-namespaced base request file.
    # ANY nonempty selected pair cell is prior output from a previous
    # invocation: refuse before mutation and preserve its bytes exactly
    # (never delete, overwrite, or merge). A manual rerun must target
    # a fresh output root instead.
    for loc in locales:
        cell = wa.locale_artifact_dir(shots_root, device_key, loc)
        try:
            nonempty = cell.is_dir() and any(cell.iterdir())
        except OSError as exc:
            return fail_closed(
                EXIT_INVALID,
                f"refused: locale cell {cell} unreadable ({exc}); "
                "rerun into a fresh output root")
        if nonempty:
            return fail_closed(
                EXIT_INVALID,
                f"refused: locale cell {cell} already holds output from "
                "a previous invocation; rerun into a fresh output root "
                "(manual reruns always use a new run identity)")

    geometry = wi.DEVICE_CATALOG[device_key]["geometry"]
    island = str(wi.island_for_device(device_key))

    def call(argv: list[str]) -> tuple[object | None, str]:
        """Run one child. Returns (proc, '') or (None, launch-note) when
        the spawn itself fails (missing binary, timeout); the caller
        treats a launch failure exactly like a fatal child rc."""
        try:
            return run(argv, child_env), ""
        except (OSError, subprocess.TimeoutExpired) as exc:
            return None, f"launch failed: {exc}"

    inflight: list | None = None
    try:
        if cancelled():
            stop_remaining(f"cancelled ({cancel_file} present before start)")
            summary["cancelled"] = True
            return finish(EXIT_CANCELLED)
        for locale in locales:
            if cancelled():
                stop_remaining(f"cancelled ({cancel_file} present)")
                summary["cancelled"] = True
                return finish(EXIT_CANCELLED)
            ldir = locale_dir(locale)
            try:
                ldir.mkdir(parents=True, exist_ok=True)
                req_dir = ldir / "requests"
                req_dir.mkdir(parents=True, exist_ok=True)
            except OSError as exc:
                return fail_closed(
                    EXIT_INVALID, f"cannot create {ldir}: {exc}")
            base = req_dir / f"{device_key}-{locale}-base-request.json"
            pin = req_dir / f"{device_key}-{locale}-pinned-totals.json"
            proc, note = call(
                make_request_argv(capture_py, locale, geometry, base))
            if note:
                reason = f"make-request {note}"
                emit(locale, "r1", wa.STATUS_FAILED, reason)
                stop_remaining(f"stopped after request failure: {reason}")
                return finish(EXIT_FAILED)
            if proc.returncode != 0:
                reason = (f"make-request rc={proc.returncode} "
                          f"{_stderr_tail(proc)}").strip()
                emit(locale, "r1", wa.STATUS_FAILED, reason)
                stop_remaining(f"stopped after request failure: {reason}")
                return finish(EXIT_FAILED)
            proc, note = call(totals_argv(capture_py, locale, pin))
            if note:
                reason = f"locale-totals {note}"
                emit(locale, "r1", wa.STATUS_FAILED, reason)
                stop_remaining(f"stopped after request failure: {reason}")
                return finish(EXIT_FAILED)
            if proc.returncode != 0:
                reason = (f"locale-totals rc={proc.returncode} "
                          f"{_stderr_tail(proc)}").strip()
                emit(locale, "r1", wa.STATUS_FAILED, reason)
                stop_remaining(f"stopped after request failure: {reason}")
                return finish(EXIT_FAILED)
            for pass_name in wi.PASSES:
                if cancelled():
                    stop_remaining(f"cancelled ({cancel_file} present)")
                    summary["cancelled"] = True
                    return finish(EXIT_CANCELLED)
                rid = run_id_for(locale, pass_name)
                inflight = [locale, pass_name]
                for domain in DOMAINS:
                    if cancelled():
                        stop_remaining(f"cancelled ({cancel_file} present)")
                        summary["cancelled"] = True
                        return finish(EXIT_CANCELLED)
                    proc, note = call(session_argv(
                        capture_py, device=device_udid, device_key=device_key,
                        request=base, domain=domain, out=ldir, run_id=rid,
                        geometry=geometry, pinned_totals=pin, island=island,
                        approval=approval, retained_dir=retained_dir))
                    if note:
                        reason = f"{domain} session {note}"
                        emit(locale, pass_name, wa.STATUS_FAILED, reason)
                        stop_remaining(f"contaminated; stopped: {reason}")
                        return finish(EXIT_FAILED)
                    if proc.returncode != 0:
                        reason = (f"{domain} session rc={proc.returncode} "
                                  f"{_stderr_tail(proc)}").strip()
                        emit(locale, pass_name, wa.STATUS_FAILED, reason)
                        stop_remaining(f"contaminated; stopped: {reason}")
                        return finish(EXIT_FAILED)
                proc, note = call(
                    finalize_argv(capture_py, ldir, rid, provenance))
                if note:
                    reason = f"finalize-run {note}"
                    emit(locale, pass_name, wa.STATUS_FAILED, reason)
                    stop_remaining(f"contaminated; stopped: {reason}")
                    return finish(EXIT_FAILED)
                if proc.returncode == 0:
                    emit(locale, pass_name, wa.STATUS_OK, "")
                elif proc.returncode == 3:
                    note = ("finalize-run needs-inspection "
                            f"{_stderr_tail(proc)}").strip()
                    emit(locale, pass_name, wa.STATUS_OK, note)
                else:
                    reason = (f"finalize-run rc={proc.returncode} "
                              f"{_stderr_tail(proc)}").strip()
                    emit(locale, pass_name, wa.STATUS_FAILED, reason)
                    stop_remaining(f"contaminated; stopped: {reason}")
                    return finish(EXIT_FAILED)
                inflight = None
    except KeyboardInterrupt:
        if inflight is not None and tuple(inflight) not in done:
            try:
                emit(inflight[0], inflight[1], wa.STATUS_FAILED,
                     "interrupted; session receipts missing")
            except (OSError, wa.ArtifactError):
                pass
        try:
            stop_remaining("interrupted; receipts missing; "
                           "runner finally owns simulator cleanup")
        except (OSError, wa.ArtifactError):
            pass
        summary["error"] = (
            summary["error"] or
            "interrupted (SIGINT); receipts may be missing; "
            "runner finally owns simulator cleanup")
        finish(EXIT_FAILED)
        raise

    failed = any(r == "failed" for pair in summary["pairs"].values()
                 for p in wi.PASSES for r in (pair[p],))
    return finish(EXIT_FAILED if failed else EXIT_OK)


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="run_device_worker.py",
        description="Device-worker outer loop: one device, selected "
                    "locales, a SINGLE automated pass each with "
                    "pinned+realtime sessions. --out is "
                    "the shots root (per-locale dirs shots/<device>/<locale>, "
                    "device summary at shots/<device>/). The YAML worker "
                    "creates/boots/installs the simulator once; "
                    "this loop never touches simctl.")
    ap.add_argument("--device-key", required=True,
                    help="catalog key (iphone69|iphone63|ipad13)")
    ap.add_argument("--device", required=True,
                    help="simulator UDID installed once by the YAML worker")
    ap.add_argument("--locales", required=True,
                    help="JSON locale list, e.g. '[\"en\",\"ru\"]'")
    ap.add_argument("--out", required=True,
                    help="shots root for this run (must be fresh; reused "
                         "locale cells from a previous invocation are "
                         "refused, never overwritten)")
    ap.add_argument("--capture-py", required=False, default=None)
    ap.add_argument("--provenance", required=False, default=None)
    ap.add_argument("--cancel-file", required=False, default=None)
    ap.add_argument("--invocation-id", required=False, default=None,
                    help="explicit run-identity namespace "
                         "(<device>-<locale>-r1-<invocation>); when omitted "
                         "a fresh id is minted, so manual reruns never "
                         "share run identities with the original")
    ap.add_argument("--approval", required=False, default=None,
                    help="5.4 approval file; must pair with --retained-dir")
    ap.add_argument("--retained-dir", required=False, default=None,
                    help="retained evidence dir bound by the approval file")
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        locales = wi.parse_locale_selection(args.locales)
    except wi.InputError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    capture_py = (Path(args.capture_py) if args.capture_py is not None
                  else default_capture_py())
    code, summary = execute(
        device_key=args.device_key, device_udid=args.device,
        locales=locales, out_dir=Path(args.out), capture_py=capture_py,
        provenance=args.provenance, cancel_file=args.cancel_file,
        approval=args.approval, retained_dir=args.retained_dir,
        invocation_id=args.invocation_id,
        env=os.environ)
    if summary.get("error"):
        print(f"invalid: {summary['error']}", file=sys.stderr)
    print(json.dumps(summary, sort_keys=True, indent=2))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
