#!/usr/bin/env python3
"""Write the external screenshot-bundle README (text only, no device).

Usage:
  write_bundle_readme.py --panels-dir <panels> --shots-dir <shots> \\
      --ios-runtime "iOS 27.0" --devices '["iphone69","ipad13"]' \\
      --languages '["en","ru"]' --out <readme.md>
      [--commit <sha>] [--dirty <true|false>]

Records devices, runtime, timestamp, commit, and deck: device catalog
(size/canvas/Island), the ios-runtime string verbatim, a UTC generation
timestamp, the repo commit (+ dirty flag, auto-detected unless overridden),
and per-set deck_version/treatment/run/status harvested from the shots-dir
via the shared single-pass selector (sets without exactly one valid
selected manifest are marked unverified/ambiguous/unreadable, never
invented). Panel inventory comes from the matrix
manifest when present, plus a sha256 file listing of the actual bundle
bytes. Review status is REVIEW SET ONLY — writing this README approves
nothing and claims no upload.

Exit codes: 0 written; 2 invalid (missing dirs, bad JSON, unknown
device/locale).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "screenshots"))

import builder as panels_builder
import output_guard as guard
import panels as panels_sel

EXIT_OK = 0
EXIT_INVALID = 2

STORE_LISTING_NOTE = ("es-419 app captures map to the Spanish (Mexico) "
                      "Store listing; bundle language and Store metadata "
                      "identifiers are distinct.")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_output(*argv: str) -> str | None:
    try:
        proc = subprocess.run(["git", *argv], capture_output=True, text=True,
                              timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def detect_commit() -> tuple[str, str]:
    """(commit sha, dirty flag); 'unknown' when git cannot answer."""
    repo = str(guard.repo_root())
    head = git_output("-C", repo, "rev-parse", "HEAD")
    status = git_output("-C", repo, "status", "--porcelain")
    commit = head if head else "unknown"
    dirty = "unknown" if status is None else ("true" if status else "false")
    return commit, dirty


def harvest_deck(shots_dir: Path, device: str,
                 language: str) -> dict[str, str]:
    """Deck record for one set via the shared matrix selector.

    Single-pass (owner decision 2026-11-04): matrix rendering and README
    harvesting share ONE selector (panels.select_cell_run), so both report
    the same selected run_id or the same blocked reason — never diverge
    (pointer-selected fresh run renders in both; malformed/absent
    selections block both). Zero manifests -> unverified; multiple or
    pointer-ambiguous -> ambiguous (never picked/merged); unreadable,
    binding-refused (device/run_id/locale), symlink-escape, or
    pointer-invalid selections -> unreadable. No r1/r2 fallback. Exit
    stays 0 (marks, never fabricates); matrix cells block via exit 2.
    """
    set_dir = shots_dir / device / language
    try:
        run_id, manifest = panels_sel.select_cell_run(
            set_dir, device, language)
    except panels_builder.BuilderError as exc:
        msg = str(exc).lower()
        if "ambiguous" in msg:
            marker = f"ambiguous ({str(exc)[:160]})"
            return {"run_id": marker, "deck_version": "ambiguous",
                    "treatment": "ambiguous", "status": "ambiguous",
                    "ci_approval_bypass": "ambiguous"}
        if "no run under" in msg:
            return {"run_id": "none", "deck_version": "unverified",
                    "treatment": "unverified", "status": "unverified",
                    "ci_approval_bypass": "unverified"}
        return {"run_id": "unreadable selection",
                "deck_version": "unreadable manifest",
                "treatment": "unreadable manifest", "status":
                "unreadable manifest", "ci_approval_bypass":
                "unreadable manifest"}
    try:
        obj = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return {"run_id": run_id, "deck_version": "unreadable manifest",
                "treatment": "unreadable manifest", "status":
                "unreadable manifest", "ci_approval_bypass": "unreadable manifest"}
    if not isinstance(obj, dict):
        return {"run_id": run_id, "deck_version": "unreadable manifest",
                "treatment": "unreadable manifest", "status":
                "unreadable manifest", "ci_approval_bypass": "unreadable manifest"}
    return {"run_id": run_id,
            "deck_version": str(obj.get("deck_version", "unknown")),
            "treatment": str(obj.get("treatment", "unknown")),
            "status": str(obj.get("status", "unknown")),
            "ci_approval_bypass": str(obj.get("ci_approval_bypass", "unknown"))}


def parse_str_list(raw: str, name: str) -> list[str]:
    try:
        val = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{name} must be a JSON list, got {raw!r}: {exc}")
    if (not isinstance(val, list) or not val
            or not all(isinstance(x, str) and x for x in val)):
        raise ValueError(
            f"{name} must be a non-empty JSON list of strings, got {raw!r}")
    return val


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description="Write the external screenshot-bundle README.")
    ap.add_argument("--panels-dir", required=True)
    ap.add_argument("--shots-dir", required=True)
    ap.add_argument("--ios-runtime", required=True)
    ap.add_argument("--devices", required=True)
    ap.add_argument("--languages", required=True)
    ap.add_argument("--out", required=True, help="README file path")
    ap.add_argument("--commit", default=None, help="override detected commit")
    ap.add_argument("--dirty", default=None, choices=["true", "false"],
                    help="override detected dirty flag")
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    panels_dir = Path(args.panels_dir)
    if not panels_dir.is_dir():
        print(f"invalid: panels dir not found: {panels_dir}",
              file=sys.stderr)
        return EXIT_INVALID
    shots_dir = Path(args.shots_dir)
    if not shots_dir.is_dir():
        print(f"invalid: shots dir not found: {shots_dir}", file=sys.stderr)
        return EXIT_INVALID
    if not args.ios_runtime.strip():
        print("invalid: --ios-runtime must be a non-empty string",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        devices = parse_str_list(args.devices, "devices")
        languages = parse_str_list(args.languages, "languages")
        for d in devices:
            if d not in panels_builder.MATRIX_DEVICES:
                raise ValueError(
                    f"unknown device {d!r}; catalog: "
                    f"{sorted(panels_builder.MATRIX_DEVICES)}")
        for lang in languages:
            if lang not in panels_builder.LOCALES:
                raise ValueError(
                    f"unknown language {lang!r}; locales: "
                    f"{list(panels_builder.LOCALES)}")
    except ValueError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID

    detected_commit, detected_dirty = detect_commit()
    commit = args.commit or detected_commit
    dirty = args.dirty or detected_dirty
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z")
    try:
        pillow = __import__("PIL").__version__
    except ImportError:  # pragma: no cover
        pillow = "unknown"

    matrix_path = panels_dir / "matrix-manifest.json"
    matrix = None
    if matrix_path.is_file():
        try:
            matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, UnicodeDecodeError):
            matrix = None

    decks = {(d, lang): harvest_deck(shots_dir, d, lang)
             for d in devices for lang in languages}
    files: list[tuple[str, str]] = []
    # bezel-stage* carries the bezel-stage transcript (release, manifest
    # SHA, per-asset hashes/geometry) into the bundle inventory so a
    # handoff/debug bundle names its bezel evidence next to the panels.
    # bezel-fetch* is retained for older bundles only (fetcher retired).
    for pattern in ("panel-*.png", "*.recipe.json", "matrix-manifest.json",
                    "bezel-stage*", "bezel-fetch*"):
        for path in sorted(panels_dir.rglob(pattern)):
            try:
                files.append((str(path.relative_to(panels_dir)),
                              sha(path)))
            except OSError:
                files.append((str(path.relative_to(panels_dir)),
                              "unreadable"))

    lines = [
        "# Lifio App Store screenshot bundle",
        "",
        f"> {panels_builder.REVIEW_STATUS}",
        "",
        "## Approval status",
        "",
    ]
    bypass_values = {deck["ci_approval_bypass"] for deck in decks.values()}
    if "True" in bypass_values:
        lines += [
            "> CI CAPTURE — NOT OWNER-APPROVED: at least one set in this "
            "bundle ran under `LIFIO_CAPTURE_CI=1` "
            "(`ci_approval_bypass:true`), which satisfies the 5.4 expansion "
            "gates without a human approval file. Owner gates 5.4/6.6/9.4 "
            "still require explicit human approval of the retained frames "
            "before any upload or publication.",
            "",
        ]
    elif bypass_values == {"False"}:
        lines += [
            "- All harvested run manifests ran under explicit 5.4 approval "
            "(`ci_approval_bypass:false`); owner gates 5.4/6.6/9.4 still "
            "require explicit human approval before any upload or publication.",
            "",
        ]
    else:
        lines += [
            "- Approval provenance unverified: no harvested run manifest "
            "declares `ci_approval_bypass` (sets unverified or manifests "
            "unreadable). Treat this bundle as NOT owner-approved until a "
            "human verifies the run manifests.",
            "",
        ]
    lines += [
        "## Bundle",
        "",
        f"- generated_utc: {stamp}",
        f"- commit: {commit}",
        f"- dirty: {dirty}",
        f"- ios_runtime: {args.ios_runtime}",
        f"- renderer: Pillow {pillow}",
        f"- templates: 6.9 v{panels_builder.TEMPLATE_69}, "
        f"6.3 v{panels_builder.TEMPLATE_69} (scaled), "
        f"ipad {panels_builder.TEMPLATE_IPAD}",
        "",
        "## Devices",
        "",
        "| device | panel size | canvas | island | model | color |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for d in devices:
        info = panels_builder.MATRIX_DEVICES[d]
        w, h = info["canvas"]
        lines.append(f"| {d} | {info['size']} | {w}x{h} | "
                     f"{'yes' if info['island'] else 'no'} | "
                     f"{info.get('model', 'unknown')} | "
                     f"{info.get('color', 'unknown')} |")
    lines += [
        "",
        "## Languages",
        "",
        f"- {', '.join(languages)}",
        f"- {STORE_LISTING_NOTE}",
        "",
        "## Decks (from shots-dir run manifests)",
        "",
        "| device | language | run_id | deck_version | treatment | status | ci_approval_bypass |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for d in devices:
        for lang in languages:
            deck = decks[(d, lang)]
            lines.append(f"| {d} | {lang} | {deck['run_id']} | "
                         f"{deck['deck_version']} | {deck['treatment']} | "
                         f"{deck['status']} | {deck['ci_approval_bypass']} |")
    lines += ["", "## Panels"]
    if isinstance(matrix, dict) and isinstance(matrix.get("cells"), list):
        counts = json.dumps(matrix.get("counts", {}), sort_keys=True)
        lines += ["",
                  "- matrix-manifest.json status: "
                  f"{matrix.get('status', 'unknown')} ({counts})",
                  ""]
        if matrix.get("status") == "complete":
            lines += ["> COMPLETE MATRIX (review set) — every cell rendered, "
                      "but this README approves nothing; owner gates "
                      "5.4/6.6/9.4 still require explicit human approval "
                      "before any upload or publication.",
                      ""]
        else:
            lines += ["> CI HANDOFF/DEBUG BUNDLE — incomplete matrix: "
                      "blocked cells below are pending evidence, not approved "
                      "panels. This README approves nothing; owner gates "
                      "5.4/6.6/9.4 still require explicit human approval.",
                      ""]
        lines += ["| device | language | size | status | detail |",
                  "| --- | --- | --- | --- | --- |"]
        for cell in matrix["cells"]:
            if not isinstance(cell, dict):
                continue
            if cell.get("status") == "rendered":
                n = len(cell.get("panels", {}))
                detail = (f"{n} panels, run {cell.get('run_id')}, "
                          f"captions {cell.get('captions_version')}")
            else:
                detail = str(cell.get("reason", "blocked"))
            lines.append(f"| {cell.get('device')} | {cell.get('language')} | "
                         f"{cell.get('size')} | {cell.get('status')} | "
                         f"{detail} |")
    else:
        lines += ["", "- no matrix-manifest.json in panels dir; "
                      "per-file inventory below is authoritative.", ""]
    lines += ["", "## Files (sha256)", ""]
    for name, digest in files:
        lines.append(f"- {name} {digest}")
    if not files:
        lines.append("- (no panel/manifest files found)")
    lines += [
        "",
        "## Handoff",
        "",
        "- External bundle only: no binaries are committed to git.",
        "- This README approves nothing and claims no upload or "
        "publication; owner gates 5.4/6.6/9.4 still require explicit "
        "human approval of retained frames.",
        "",
    ]
    out_path = Path(args.out)
    try:
        if out_path.parent != Path(".") and str(out_path.parent):
            out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\n".join(lines), encoding="utf-8")
    except OSError as exc:
        print(f"invalid: cannot write {out_path}: {exc}", file=sys.stderr)
        return EXIT_INVALID
    print(f"wrote {out_path}")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
