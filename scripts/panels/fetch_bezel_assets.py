#!/usr/bin/env python3
"""Fetch Apple device bezel PNGs from a pinned Figma source (fail-closed).

Usage:
  FIGMA_API_KEY=<token> fetch_bezel_assets.py --out <external-bezels-dir>
      [--file-key <key>] [--iphone-node <id>] [--iphone63-node <id>]
      [--ipad-node <id>] [--scale <float>]

The bezel source is NOT pinned in git: pass --file-key (or FIGMA_FILE_KEY)
with the owner-approved Apple community Figma file plus the bezel node IDs
(--iphone-node/--iphone63-node/--ipad-node or FIGMA_IPHONE_NODE_ID /
FIGMA_IPHONE63_NODE_ID / FIGMA_IPAD_NODE_ID). Without a pinned source the
fetch fails closed and names the missing pin — no default file is guessed,
no art is fabricated. Known pins: iPhone 6.9 FIGMA_IPHONE_NODE_ID
12887:20855, iPhone 6.3 (iPhone 17 Black) FIGMA_IPHONE63_NODE_ID
6316:14199, iPad FIGMA_IPAD_NODE_ID 5456:18569.

Outputs (canonical names shared with panels.py --render-matrix):
  <out>/iphone-69-bezel.png   (980x2000, transparent screen slot)
  <out>/iphone-63-bezel.png   (measured at fetch time: portrait alpha PNG
                               with a dominant transparent slot agreeing
                               with the 1206x2622 canvas aspect)
  <out>/ipad-13-bezel.png     (2300x3000, silver, transparent cavity)

Every download is geometry/alpha-verified with the panel builder before it
lands: size drift, missing alpha, or a non-transparent screen area fails
loudly and leaves no partial asset behind. Stdlib only (urllib); no
device, no simulator I/O. FIGMA_API_BASE overrides the REST base for
hermetic localhost tests only; production default is api.figma.com.

Exit codes: 0 fetched + verified; 2 invalid/blocked (missing key, missing
pin, Figma/network error, verification drift).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "screenshots"))

import builder as panels_builder
import output_guard as guard

EXIT_OK = 0
EXIT_INVALID = 2

FIGMA_API = "https://api.figma.com/v1"
TIMEOUT_S = 30


def api_base() -> str:
    """Figma REST base; FIGMA_API_BASE overrides it for hermetic tests."""
    return os.environ.get("FIGMA_API_BASE", FIGMA_API)


class FetchError(ValueError):
    """Fail-closed fetch error: unconfigured, unreachable, or drifted."""


def _get_json(url: str, token: str) -> dict:
    """GET a Figma REST endpoint (thin wrapper; tests monkeypatch it)."""
    req = urllib.request.Request(url, headers={"X-Figma-Token": token})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            raw = resp.read()
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise FetchError(f"figma request failed {url}: {exc}")
    try:
        obj = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise FetchError(f"figma response malformed {url}: {exc}")
    if not isinstance(obj, dict):
        raise FetchError(f"figma response not an object {url}")
    return obj


def _get_bytes(url: str) -> bytes:
    """GET raw bytes (signed image URLs carry no auth header)."""
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT_S) as resp:
            return resp.read()
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise FetchError(f"image download failed {url}: {exc}")


def fetch_bezel(*, node_id: str, file_key: str, images: dict,
                size: str, out_dir: Path) -> dict:
    """Download + verify one bezel; raises FetchError (no partial writes)."""
    url = images.get(node_id)
    if not isinstance(url, str) or not url:
        raise FetchError(
            f"figma rendered no image for node {node_id!r} "
            f"(file {file_key}); refusing to fabricate the {size} bezel")
    data = _get_bytes(url)
    if not data:
        raise FetchError(f"empty image bytes for node {node_id!r}")
    tmp = out_dir / (panels_builder.BEZEL_FILES[size] + ".part")
    tmp.write_bytes(data)
    try:
        if size == "6.9":
            info = panels_builder.verify_bezel_69(tmp)
        elif size == "6.3":
            info = panels_builder.verify_bezel_63(tmp)
        else:
            info = panels_builder.verify_bezel_ipad(tmp)
    except panels_builder.BuilderError as exc:
        tmp.unlink(missing_ok=True)
        raise FetchError(f"bezel verification failed ({size}, "
                         f"node {node_id!r}): {exc}")
    final = out_dir / panels_builder.BEZEL_FILES[size]
    tmp.replace(final)
    return {"file": str(final), "sha256": info["sha256"],
            "size": info["size"], "node_id": node_id}


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description="Fetch iPhone + iPad bezel PNGs from Figma (fail-closed).")
    ap.add_argument("--out", required=True,
                    help="external bezels dir (created; repo paths rejected)")
    ap.add_argument("--file-key", default=None,
                    help="Figma file key (default: $FIGMA_FILE_KEY)")
    ap.add_argument("--iphone-node", default=None,
                    help="iPhone 6.9 bezel node id (default: $FIGMA_IPHONE_NODE_ID)")
    ap.add_argument("--iphone63-node", default=None,
                    help="iPhone 6.3 bezel node id "
                         "(default: $FIGMA_IPHONE63_NODE_ID)")
    ap.add_argument("--ipad-node", default=None,
                    help="iPad bezel node id (default: $FIGMA_IPAD_NODE_ID)")
    ap.add_argument("--scale", default="2",
                    help="Figma image render scale (default 2: the pinned "
                         "980x2000 / 2300x3000 bezels verify at scale 2; "
                         "size drift still fails verification loudly)")
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    token = os.environ.get("FIGMA_API_KEY", "")
    if not token:
        print("invalid: FIGMA_API_KEY is not set; bezel fetch refuses "
              "unauthenticated Figma access", file=sys.stderr)
        return EXIT_INVALID
    file_key = args.file_key or os.environ.get("FIGMA_FILE_KEY", "")
    iphone_node = args.iphone_node or os.environ.get("FIGMA_IPHONE_NODE_ID",
                                                     "")
    iphone63_node = args.iphone63_node or os.environ.get(
        "FIGMA_IPHONE63_NODE_ID", "")
    ipad_node = args.ipad_node or os.environ.get("FIGMA_IPAD_NODE_ID", "")
    missing = [n for n, v in (("--file-key/FIGMA_FILE_KEY", file_key),
                              ("--iphone-node/FIGMA_IPHONE_NODE_ID",
                               iphone_node),
                              ("--iphone63-node/FIGMA_IPHONE63_NODE_ID",
                               iphone63_node),
                              ("--ipad-node/FIGMA_IPAD_NODE_ID", ipad_node))
               if not v]
    if missing:
        print(f"invalid: bezel source unpinned ({', '.join(missing)} "
              "missing); no default Figma file is guessed — pin the "
              "owner-approved Apple community file + node IDs, then retry",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        scale = float(args.scale)
    except ValueError:
        print(f"invalid: --scale must be a number, got {args.scale!r}",
              file=sys.stderr)
        return EXIT_INVALID
    if not 0.01 <= scale <= 4:
        print(f"invalid: --scale {args.scale!r} outside Figma range "
              "0.01..4", file=sys.stderr)
        return EXIT_INVALID

    try:
        out_dir = guard.resolve_out_root(args.out)
    except guard.GuardError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    out_dir.mkdir(parents=True, exist_ok=True)

    ids = ",".join(urllib.parse.quote(n, safe="") for n in
                   (iphone_node, iphone63_node, ipad_node))
    try:
        meta = _get_json(
            f"{api_base()}/images/{urllib.parse.quote(file_key, safe='')}"
            f"?ids={ids}&format=png&scale={args.scale}", token)
    except FetchError as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    if meta.get("err"):
        print(f"invalid: figma images error: {meta.get('err')}",
              file=sys.stderr)
        return EXIT_INVALID
    images = meta.get("images")
    if not isinstance(images, dict):
        print("invalid: figma images response missing 'images' object",
              file=sys.stderr)
        return EXIT_INVALID
    try:
        iphone = fetch_bezel(node_id=iphone_node, file_key=file_key,
                             images=images, size="6.9", out_dir=out_dir)
        iphone63 = fetch_bezel(node_id=iphone63_node, file_key=file_key,
                               images=images, size="6.3", out_dir=out_dir)
        ipad = fetch_bezel(node_id=ipad_node, file_key=file_key,
                           images=images, size="ipad13", out_dir=out_dir)
    except (FetchError, panels_builder.BuilderError) as exc:
        print(f"invalid: {exc}", file=sys.stderr)
        return EXIT_INVALID
    for got in (iphone, iphone63, ipad):
        print(f"wrote {got['file']} {got['sha256'][:12]}")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
