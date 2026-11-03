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
  <shots>/<device>/<language>/runs/<device>-<language>-r1/run-manifest.json
  <shots>/<device>/<language>/runs/<device>-<language>-r1/frames/<frame>.png
  (r2 is the fallback when r1 is absent; anything else is a blocked cell.)
Matrix layout out: <out>/<device>/<language>/panel-*.png + recipe, plus
  <out>/matrix-manifest.json (rendered/blocked per cell, never fabricated).

Devices are CI catalog keys (iphone69/iphone63/iphone65/ipad13); languages
are JSON lists. Bezels come from fetch_bezel_assets.py (canonical names).
Non-en captions resolve to <captions-dir>/<locale>.json (en falls back to
the in-git captions_en.json); without a captions dir, non-en cells are
BLOCKED (captions pending 9.2), never rendered with substituted copy.

Required headline flags (the panel contract):
  --locale      en | ru | zh-Hans | es-419 | pt-BR
  --size        6.9 | 6.5 | ipad13
                6.9    -> approved v13 composition (5 panels, LA-combined)
                ipad13 -> approved ipad-v1 composition (4 panels, no LA)
                6.5    -> recognized but REFUSED: no owner-approved 6.5
                          composition exists; the workflow stops at the
                          template gate and names the pending decision.
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
  --bezel         device bezel PNG (iPhone bezel for 6.9, silver iPad bezel
                  for ipad13; carries the transparent screen slot).

Verification:
  --selftest       structural selftest on the built outputs (template
                   geometry, gaps, headline text, background/device probes).
  --check-template byte-identical proof for owner-approved EN compositions:
                   output hashes MUST equal the baked approved-template set
                   (en/6.9 -> v13 hashes, en/ipad13 -> ipad-v1 hashes).

Exit codes: 0 built (and every requested check green); 2 invalid/blocked
(bad flags, caption drift, source drift, template-gate refusal, fit
finding, check mismatch). Nothing here approves assets: outputs are
REVIEW SETS ONLY until the 9.3 hold clears and 9.4 acceptance lands.
"""

from __future__ import annotations

import argparse
import json
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
        print("invalid: --size is required (6.9 | 6.5 | ipad13)",
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

    size_info = panels_builder.SIZES[args.size]
    if size_info["template"] is None:
        print(f"blocked: no owner-approved {args.size}-inch panel composition; "
              "only 6.9 (template v13) and ipad13 (template ipad-v1) are "
              "approved — the 6.5 template decision is pending, matrix render "
              "stays HELD per 9.3", file=sys.stderr)
        return EXIT_INVALID

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


def find_matrix_run(set_dir: Path, device: str,
                    language: str) -> tuple[str, Path]:
    """Locate the panel source run: <device>-<language>-r1, else -r2."""
    for run_id in (f"{device}-{language}-r1", f"{device}-{language}-r2"):
        manifest = set_dir / "runs" / run_id / "run-manifest.json"
        if manifest.is_file():
            return run_id, manifest
    raise panels_builder.BuilderError(
        f"no r1/r2 run under {set_dir}/runs "
        f"(expected {device}-{language}-r1); set incomplete — recorded, "
        "never fabricated")


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
            "(template v13) and ipad13 (template ipad-v1) are approved — "
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
            f"missing bezel asset {bezel_path}; fetch via "
            "fetch_bezel_assets.py --out "
            f"{bezels_dir}")
    caps_obj = panels_builder.load_captions(
        captions_for(language, captions_dir))
    caps = panels_builder.validate_captions_for_locale(caps_obj, language)
    captions_version = str(caps_obj.get("version", "unknown"))
    out_cell = out_root / device / language
    out_cell.mkdir(parents=True, exist_ok=True)
    if size == "6.9":
        recipe = panels_builder.build_69(
            language, caps, captions_version,
            frames_dir, manifest_path, bezel_path, out_cell)
        probe_lines = panels_builder.selftest_69(out_cell, recipe)
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
              "(fetch via fetch_bezel_assets.py)", file=sys.stderr)
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
