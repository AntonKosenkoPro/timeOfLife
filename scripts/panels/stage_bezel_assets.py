#!/usr/bin/env python3
"""Stage official Apple device bezel PNGs from a local source dir (fail-closed).

Usage:
  stage_bezel_assets.py --source-dir <dir> --out <external-bezels-dir>
      [--manifest <apple-bezels-manifest.json>]
      [--expected-manifest-sha <hex>]

Local-only staging for the OWNER-DECIDED private versioned release
(`AntonKosenkoPro/lifio-design-assets`, `apple-bezels-v2` — 4 release PNGs:
18PM current plus 17PM retained for history — + manifest): the CI worker
downloads the canonical PNGs + manifest with `gh release download`
(auth handled outside this helper — a read-only APPLE_BEZELS_TOKEN secret,
pending owner provisioning; never copy a token from local `gh auth`),
then THIS helper verifies and stages them. No network, no Figma/Sketch
API, no DMG extraction here — those are retired, not reimplemented.

Trust order (fail-closed at each step):

1. The downloaded manifest bytes are hashed FIRST and compared against
   the pinned manifest SHA (baked default `--expected-manifest-sha`;
   tests inject their own manifest+sha pair — production strictness is
   never disabled globally). Only after the hash matches is ANY manifest
   metadata (names, SHAs, dimensions, cavities) used. A downloaded
   manifest's mutable SHA claims are never trusted. Release/repo tags
   must read a pinned release (`apple-bezels-v2`; `apple-bezels-v1`
   stays accepted for historical bundles already staged) / the pinned
   repo.
2. Manifest assets are grouped by staged size; a sole candidate stages
   as-is, while competing same-geometry candidates resolve to the pinned
   per-size preferred release file (18PM over 17PM) — competing
   non-preferred candidates refuse (never picked or merged silently).
3. Each source PNG (located by manifest `name` under --source-dir;
   originals stay read-only, never modified) is hashed and compared to
   its manifest SHA256 (tampered bytes refused), then geometry/alpha
   verified with the panel builder against the exact pinned Apple
   profile (native dimensions, measured screen slot, clear interior,
   opaque frame — no silent scale/rotate).
4. Verified bytes are copied atomically (tmp `.part` + rename) to the
   canonical staged filenames shared with panels.py --render-matrix.
   Original filenames never leak into the render path.

Outputs (canonical names shared with panels.py --render-matrix):
  <out>/iphone-69-bezel.png    (iPhone 17 Pro Max Silver, 1470x3000)
  <out>/iphone-63-bezel.png    (iPhone 17 White, 1350x2760)
  <out>/ipad-13-bezel.png      (iPad Pro 13-inch (M5) Silver, 2300x3000)
  <out>/bezel-stage.json       (stage transcript: release, manifest SHA,
                                per-asset hashes/geometry/provenance)

On any failure nothing new is trusted: `.part` files are removed, the
failing asset is not staged, previously staged assets from earlier runs
are left untouched (partial handoff, like the retired fetcher — missing
cells stay blocked downstream, no art fabricated), and no stage manifest
is written. Exit codes: 0 staged + verified; 2 invalid/blocked.

Artwork license: bezel PNGs are property of Apple (Apple Design
Resources license; private internal use only, no redistribution
clearance claimed). Staged bezels and raw PNGs must NEVER enter git or
any public artifact ZIP — only rendered marketing panels + recipe hashes
ship (licensed use, no legal-approval claim here).

Dependencies: stdlib + Pillow (via builder). No device, no simulator I/O.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
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

# Size key -> (Apple source pins, builder verifier).
_SIZE_MAP: tuple[tuple[str, dict]] = (
    ("6.9", panels_builder.APPLE_SOURCE_69),
    ("6.3", panels_builder.APPLE_SOURCE_63),
    ("ipad13", panels_builder.APPLE_SOURCE_IPAD),
)


class StageError(ValueError):
    """Fail-closed staging error: unconfigured, mismatched, or drifted."""


def _sha_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _load_verified_manifest(manifest_path: Path,
                            expected_sha: str) -> dict:
    """Read + hash-verify the release manifest BEFORE using its metadata."""
    if manifest_path.is_symlink():
        raise StageError(
            f"manifest {manifest_path} is a symlink; refusing escape")
    try:
        raw = manifest_path.read_bytes()
    except OSError as exc:
        raise StageError(f"manifest not readable {manifest_path}: {exc}")
    actual = _sha_bytes(raw)
    if actual != expected_sha.lower():
        raise StageError(
            f"release manifest hash mismatch: file {actual[:16]}… != pinned "
            f"{expected_sha[:16]}…; refusing to trust any manifest metadata")
    try:
        obj = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise StageError(f"release manifest malformed {manifest_path}: {exc}")
    if not isinstance(obj, dict):
        raise StageError("release manifest must contain a JSON object")
    if obj.get("release") not in (panels_builder.APPLE_RELEASE,
                                    panels_builder.APPLE_RELEASE_V1):
        raise StageError(
            f"release manifest release {obj.get('release')!r} not in pinned "
            f"{(panels_builder.APPLE_RELEASE_V1, panels_builder.APPLE_RELEASE)}; "
            "refusing to stage")
    if obj.get("repo") != panels_builder.APPLE_RELEASE_REPO:
        raise StageError(
            f"release manifest repo {obj.get('repo')!r} != pinned "
            f"{panels_builder.APPLE_RELEASE_REPO!r}; refusing to stage")
    assets = obj.get("assets")
    if not isinstance(assets, list) or not assets:
        raise StageError("release manifest 'assets' must be a non-empty list")
    return obj


def _check_asset_entry(entry: object) -> dict:
    """Schema gate for one manifest asset entry (fail-closed)."""
    if not isinstance(entry, dict):
        raise StageError("release manifest asset must be an object")
    name = entry.get("name")
    sha = entry.get("sha256")
    native = entry.get("native")
    slot = entry.get("cavity_slot")
    if not isinstance(name, str) or not name or "/" in name \
            or name.startswith(".") or ".." in name:
        raise StageError(
            f"release manifest asset name {name!r} unsafe; refusing to stage")
    if not isinstance(sha, str) or len(sha) != 64 or any(
            c not in "0123456789abcdef" for c in sha):
        raise StageError(
            f"release manifest asset {name!r} carries an invalid sha256; "
            "refusing to stage")
    if not isinstance(native, dict) or not isinstance(
            native.get("width"), int) or not isinstance(
            native.get("height"), int):
        raise StageError(
            f"release manifest asset {name!r} carries invalid native "
            "dimensions; refusing to stage")
    if not isinstance(slot, dict) or any(
            not isinstance(slot.get(k), int)
            for k in ("x", "y", "width", "height")):
        raise StageError(
            f"release manifest asset {name!r} carries an invalid "
            "cavity_slot; refusing to stage")
    return entry


def _verify_profile(entry: dict, staged_info: dict, size: str) -> None:
    """Cross-check manifest geometry against the baked source profile.

    The manifest itself is already hash-trusted at this point; this gate
    catches code/release skew (a future manifest whose native dimensions
    or cavity disagree with the builder pins this release renders with).
    Asset bytes are bound by manifest SHA256 (checked in stage_asset) and
    by the builder's exact geometry/alpha verification — never by mutable
    self-claims. Test manifests inject their own SHAs but keep pinned
    geometry, so production strictness is never disabled globally.
    """
    pins = dict(panels_builder.APPLE_SOURCE_69
                if size == "6.9" else panels_builder.APPLE_SOURCE_63
                if size == "6.3" else panels_builder.APPLE_SOURCE_IPAD)
    native = entry["native"]
    if (native["width"], native["height"]) != tuple(pins["native"]):
        raise StageError(
            f"manifest asset {entry.get('name')!r} native "
            f"{(native['width'], native['height'])} disagrees with the "
            "pinned source profile; refusing to stage")
    slot = entry["cavity_slot"]
    if (slot["width"], slot["height"], slot["x"], slot["y"]) != (
            pins["slot"][0], pins["slot"][1],
            pins["at"][0], pins["at"][1]):
        raise StageError(
            f"manifest asset {entry.get('name')!r} cavity disagrees with "
            "the pinned source profile; refusing to stage")
    if staged_info.get("sha256") != entry["sha256"]:
        raise StageError(
            f"staged verification hash drift for {entry.get('name')!r}; "
            "refusing to stage")


def _map_size(entry: dict) -> str:
    """Map a manifest asset to a staged size key via pinned native dims."""
    native = entry["native"]
    dims = (native["width"], native["height"])
    for size, pins in _SIZE_MAP:
        if tuple(pins["native"]) == dims:
            return size
    raise StageError(
        f"manifest asset {entry.get('name')!r} native {dims} matches no "
        "pinned Apple source profile; refusing to stage")


def stage_asset(*, entry: dict, source_dir: Path, out_dir: Path) -> dict:
    """Hash-verify + geometry-verify + atomically stage one asset."""
    name = entry["name"]
    src = source_dir / name
    if src.is_symlink():
        raise StageError(
            f"source asset {name!r} is a symlink; refusing escape")
    if not src.is_file():
        raise StageError(
            f"source asset missing {src}; refusing to fabricate it")
    try:
        raw = src.read_bytes()
    except OSError as exc:
        raise StageError(f"source asset not readable {src}: {exc}")
    actual = _sha_bytes(raw)
    if actual != entry["sha256"]:
        raise StageError(
            f"source asset {name!r} hash mismatch: file {actual[:16]}… != "
            f"manifest {entry['sha256'][:16]}…; refusing tampered bytes")
    size = _map_size(entry)
    staged_name = panels_builder.BEZEL_FILES[size]
    tmp = out_dir / (staged_name + ".part")
    try:
        tmp.write_bytes(raw)
    except OSError as exc:
        raise StageError(f"cannot write staging tmp {tmp}: {exc}")
    try:
        if size == "6.9":
            info = panels_builder.verify_bezel_69(tmp)
        elif size == "6.3":
            info = panels_builder.verify_bezel_63(tmp)
        else:
            info = panels_builder.verify_bezel_ipad(tmp)
    except panels_builder.BuilderError as exc:
        tmp.unlink(missing_ok=True)
        raise StageError(
            f"bezel verification failed ({size}, asset {name!r}): {exc}")
    _verify_profile(entry, info, size)
    final = out_dir / staged_name
    try:
        tmp.replace(final)
    except OSError as exc:
        tmp.unlink(missing_ok=True)
        raise StageError(f"cannot publish staged asset {final}: {exc}")
    print(f"wrote {final} {info['sha256'][:12]}")
    return {"release_name": name, "staged_file": staged_name,
            "sha256": info["sha256"], "size": info["size"],
            "model": entry.get("model", "unknown"),
            "color": entry.get("color", "unknown")}


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description="Stage official Apple bezel PNGs from a local source "
                    "dir (fail-closed, no network).")
    ap.add_argument("--source-dir", required=True,
                    help="dir holding the release PNGs by manifest name "
                         "(read-only; e.g. the gh-release download dir)")
    ap.add_argument("--out", required=True,
                    help="external bezels dir (created; repo paths rejected)")
    ap.add_argument("--manifest", required=True,
                    help="downloaded release manifest JSON "
                    "(hash-verified before use)")
    ap.add_argument("--expected-manifest-sha", default=None,
                    help="pinned manifest SHA256 (default: baked "
                         "apple-bezels-v2 pin; tests inject their own "
                         "manifest+sha pair — production strictness is never "
                         "disabled globally)")
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    expected_sha = (args.expected_manifest_sha
                    or panels_builder.APPLE_MANIFEST_SHA256)
    source_dir = Path(args.source_dir)
    if not source_dir.is_dir():
        print(f"invalid: source dir not found: {source_dir}",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        out_dir = guard.resolve_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"invalid: cannot create {out_dir}: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        manifest = _load_verified_manifest(Path(args.manifest),
                                           expected_sha)
        checked = [_check_asset_entry(entry)
                   for entry in manifest["assets"]]
        by_size: dict[str, list[dict]] = {}
        for entry in checked:
            by_size.setdefault(_map_size(entry), []).append(entry)
        selected: list[tuple[str, dict]] = []
        for size, _pins in _SIZE_MAP:
            candidates = by_size.get(size, [])
            if not candidates:
                raise StageError(
                    f"release manifest has no asset for size {size!r}; "
                    "refusing to stage an incomplete set")
            if len(candidates) == 1:
                selected.append((size, candidates[0]))
                continue
            preferred = panels_builder.APPLE_PREFERRED_ASSET[size]
            matches = [c for c in candidates if c["name"] == preferred]
            if len(matches) == 1:
                print(f"note: {size} selects preferred {preferred!r} over "
                      f"{len(candidates) - 1} superseded candidate(s)")
                selected.append((size, matches[0]))
                continue
            raise StageError(
                f"release manifest lists {len(candidates)} competing assets "
                f"for size {size!r} with no single preferred "
                f"{preferred!r}; refusing to pick/merge")
        staged: list[dict] = []
        for size, entry in selected:
            staged.append(stage_asset(entry=entry,
                                      source_dir=source_dir,
                                      out_dir=out_dir))
    except (StageError, panels_builder.BuilderError) as exc:
        for leftover in sorted(out_dir.glob("*.part")):
            leftover.unlink(missing_ok=True)
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    try:
        import PIL as _PIL
        pillow_version = _PIL.__version__
    except ImportError:  # pragma: no cover
        pillow_version = "unknown"
    stage_manifest = {
        "schema_version": 1,
        "release": manifest.get("release"),
        "repo": manifest.get("repo"),
        "manifest_sha256": _sha_bytes(
            Path(args.manifest).read_bytes()),
        "generated_utc": datetime.now(timezone.utc).isoformat(
            timespec="seconds").replace("+00:00", "Z"),
        "assets": staged,
        "renderer": {"tool": "Pillow", "pillow_version": pillow_version,
                     "python_version": platform.python_version()},
    }
    stage_path = out_dir / panels_builder.STAGE_MANIFEST_FILE
    tmp_stage = out_dir / (panels_builder.STAGE_MANIFEST_FILE + ".part")
    try:
        tmp_stage.write_text(
            json.dumps(stage_manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8")
        tmp_stage.replace(stage_path)
    except OSError as exc:
        tmp_stage.unlink(missing_ok=True)
        print(f"invalid: cannot write stage manifest {stage_path}: {exc}",
              file=sys.stderr)
        return EXIT_INVALID
    print(f"wrote {stage_path} release={manifest.get('release')} "
          f"{len(staged)}/{len(_SIZE_MAP)} staged")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
