#!/usr/bin/env python3
"""Store marketing panel CLI (task 9.x): build approved-template panels.

Single render (one locale x one size):
  panels.py --locale en --size 6.9 --panels-dir <external-dir> \\
      --captions captions_en.json --frames-dir <frames> \\
      --run-manifest <run-manifest.json> --bezel <bezel.png>
      [--selftest] [--check-template]

Matrix render (locales x sizes from a shots dir):
  panels.py --render-matrix --shots-dir <shots> --bezels-dir <bezels> \\
      --out <external-dir> --devices '["iphone69","ipad13"]' \\
      --languages '["en","ru"]' [--captions-dir <captions>]

Matrix layout in (capture-runner layout: <device>/<language>/runs/<run-id>/):
  <shots>/<device>/<language>/runs/<run-id>/run-manifest.json
  <shots>/<device>/<language>/runs/<run-id>/frames/<frame>.png
  Single pass (owner decision 2026-11-04): exactly one selected run per
  cell. <run-id> is the fresh invocation run identity (no longer
  guaranteed to be <device>-<language>-r1); legacy r1/r2 fallback is
  removed. Zero manifests or multiple manifests are blocked cells
  (recorded, never picked/merged/fabricated). When the device worker
  writes canonical per-pass status pointers
  (<device>-<language>-*.status.json carrying device/locale/run_id),
  every present pointer must validate and all must agree on one run;
  malformed/symlink/mismatched/bad-run_id pointers block (discovery
  applies ONLY when no pointer files exist). Declared device binding
  (manifest frames device_key == cell device, run_id == directory) and
  strict locale binding (manifest `locale` when present — B-owner field,
  coordinated via main — plus every hash-bound session request envelope
  in runs/<run-id>/requests, unanimous == cell language, never inferring
  from directory/captions) are verified before evidence validation; frame
  evidence (hashes/receipts/N-A/pending) validated unchanged via the
  shared helper. Matrix rendering and bundle-README harvesting share ONE
  selector (select_cell_run) so both report the same run or the same
  blocked reason.
Matrix layout out: <out>/<device>/<language>/panel-*.png + recipe, plus
  <out>/matrix-manifest.json (rendered/blocked per cell, never fabricated).

Devices are capture catalog keys (iphone69/iphone63/ipad13); languages
are JSON lists. Bezels come from stage_bezel_assets.py (canonical names):
official Apple PNGs (iPhone 17 Pro Max Silver, iPhone 17 White, iPad Pro
13-inch (M5) Silver) staged from the private versioned release after exact
manifest+asset hash verification — never Figma, never in git.
Non-en captions resolve to <captions-dir>/<locale>.json (en falls back to
the in-git captions_en.json); without a captions dir, non-en cells are
BLOCKED (captions pending 9.2), never rendered with substituted copy.

Required headline flags (the panel contract):
  --locale      en | ru | zh-Hans | es-419 | pt-BR
  --size        6.9 | 6.3 | ipad13
                6.9    -> v13 composition (5 panels, LA-combined) on official
                          Apple 17 Pro Max art; review sets only until the
                          new-art template version is explicitly approved
                          (9.3 hold still applies, no approval transfer)
                6.3    -> v13 composition scaled to the 1206x2622 canvas
                          (5 panels, LA-combined) on official Apple 17 art;
                          review sets only — no separate 6.3 approval, 9.3
                          hold still applies
                ipad13 -> ipad-v1 composition (4 panels, no LA) on official
                          Apple M5 iPad art
                (owner lineup 2026-11-04: 17 Pro Max / 17 / M5 iPad only;
                6.5 dropped, any other --size is an invalid choice, devices
                outside the matrix catalog stay blocked, never rendered)
  --panels-dir  external output directory (must already exist; repository
                paths are rejected — panel binaries stay outside git).
  --captions    captions JSON file (captions-v1 schema: locale, version,
                captions.{track,insights,history_primary,history_secondary,
                live_activity,add_entry} each with text+en). Locale must
                match --locale; embedded `en` fields must equal the
                owner-fixed copy verbatim; for en, `text` must too.

Supporting inputs (explicit paths; no machine-specific defaults in git):
  --frames-dir    directory with source frame PNGs (<frame>.png). Defaults
                  to <run-manifest-parent>/frames when --run-manifest is set.
  --run-manifest  run-manifest.json: every required source is hash-verified
                  against it (fail-closed); geometry must equal the canvas
                  (no cross-size stretching); run status must be complete.
  --bezel         device bezel PNG (official Apple art staged by
                  stage_bezel_assets.py into canonical names; carries the
                  transparent screen slot).

Verification:
  --selftest       structural selftest on the built outputs (template
                   geometry, gaps, headline text, background/device probes).
  --check-template byte-identical proof for owner-approved EN compositions:
                   output hashes MUST equal the baked approved-template set
                   (en/6.9 -> v13 hashes on the legacy Figma profile,
                   en/ipad13 -> ipad-v1 hashes). New-art (Apple profile)
                   recipes are refused loudly — review sets are never
                   byte-compared against historical approvals.

Exit codes: 0 built (and every requested check green); 2 invalid/blocked
(bad flags, caption drift, source drift, template-gate refusal, fit
finding, check mismatch). Nothing here approves assets: outputs are
REVIEW SETS ONLY until the 9.3 hold clears and 9.4 acceptance lands.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "screenshots"))

import builder as panels_builder
import output_guard as guard

EXIT_OK = 0
EXIT_INVALID = 2

SINGLE_ONLY = ("locale", "size", "panels_dir", "captions", "frames_dir",
               "run_manifest", "bezel", "selftest", "check_template")
MATRIX_ONLY = ("shots_dir", "bezels_dir", "out", "devices", "languages",
               "captions_dir")


def _flag(name: str) -> str:
    return "--" + name.replace("_", "-")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description="Build App Store marketing panels from approved templates.")
    ap.add_argument("--locale", default=None,
                    choices=list(panels_builder.LOCALES))
    ap.add_argument("--size", default=None,
                    choices=sorted(panels_builder.SIZES))
    ap.add_argument("--panels-dir", default=None)
    ap.add_argument("--captions", default=None)
    ap.add_argument("--frames-dir", default=None)
    ap.add_argument("--run-manifest", default=None)
    ap.add_argument("--bezel", default=None)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--check-template", action="store_true")
    ap.add_argument("--render-matrix", action="store_true",
                    help="render the locales x sizes matrix from --shots-dir")
    ap.add_argument("--shots-dir", default=None)
    ap.add_argument("--bezels-dir", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--devices", default=None,
                    help='JSON device list, e.g. \'["iphone69","ipad13"]\'')
    ap.add_argument("--languages", default=None,
                    help='JSON locale list, e.g. \'["en","ru"]\'')
    ap.add_argument("--captions-dir", default=None,
                    help="dir with <locale>.json captions (non-en matrix cells)")
    return ap


def cmd_single(args: argparse.Namespace) -> int:
    for name in MATRIX_ONLY:
        if args.__dict__.get(name) is not None:
            print(f"invalid: {_flag(name)} is matrix-only "
                  "(requires --render-matrix)", file=sys.stderr)
            return EXIT_INVALID
    if args.locale is None:
        print("invalid: --locale is required "
              "(en | ru | zh-Hans | es-419 | pt-BR)", file=sys.stderr)
        return EXIT_INVALID
    if args.size is None:
        print("invalid: --size is required (6.9 | 6.3 | ipad13)",
              file=sys.stderr)
        return EXIT_INVALID
    if args.panels_dir is None:
        print("invalid: --panels-dir is required (external output dir)",
              file=sys.stderr)
        return EXIT_INVALID
    if args.captions is None:
        print("invalid: --captions is required (captions JSON file)",
              file=sys.stderr)
        return EXIT_INVALID

    # NB: --size membership is enforced by argparse choices=SIZES keys;
    # every cataloged size carries a template (no template-None entries).
    try:
        out_dir = guard.ensure_out_root(args.panels_dir)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID

    manifest_path = Path(args.run_manifest) if args.run_manifest else None
    if args.frames_dir:
        frames_dir = Path(args.frames_dir)
    elif manifest_path is not None:
        frames_dir = manifest_path.parent / "frames"
    else:
        print("invalid: --frames-dir or --run-manifest is required "
              "(source frames must be hash-bound to a run manifest)",
              file=sys.stderr)
        return EXIT_INVALID
    if manifest_path is None:
        print("invalid: --run-manifest is required (panels must trace to "
              "hash-verified approved frames, never loose PNGs)",
              file=sys.stderr)
        return EXIT_INVALID
    if not frames_dir.is_dir():
        print(f"invalid: frames dir not found: {frames_dir}", file=sys.stderr)
        return EXIT_INVALID
    if args.bezel is None:
        print("invalid: --bezel is required (approved bezel asset lives in "
              "external retention, never in git)", file=sys.stderr)
        return EXIT_INVALID
    bezel_path = Path(args.bezel)

    try:
        caps_obj = panels_builder.load_captions(Path(args.captions))
        caps = panels_builder.validate_captions_for_locale(caps_obj, args.locale)
        captions_version = str(caps_obj.get("version", "unknown"))
        if args.size == "6.9":
            recipe = panels_builder.build_69(
                args.locale, caps, captions_version,
                frames_dir, manifest_path, bezel_path, out_dir)
        elif args.size == "6.3":
            recipe = panels_builder.build_63(
                args.locale, caps, captions_version,
                frames_dir, manifest_path, bezel_path, out_dir)
        else:
            recipe = panels_builder.build_ipad(
                args.locale, caps, captions_version,
                frames_dir, manifest_path, bezel_path, out_dir)
    except panels_builder.BuilderError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID

    for pname, p in recipe["panels"].items():
        print(f"wrote {out_dir / pname} {p['sha256'][:12]}")
    print(f"wrote {out_dir / recipe['_recipe_file']}")

    if args.selftest:
        try:
            if args.size == "6.9":
                lines = panels_builder.selftest_69(out_dir, recipe)
            elif args.size == "6.3":
                lines = panels_builder.selftest_63(out_dir, recipe)
            else:
                lines = panels_builder.selftest_ipad(out_dir, recipe)
        except panels_builder.BuilderError as exc:
            print(f"invalid: selftest failed: {exc}", file=sys.stderr)
            return EXIT_INVALID
        for line in lines:
            print(line)
        print(f"selftest green: {out_dir / recipe['_recipe_file']}")

    if args.check_template:
        try:
            mismatches = panels_builder.check_template(recipe, args.locale,
                                                       args.size)
        except panels_builder.BuilderError as exc:
            print(f"invalid: {exc}", file=sys.stderr)
            return EXIT_INVALID
        if mismatches:
            for m in mismatches:
                print(f"invalid: template mismatch: {m}", file=sys.stderr)
            return EXIT_INVALID
        print(f"template check green: outputs reproduce the approved "
              f"EN {args.size} composition byte-identical")

    return EXIT_OK


# ---------------------------------------------------------------------------
# Matrix render (locales x sizes from a shots dir)
# ---------------------------------------------------------------------------

def parse_str_list(raw: str, name: str) -> list[str]:
    """Parse a JSON string list flag (fail-closed, never comma-split)."""
    try:
        val = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise panels_builder.BuilderError(
            f"{name} must be a JSON list, got {raw!r}: {exc}")
    if (not isinstance(val, list) or not val
            or not all(isinstance(x, str) and x for x in val)):
        raise panels_builder.BuilderError(
            f"{name} must be a non-empty JSON list of strings, got {raw!r}")
    return val


_RUN_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


def _status_pointer_files(set_dir: Path, device: str,
                          language: str) -> list[Path]:
    return sorted(set_dir.glob(f"{device}-{language}-*.status.json"))


def _read_pointer(path: Path, device: str, language: str) -> str:
    """Validate one present status pointer; return its run_id or raise.

    Fail-closed: symlinks, unreadable/malformed JSON, non-object shapes,
    device/locale mismatch, and unsafe run_ids all block (never ignored
    for fallback discovery).
    """
    name = path.name
    if path.is_symlink():
        raise panels_builder.BuilderError(
            f"status pointer {name} is a symlink; refusing escape — "
            "recorded, never selected")
    try:
        obj = json.loads(path.read_bytes().decode("utf-8"))
    except (OSError, ValueError, UnicodeError) as exc:
        raise panels_builder.BuilderError(
            f"status pointer {name} unreadable/malformed ({exc}); "
            "refusing fallback — recorded, never selected")
    if not isinstance(obj, dict):
        raise panels_builder.BuilderError(
            f"status pointer {name} must contain a JSON object; "
            "refusing fallback — recorded, never selected")
    if obj.get("device") != device or obj.get("locale") != language:
        raise panels_builder.BuilderError(
            f"status pointer {name} declares device/locale "
            f"{obj.get('device')!r}/{obj.get('locale')!r} != cell "
            f"{device!r}/{language!r}; refusing mismatched selection")
    rid = obj.get("run_id")
    if not isinstance(rid, str) or not _RUN_ID_RE.match(rid):
        raise panels_builder.BuilderError(
            f"status pointer {name} carries invalid run_id {rid!r}; "
            "refusing selection")
    return rid


def _check_locale_binding(run_dir: Path, manifest_obj: dict, run_id: str,
                          language: str) -> None:
    """Enforce strict locale binding for a selected matrix run.

    Claims come from the manifest top-level `locale` field when present
    (B-owner verified provenance; coordinated field name `locale` via
    main) plus every hash-bound session request envelope in
    run_dir/requests/*.envelope.json (existing archives; never trusting
    the directory name or captions alone). At least one claim is
    required and every claim must equal the cell language; missing or
    divergent provenance blocks. Envelope locales are bound to frame
    evidence (request_json hash == envelope request_sha256 == frame
    record request_sha256, run/frame identities match), so a forged
    locale without matching frame hashes also blocks. Explicit
    single-render paths bypass selection (retained fixtures preserved).
    """
    claims: list[tuple[str, str]] = []
    mloc = manifest_obj.get("locale")
    if mloc is not None:
        if not isinstance(mloc, str) or not mloc:
            raise panels_builder.BuilderError(
                f"run {run_id} carries invalid locale {mloc!r}; "
                "refusing selection")
        claims.append((f"manifest locale {mloc!r}", mloc))
    req_dir = run_dir / "requests"
    env_paths = sorted(req_dir.glob("*.envelope.json")) \
        if req_dir.is_dir() else []
    by_frame = {r.get("frame"): r for r in manifest_obj.get("frames", [])
                if isinstance(r, dict)}
    seen_frames: set[str] = set()
    for env_path in env_paths:
        ename = env_path.name
        if env_path.is_symlink():
            raise panels_builder.BuilderError(
                f"request envelope {ename} is a symlink; refusing escape "
                f"(locale unverifiable for run {run_id})")
        try:
            env = json.loads(env_path.read_bytes().decode("utf-8"))
        except (OSError, ValueError, UnicodeError) as exc:
            raise panels_builder.BuilderError(
                f"request envelope {ename} unreadable/malformed ({exc}); "
                f"locale unverifiable for run {run_id}")
        if not isinstance(env, dict):
            raise panels_builder.BuilderError(
                f"request envelope {ename} must contain a JSON object; "
                f"locale unverifiable for run {run_id}")
        frame = env.get("frame")
        sha = env.get("request_sha256")
        req_json = env.get("request_json")
        if not isinstance(frame, str) or not frame:
            raise panels_builder.BuilderError(
                f"request envelope {ename} carries no frame; "
                f"locale unverifiable for run {run_id}")
        if not isinstance(sha, str) or not _HEX64_RE.match(sha):
            raise panels_builder.BuilderError(
                f"request envelope {ename} carries invalid request_sha256; "
                f"locale unverifiable for run {run_id}")
        if not isinstance(req_json, str) or not req_json:
            raise panels_builder.BuilderError(
                f"request envelope {ename} carries no request_json; "
                f"locale unverifiable for run {run_id}")
        if hashlib.sha256(req_json.encode("utf-8")).hexdigest() != sha:
            raise panels_builder.BuilderError(
                f"request envelope {ename} hash mismatch (tampered "
                f"request_json); locale unverifiable for run {run_id}")
        try:
            inner = json.loads(req_json)
        except ValueError as exc:
            raise panels_builder.BuilderError(
                f"request envelope {ename} inner payload malformed ({exc}); "
                f"locale unverifiable for run {run_id}")
        if not isinstance(inner, dict):
            raise panels_builder.BuilderError(
                f"request envelope {ename} inner payload must be an object; "
                f"locale unverifiable for run {run_id}")
        iloc = inner.get("locale")
        irun = inner.get("run_id")
        iframe = inner.get("frame")
        if not isinstance(iloc, str) or not iloc:
            raise panels_builder.BuilderError(
                f"request envelope {ename} carries no locale; "
                f"locale unverifiable for run {run_id}")
        if irun != run_id:
            raise panels_builder.BuilderError(
                f"request envelope {ename} run_id {irun!r} != selected run "
                f"{run_id!r}; refusing mismatched locale provenance")
        if iframe != frame:
            raise panels_builder.BuilderError(
                f"request envelope {ename} frame {iframe!r} != envelope "
                f"frame {frame!r}; refusing mismatched locale provenance")
        if env.get("run_id") != run_id:
            raise panels_builder.BuilderError(
                f"request envelope {ename} outer run_id "
                f"{env.get('run_id')!r} != selected run {run_id!r}; "
                "refusing mismatched locale provenance")
        rec = by_frame.get(frame)
        if rec is None:
            raise panels_builder.BuilderError(
                f"request envelope {ename} covers unknown frame "
                f"{frame!r} (unbound to run {run_id}); refusing selection")
        if rec.get("request_sha256") != sha:
            raise panels_builder.BuilderError(
                f"request envelope {ename} hash {sha[:12]} unbound to frame "
                f"record {frame!r} (forged locale without matching frame "
                "hashes refused)")
        seen_frames.add(frame)
        claims.append((f"envelope {ename}", iloc))
    if not seen_frames:
        raise panels_builder.BuilderError(
            f"run {run_id} carries no request envelopes "
            f"(runs/{run_id}/requests/*.envelope.json missing); refusing "
            "to infer locale from directory/captions")
    if not claims:
        raise panels_builder.BuilderError(
            f"run {run_id} carries no locale provenance (manifest locale + "
            "request envelopes missing); refusing to infer locale from "
            "directory/captions")
    bad = [(src, loc) for src, loc in claims if loc != language]
    if bad:
        detail = ", ".join(f"{src} claims {loc!r}" for src, loc in bad[:3])
        extra = f" (+{len(bad) - 3} more)" if len(bad) > 3 else ""
        raise panels_builder.BuilderError(
            f"run {run_id} locale mismatch for cell language "
            f"{language!r}: {detail}{extra}; refusing cross-locale selection")


def select_cell_run(set_dir: Path, device: str,
                    language: str) -> tuple[str, Path]:
    """Select the single-pass source run for a matrix cell (shared).

    ONE selection chokepoint for matrix rendering and bundle-README
    harvesting (both must report the same run_id or the same blocked
    reason; never diverge). Fail-closed everywhere:
    - Present status pointers are strict: every
      <device>-<language>-*.status.json must validate and all must agree
      on exactly one run_id. Malformed/symlink/mismatched/bad-run_id
      pointers block; discovery applies ONLY when no pointer files exist.
    - Without pointers, exactly one runs/*/run-manifest.json is required;
      zero or multiple block (never picked/merged).
    - The selected manifest must satisfy run_id == directory, unanimous
      frames device_key == cell device, and strict locale binding (see
      _check_locale_binding). Full frame evidence stays validated
      downstream via verify_sources (unchanged).
    Raises BuilderError with "ambiguous" for multi-candidate blocks,
    "no run under" for empty cells, "pointer" for invalid pointers, and
    "locale"/"device"/"run_id" for binding refusals.
    """
    ptrs = _status_pointer_files(set_dir, device, language)
    runs_dir = set_dir / "runs"
    if ptrs:
        selected_ids: list[str] = []
        for p in ptrs:
            rid = _read_pointer(p, device, language)
            if rid not in selected_ids:
                selected_ids.append(rid)
        if len(selected_ids) != 1:
            raise panels_builder.BuilderError(
                f"ambiguous status pointers under {set_dir}: "
                f"{len(selected_ids)} distinct run_ids "
                f"({', '.join(sorted(selected_ids))}); single-pass "
                "requires exactly one selected run — recorded, never "
                "picked/merged")
        if not runs_dir.is_dir():
            raise panels_builder.BuilderError(
                f"no run under {set_dir}/runs "
                "(single-pass: exactly one selected run-manifest expected); "
                "set incomplete — recorded, never fabricated")
        run_id = selected_ids[0]
        manifest = runs_dir / run_id / "run-manifest.json"
        if manifest.is_symlink():
            raise panels_builder.BuilderError(
                f"selected run manifest {manifest} is a symlink; refusing "
                "escape — recorded, never selected")
        if not manifest.is_file():
            raise panels_builder.BuilderError(
                f"status pointer selects run {run_id!r} under "
                f"{set_dir}/runs but its run-manifest.json is absent; "
                "set incomplete — recorded, never fabricated")
    else:
        if not runs_dir.is_dir():
            raise panels_builder.BuilderError(
                f"no run under {set_dir}/runs "
                "(single-pass: exactly one selected run-manifest expected); "
                "set incomplete — recorded, never fabricated")
        manifests = sorted(runs_dir.glob("*/run-manifest.json"))
        manifests = [m for m in manifests if m.is_file() or m.is_symlink()]
        if not manifests:
            raise panels_builder.BuilderError(
                f"no run under {set_dir}/runs "
                "(single-pass: exactly one selected run-manifest expected); "
                "set incomplete — recorded, never fabricated")
        if len(manifests) != 1:
            names = ", ".join(sorted(m.parent.name for m in manifests))
            raise panels_builder.BuilderError(
                f"ambiguous runs under {set_dir}/runs: {len(manifests)} "
                f"run-manifests ({names}); single-pass requires exactly "
                "one selected run — recorded, never picked/merged")
        manifest = manifests[0]
        if manifest.is_symlink():
            raise panels_builder.BuilderError(
                f"selected run manifest {manifest} is a symlink; refusing "
                "escape — recorded, never selected")
        run_id = manifest.parent.name
    # Declared identity: manifest run_id must equal its directory name.
    try:
        obj = json.loads(manifest.read_bytes().decode("utf-8"))
    except (OSError, ValueError, UnicodeError) as exc:
        raise panels_builder.BuilderError(
            f"run manifest unreadable {manifest}: {exc}")
    if not isinstance(obj, dict):
        raise panels_builder.BuilderError(
            f"run manifest {manifest} must contain a JSON object")
    if obj.get("run_id") != run_id:
        raise panels_builder.BuilderError(
            f"run manifest run_id {obj.get('run_id')!r} != directory "
            f"{run_id!r}; refusing mismatched selection")
    frames = obj.get("frames")
    if not isinstance(frames, list) or not frames:
        raise panels_builder.BuilderError(
            f"run manifest {manifest} missing 'frames' list")
    keys = {r.get("device_key") for r in frames
            if isinstance(r, dict)}
    if len(keys) != 1 or next(iter(keys)) != device:
        got = ", ".join(sorted(str(k) for k in keys)) or "none"
        raise panels_builder.BuilderError(
            f"run {run_id} declares device_key {{{got}}} != cell device "
            f"{device!r}; refusing cross-device selection")
    _check_locale_binding(manifest.parent, obj, run_id, language)
    # Locale binding is provenance-strict (manifest locale + hash-bound
    # request envelopes); the cell path and captions are never trusted
    # alone. Frame evidence (hashes/receipts/geometry/N-A/pending) is
    # validated unchanged downstream via verify_sources.
    return run_id, manifest


def _selected_run_from_status(set_dir: Path, device: str,
                              language: str) -> str | None:
    """Legacy entry point: strict pointer selection or None when absent.

    Present-but-invalid pointers now raise (fail-closed) instead of
    falling back to manifest discovery; discovery applies ONLY when no
    pointer files exist. Prefer select_cell_run (full selection).
    """
    ptrs = _status_pointer_files(set_dir, device, language)
    if not ptrs:
        return None
    selected_ids: list[str] = []
    for p in ptrs:
        rid = _read_pointer(p, device, language)
        if rid not in selected_ids:
            selected_ids.append(rid)
    if len(selected_ids) != 1:
        raise panels_builder.BuilderError(
            f"ambiguous status pointers under {set_dir}: "
            f"{len(selected_ids)} distinct run_ids "
            f"({', '.join(sorted(selected_ids))}); single-pass requires "
            "exactly one selected run — recorded, never picked/merged")
    return selected_ids[0]


def find_matrix_run(set_dir: Path, device: str,
                    language: str) -> tuple[str, Path]:
    """Locate the single-pass panel source run (exactly one selected).

    Thin wrapper over select_cell_run (shared matrix/README chokepoint).
    """
    return select_cell_run(set_dir, device, language)


def captions_for(language: str, captions_dir: Path | None) -> Path:
    """Resolve the captions file for a matrix cell (fail-closed)."""
    if captions_dir is not None:
        cand = captions_dir / f"{language}.json"
        if cand.is_file():
            return cand
        if language == "en":
            return HERE / "captions_en.json"
        raise panels_builder.BuilderError(
            f"captions file missing {cand}; {language} captions pending "
            "9.2 on-template review — cell blocked, never substituted")
    if language == "en":
        return HERE / "captions_en.json"
    raise panels_builder.BuilderError(
        f"no --captions-dir: {language} captions pending 9.2 on-template "
        "review — cell blocked, never rendered with substituted copy")


def render_matrix_cell(*, device: str, language: str, size: str,
                       shots_dir: Path, bezels_dir: Path,
                       captions_dir: Path | None,
                       out_root: Path) -> dict:
    """Render one device x language cell; BuilderError means blocked cell."""
    size_info = panels_builder.SIZES.get(size)
    if not size_info or size_info["template"] is None:
        raise panels_builder.BuilderError(
            f"no owner-approved {size} panel composition; only 6.9 "
            "(template v13), 6.3 (template v13 scaled), and ipad13 "
            "(template ipad-v1) render — "
            f"matrix cell {device}/{language} stays HELD")
    run_id, manifest_path = find_matrix_run(
        shots_dir / device / language, device, language)
    frames_dir = manifest_path.parent / "frames"
    if not frames_dir.is_dir():
        raise panels_builder.BuilderError(
            f"frames dir not found: {frames_dir}")
    bezel_path = bezels_dir / panels_builder.BEZEL_FILES[size]
    if not bezel_path.is_file():
        raise panels_builder.BuilderError(
            f"missing bezel asset {bezel_path}; stage via "
            "stage_bezel_assets.py --source-dir <release-dir> --out "
            f"{bezels_dir}")
    caps_obj = panels_builder.load_captions(
        captions_for(language, captions_dir))
    caps = panels_builder.validate_captions_for_locale(caps_obj, language)
    captions_version = str(caps_obj.get("version", "unknown"))
    out_cell = out_root / language / device
    out_cell.mkdir(parents=True, exist_ok=True)
    if size == "6.9":
        recipe = panels_builder.build_69(
            language, caps, captions_version,
            frames_dir, manifest_path, bezel_path, out_cell)
        probe_lines = panels_builder.selftest_69(out_cell, recipe)
    elif size == "6.3":
        recipe = panels_builder.build_63(
            language, caps, captions_version,
            frames_dir, manifest_path, bezel_path, out_cell)
        probe_lines = panels_builder.selftest_63(out_cell, recipe)
    else:
        recipe = panels_builder.build_ipad(
            language, caps, captions_version,
            frames_dir, manifest_path, bezel_path, out_cell)
        probe_lines = panels_builder.selftest_ipad(out_cell, recipe)
    return {
        "device": device, "language": language, "size": size,
        "status": "rendered", "run_id": run_id,
        "deck_version": recipe.get("deck_version"),
        "treatment": recipe.get("treatment"),
        "captions_version": captions_version,
        "template_version": recipe.get("template_version"),
        "bezel": recipe.get("bezel"),
        "panels": {n: p["sha256"] for n, p in recipe["panels"].items()},
        "recipe_file": str(out_cell / recipe["_recipe_file"]),
        "selftest": probe_lines,
    }


def cmd_render_matrix(args: argparse.Namespace) -> int:
    for name in SINGLE_ONLY:
        val = args.__dict__.get(name)
        if val is not None and val is not False:
            print(f"invalid: {_flag(name)} is single-render only "
                  "(matrix takes --shots-dir/--bezels-dir/--out/--devices/"
                  "--languages)", file=sys.stderr)
            return EXIT_INVALID
    missing = [n for n in ("shots_dir", "bezels_dir", "out", "devices",
                           "languages")
               if args.__dict__.get(n) is None]
    if missing:
        print(f"invalid: matrix requires "
              f"{', '.join(_flag(n) for n in missing)}", file=sys.stderr)
        return EXIT_INVALID
    try:
        devices = parse_str_list(args.devices, "devices")
        languages = parse_str_list(args.languages, "languages")
        for d in devices:
            if d not in panels_builder.MATRIX_DEVICES:
                raise panels_builder.BuilderError(
                    f"unknown device {d!r}; catalog: "
                    f"{sorted(panels_builder.MATRIX_DEVICES)}")
        for lang in languages:
            if lang not in panels_builder.LOCALES:
                raise panels_builder.BuilderError(
                    f"unknown language {lang!r}; locales: "
                    f"{list(panels_builder.LOCALES)}")
    except panels_builder.BuilderError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID

    try:
        out_root = guard.resolve_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    out_root.mkdir(parents=True, exist_ok=True)
    shots_dir = Path(args.shots_dir)
    if not shots_dir.is_dir():
        print(f"invalid: shots dir not found: {shots_dir}", file=sys.stderr)
        return EXIT_INVALID
    bezels_dir = Path(args.bezels_dir)
    if not bezels_dir.is_dir():
        print(f"invalid: bezels dir not found: {bezels_dir} "
              "(stage via stage_bezel_assets.py)", file=sys.stderr)
        return EXIT_INVALID
    captions_dir = Path(args.captions_dir) if args.captions_dir else None
    if captions_dir is not None and not captions_dir.is_dir():
        print(f"invalid: captions dir not found: {captions_dir}",
              file=sys.stderr)
        return EXIT_INVALID

    cells: list[dict] = []
    for device in devices:
        size = panels_builder.MATRIX_DEVICES[device]["size"]
        for language in languages:
            try:
                cells.append(render_matrix_cell(
                    device=device, language=language, size=size,
                    shots_dir=shots_dir, bezels_dir=bezels_dir,
                    captions_dir=captions_dir, out_root=out_root))
            except panels_builder.BuilderError as exc:
                cells.append({"device": device, "language": language,
                              "size": size, "status": "blocked",
                              "reason": str(exc)})
    try:
        import PIL as _PIL
        pillow_version = _PIL.__version__
    except ImportError:  # pragma: no cover
        pillow_version = "unknown"
    import platform as _platform
    rendered = sum(1 for c in cells if c["status"] == "rendered")
    manifest = {
        "schema_version": 1,
        "generated_utc": datetime.now(timezone.utc).isoformat(
            timespec="seconds").replace("+00:00", "Z"),
        "review_status": panels_builder.REVIEW_STATUS,
        "template_versions": {"6.9": panels_builder.TEMPLATE_69,
                              "6.3": panels_builder.TEMPLATE_69,
                              "ipad13": panels_builder.TEMPLATE_IPAD},
        "devices": devices, "languages": languages,
        "counts": {"cells": len(cells), "rendered": rendered,
                   "blocked": len(cells) - rendered},
        "status": "complete" if rendered == len(cells) else "incomplete",
        "cells": cells,
        "renderer": {"tool": "Pillow", "pillow_version": pillow_version,
                     "python_version": _platform.python_version()},
    }
    manifest_path = out_root / "matrix-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    for cell in cells:
        if cell["status"] == "rendered":
            print(f"rendered {cell['device']}/{cell['language']} "
                  f"({len(cell['panels'])} panels, run {cell['run_id']})")
        else:
            print(f"blocked: {cell['device']}/{cell['language']}: "
                  f"{cell['reason']}", file=sys.stderr)
    print(f"wrote {manifest_path} status={manifest['status']} "
          f"{rendered}/{len(cells)} rendered")
    return EXIT_OK if manifest["status"] == "complete" else EXIT_INVALID


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.render_matrix:
        return cmd_render_matrix(args)
    return cmd_single(args)


if __name__ == "__main__":
    sys.exit(main())
