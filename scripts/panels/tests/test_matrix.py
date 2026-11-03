#!/usr/bin/env python3
"""Matrix render + bezel fetch + bundle README tests (hermetic).

Stdlib unittest + Pillow; no device, no network (Figma HTTP is faked by
monkeypatching the fetch module's thin wrappers). Synthetic capture runs
(frames + run manifests) and synthetic bezels are built in tmp dirs.
"""

import hashlib
import http.server
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
PANELS_CLI = str(HERE / "panels.py")
FETCH_CLI = str(HERE / "fetch_bezel_assets.py")
README_CLI = str(HERE / "write_bundle_readme.py")

sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "screenshots"))

import builder as panels_builder

try:
    from PIL import Image, ImageDraw  # noqa: E402
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

OWNER_EN = {
    "track": "Time tracking at your fingertips.",
    "insights": "See where your time goes.",
    "history_primary": "Every minute, at a glance.",
    "history_secondary": "For your eyes only.",
    "live_activity": "Your timer, always in view.",
    "add_entry": "All details you need.",
}

FRAME_COLORS_69 = {
    "track-running": (70, 130, 180),
    "insights": (90, 160, 90),
    "history": (180, 130, 70),
    "add-entry": (150, 100, 170),
    "la-lock": (100, 100, 140),
    "la-compact": (140, 100, 100),
    "la-expanded": (100, 140, 120),
}
FRAME_COLORS_IPAD = {
    "track-running": (70, 130, 180),
    "insights": (90, 160, 90),
    "history": (180, 130, 70),
    "add-entry": (150, 100, 170),
}

RU_SHORT = {
    "track": "Трек.",
    "insights": "Инсайты.",
    "history_primary": "История.",
    "history_secondary": "Личное.",
    "live_activity": "Таймер.",
    "add_entry": "Детали.",
}


def base_env() -> dict:
    env = dict(os.environ)
    env.pop("LIFIO_CAPTURE_LEASE", None)
    return env


def run_panels(*argv: str):
    return subprocess.run([sys.executable, PANELS_CLI, *argv],
                          capture_output=True, text=True, timeout=300,
                          env=base_env())


def run_fetch(*argv: str, extra_env: dict | None = None):
    env = base_env()
    env.pop("FIGMA_API_KEY", None)
    env.update(extra_env or {})
    return subprocess.run([sys.executable, FETCH_CLI, *argv],
                          capture_output=True, text=True, timeout=120,
                          env=env)


def run_readme(*argv: str):
    return subprocess.run([sys.executable, README_CLI, *argv],
                          capture_output=True, text=True, timeout=120,
                          env=base_env())


def write_manifest(path: Path, frames_dir: Path, run_id: str,
                   canvas: tuple[int, int], frames: tuple[str, ...]) -> None:
    recs = []
    for frame in frames:
        png = frames_dir / f"{frame}.png"
        recs.append({"frame": frame,
                     "screenshot_sha256": hashlib.sha256(
                         png.read_bytes()).hexdigest(),
                     "geometry": {"width": canvas[0], "height": canvas[1]}})
    path.write_text(json.dumps({
        "schema_version": 1, "run_id": run_id, "status": "complete",
        "deck_version": "en-austin-1", "treatment": "light-v1",
        "geometry": {"width": canvas[0], "height": canvas[1]},
        "frames": recs}), encoding="utf-8")


def make_run(shots: Path, device: str, language: str, run_id: str,
             canvas: tuple[int, int], colors: dict) -> None:
    run_dir = shots / device / language / "runs" / run_id
    frames_dir = run_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    for frame, color in colors.items():
        Image.new("RGB", canvas, color).save(frames_dir / f"{frame}.png")
    write_manifest(run_dir / "run-manifest.json", frames_dir, run_id,
                   canvas, tuple(colors))


def make_bezel_69_bytes() -> bytes:
    im = Image.new("RGBA", (980, 2000), (20, 20, 20, 255))
    ImageDraw.Draw(im).rectangle([50, 44, 50 + 880, 44 + 1912],
                                 fill=(0, 0, 0, 0))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def make_bezel_63_bytes() -> bytes:
    """Synthetic 6.3 bezel passing verify_bezel_63 (sharp slot + pill)."""
    bw, bh, sw, sh, ax, ay = 880, 1800, 804, 1748, 38, 26
    im = Image.new("RGBA", (bw, bh), (20, 20, 20, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([ax, ay, ax + sw, ay + sh], fill=(0, 0, 0, 0))
    d.rounded_rectangle([ax + sw // 2 - 90, ay + 30,
                         ax + sw // 2 + 90, ay + 30 + 64],
                        radius=32, fill=(20, 20, 20, 255))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def make_bezel_ipad_bytes() -> bytes:
    im = Image.new("RGBA", (2300, 3000), (200, 200, 200, 255))
    ImageDraw.Draw(im).rectangle([118, 124, 118 + 2064, 124 + 2752],
                                 fill=(0, 0, 0, 0))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def write_bezels(bezels: Path) -> None:
    bezels.mkdir(parents=True, exist_ok=True)
    (bezels / panels_builder.BEZEL_FILES["6.9"]).write_bytes(
        make_bezel_69_bytes())
    (bezels / panels_builder.BEZEL_FILES["6.3"]).write_bytes(
        make_bezel_63_bytes())
    (bezels / panels_builder.BEZEL_FILES["ipad13"]).write_bytes(
        make_bezel_ipad_bytes())


def write_captions(path: Path, locale: str, texts: dict) -> None:
    caps = {k: {"text": texts[k], "en": OWNER_EN[k]}
            for k in panels_builder.CAPTION_KEYS}
    path.write_text(json.dumps({"locale": locale, "version": "captions-v1",
                                "status": "test fixture",
                                "captions": caps}), encoding="utf-8")


def make_shots_matrix(root: Path) -> Path:
    """Synthetic shots dir: iphone69 en/ru + ipad13 en/ru, r1 runs."""
    shots = root / "shots"
    make_run(shots, "iphone69", "en", "iphone69-en-r1", (1320, 2868),
             FRAME_COLORS_69)
    make_run(shots, "iphone69", "ru", "iphone69-ru-r1", (1320, 2868),
             FRAME_COLORS_69)
    make_run(shots, "ipad13", "en", "ipad13-en-r1", (2064, 2752),
             FRAME_COLORS_IPAD)
    make_run(shots, "ipad13", "ru", "ipad13-ru-r1", (2064, 2752),
             FRAME_COLORS_IPAD)
    return shots


def make_captions_dir(root: Path) -> Path:
    caps = root / "captions"
    caps.mkdir(parents=True, exist_ok=True)
    write_captions(caps / "ru.json", "ru", RU_SHORT)
    return caps


@unittest.skipUnless(HAS_PILLOW, "Pillow required")
class RenderMatrixTests(unittest.TestCase):
    def test_matrix_en_two_devices_green(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69","ipad13"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("status=complete", proc.stdout)
            self.assertEqual(
                len(list((out / "iphone69" / "en").glob(
                    "panel-*-en-1320x2868.png"))), 5)
            self.assertEqual(
                len(list((out / "ipad13" / "en").glob(
                    "panel-*-en-2064x2752.png"))), 4)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["status"], "complete")
            self.assertEqual(manifest["counts"],
                             {"blocked": 0, "cells": 2, "rendered": 2})
            for cell in manifest["cells"]:
                self.assertEqual(cell["status"], "rendered")
                self.assertEqual(len(cell["selftest"]),
                                 len(cell["panels"]))

    def test_matrix_non_en_with_captions_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            bezels = root / "bezels"
            write_bezels(bezels)
            caps = make_captions_dir(root)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["ipad13"]',
                "--languages", '["ru"]',
                "--captions-dir", str(caps))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(
                len(list((out / "ipad13" / "ru").glob(
                    "panel-*-ru-2064x2752.png"))), 4)

    def test_matrix_non_en_without_captions_dir_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en","ru"]')
            self.assertEqual(proc.returncode, 2)
            self.assertIn("ru", proc.stderr)
            self.assertIn("captions", proc.stderr)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["status"], "incomplete")
            by_lang = {c["language"]: c for c in manifest["cells"]}
            self.assertEqual(by_lang["en"]["status"], "rendered")
            self.assertEqual(by_lang["ru"]["status"], "blocked")

    def test_matrix_dropped_device_rejected_at_catalog_gate(self):
        # Owner lineup 2026-11-03 dropped iphone65: the matrix catalog no
        # longer lists it, so a stale dispatch key fails closed as an
        # unknown device (exit 2) before any cell renders — never stretched.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            (shots / "iphone65" / "en" / "runs").mkdir(parents=True)
            bezels = root / "bezels"
            bezels.mkdir()
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone65"]', "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            self.assertIn("unknown device", proc.stderr)
            self.assertFalse((out / "matrix-manifest.json").exists())

    def test_matrix_63_en_green(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone63", "en", "iphone63-en-r1",
                     (1206, 2622), FRAME_COLORS_69)
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone63"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("status=complete", proc.stdout)
            built = list((out / "iphone63" / "en").glob(
                "panel-*-en-1206x2622.png"))
            self.assertEqual(len(built), 5)
            for png in built:
                with Image.open(png) as im:
                    self.assertEqual(im.size, (1206, 2622))
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["status"], "complete")
            self.assertEqual(manifest["counts"],
                             {"blocked": 0, "cells": 1, "rendered": 1})
            cell = manifest["cells"][0]
            self.assertEqual(cell["status"], "rendered")
            self.assertEqual(cell["size"], "6.3")
            self.assertEqual(cell["run_id"], "iphone63-en-r1")
            self.assertEqual(cell["template_version"],
                             panels_builder.TEMPLATE_69)
            self.assertEqual(len(cell["selftest"]), 5)
            recipe_path = Path(cell["recipe_file"])
            recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
            self.assertEqual(recipe.get("template_variant"), "v13-scaled-63")
            self.assertEqual(recipe["canvas"], {"width": 1206,
                                                "height": 2622})

    def test_matrix_63_r2_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone63", "en", "iphone63-en-r2",
                     (1206, 2622), FRAME_COLORS_69)
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone63"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 0, proc.stderr)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["run_id"],
                             "iphone63-en-r2")

    def test_matrix_63_missing_bezel_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone63", "en", "iphone63-en-r1",
                     (1206, 2622), FRAME_COLORS_69)
            bezels = root / "bezels"
            bezels.mkdir()
            (bezels / panels_builder.BEZEL_FILES["6.9"]).write_bytes(
                make_bezel_69_bytes())
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone63"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            self.assertIn("missing bezel asset", proc.stderr)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")

    def test_matrix_missing_run_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            (shots / "iphone69" / "en").mkdir(parents=True)
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]', "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            self.assertIn("no r1/r2 run", proc.stderr)

    def test_matrix_missing_bezels_dir_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(root / "no-bezels"),
                "--out", str(root / "out"),
                "--devices", '["iphone69"]', "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            self.assertIn("bezels dir not found", proc.stderr)

    def test_matrix_unknown_device_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            bezels = root / "bezels"
            write_bezels(bezels)
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(root / "out"),
                "--devices", '["flip-phone"]', "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            self.assertIn("unknown device", proc.stderr)

    def test_matrix_bad_json_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            bezels = root / "bezels"
            write_bezels(bezels)
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(root / "out"),
                "--devices", 'iphone69', "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)

    def test_matrix_repo_out_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            bezels = root / "bezels"
            write_bezels(bezels)
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels),
                "--out", str(HERE / "matrix-out"),
                "--devices", '["iphone69"]', "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            self.assertIn("inside the repository", proc.stderr)

    def test_matrix_mode_rejects_single_flags(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(Path(tmp)),
                "--bezels-dir", str(Path(tmp)),
                "--out", str(Path(tmp) / "out"),
                "--devices", '["iphone69"]', "--languages", '["en"]',
                "--locale", "en")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("single-render only", proc.stderr)

    def test_single_mode_rejects_matrix_flags(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run_panels(
                "--locale", "en", "--size", "6.9",
                "--panels-dir", str(Path(tmp)),
                "--captions", str(HERE / "captions_en.json"),
                "--shots-dir", str(Path(tmp)))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("matrix-only", proc.stderr)

    def test_single_mode_still_requires_flags(self):
        proc = run_panels("--locale", "en")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("--size is required", proc.stderr)


@unittest.skipUnless(HAS_PILLOW, "Pillow required")
class FetchBezelTests(unittest.TestCase):
    """Hermetic Figma fakes: localhost HTTP, never api.figma.com."""

    def start_fake_figma(self, meta: dict, blobs: dict) -> str:
        """Serve one fake Figma REST base on localhost; returns the base.

        `meta`/`blobs` are read at request time, so callers may fill them
        after learning the base URL (image URLs must point at this server).
        """

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802
                if self.path.startswith("/v1/images/"):
                    body = json.dumps(meta).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                elif self.path in blobs:
                    body = blobs[self.path]
                    self.send_response(200)
                    self.send_header("Content-Type", "image/png")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                else:
                    self.send_response(404)
                    self.end_headers()

            def log_message(self, *args):
                pass

        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(srv.shutdown)
        host, port = srv.server_address
        return f"http://{host}:{port}/v1"

    def fake_env(self, base: str) -> dict:
        return {"FIGMA_API_KEY": "test-token", "FIGMA_API_BASE": base}

    def test_missing_api_key_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run_fetch("--out", str(Path(tmp) / "bezels"),
                             "--file-key", "F",
                             "--iphone-node", "1:1", "--ipad-node", "2:2")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("FIGMA_API_KEY", proc.stderr)

    def test_missing_pin_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run_fetch("--out", str(Path(tmp) / "bezels"),
                             extra_env={"FIGMA_API_KEY": "tok"})
            self.assertEqual(proc.returncode, 2)
            self.assertIn("unpinned", proc.stderr)

    def test_partial_pin_names_iphone63(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run_fetch("--out", str(Path(tmp) / "bezels"),
                             "--file-key", "F",
                             "--iphone-node", "1:1",
                             "--ipad-node", "2:2",
                             extra_env={"FIGMA_API_KEY": "tok"})
            self.assertEqual(proc.returncode, 2)
            self.assertIn("unpinned", proc.stderr)
            self.assertIn("FIGMA_IPHONE63_NODE_ID", proc.stderr)

    def test_figma_error_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = self.start_fake_figma({"err": "Not found"}, {})
            proc = run_fetch("--out", str(Path(tmp) / "bezels"),
                             "--file-key", "F",
                             "--iphone-node", "1:1",
                             "--iphone63-node", "3:3",
                             "--ipad-node", "2:2",
                             extra_env=self.fake_env(base))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("figma images error", proc.stderr)

    def test_missing_node_image_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = self.start_fake_figma(
                {"err": "", "images": {"1:1": None}}, {})
            proc = run_fetch("--out", str(Path(tmp) / "bezels"),
                             "--file-key", "F",
                             "--iphone-node", "1:1",
                             "--iphone63-node", "3:3",
                             "--ipad-node", "2:2",
                             extra_env=self.fake_env(base))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("rendered no image", proc.stderr)

    def test_missing_63_node_image_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            holder: dict = {}
            base = self.start_fake_figma(holder, {
                "/v1/img/iphone.png": make_bezel_69_bytes()})
            holder.update({"err": "", "images": {
                "1:1": f"{base}/img/iphone.png", "3:3": None}})
            proc = run_fetch("--out", str(Path(tmp) / "bezels"),
                             "--file-key", "F",
                             "--iphone-node", "1:1",
                             "--iphone63-node", "3:3",
                             "--ipad-node", "2:2",
                             extra_env=self.fake_env(base))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("rendered no image", proc.stderr)
            self.assertIn("3:3", proc.stderr)

    def test_network_error_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {"FIGMA_API_KEY": "tok",
                   "FIGMA_API_BASE": "http://127.0.0.1:1/v1"}
            proc = run_fetch("--out", str(Path(tmp) / "bezels"),
                             "--file-key", "F",
                             "--iphone-node", "1:1",
                             "--iphone63-node", "3:3",
                             "--ipad-node", "2:2",
                             extra_env=env)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("figma request failed", proc.stderr)

    def test_happy_path_writes_verified_bezels(self):
        with tempfile.TemporaryDirectory() as tmp:
            holder: dict = {}
            base = self.start_fake_figma(holder, {
                "/v1/img/iphone.png": make_bezel_69_bytes(),
                "/v1/img/iphone63.png": make_bezel_63_bytes(),
                "/v1/img/ipad.png": make_bezel_ipad_bytes()})
            holder.update({"err": "", "images": {
                "1:1": f"{base}/img/iphone.png",
                "3:3": f"{base}/img/iphone63.png",
                "2:2": f"{base}/img/ipad.png"}})
            out = Path(tmp) / "bezels"
            proc = run_fetch("--out", str(out),
                             "--file-key", "F",
                             "--iphone-node", "1:1",
                             "--iphone63-node", "3:3",
                             "--ipad-node", "2:2",
                             extra_env=self.fake_env(base))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            iphone = out / panels_builder.BEZEL_FILES["6.9"]
            iphone63 = out / panels_builder.BEZEL_FILES["6.3"]
            ipad = out / panels_builder.BEZEL_FILES["ipad13"]
            self.assertTrue(iphone.is_file())
            self.assertTrue(iphone63.is_file())
            self.assertTrue(ipad.is_file())
            panels_builder.verify_bezel_69(iphone)
            info63 = panels_builder.verify_bezel_63(iphone63)
            self.assertEqual(info63["screen_slot_px"], [805, 1749])
            self.assertEqual(info63["screen_at_px"], [38, 26])
            panels_builder.verify_bezel_ipad(ipad)

    def test_size_drift_fails_closed_without_partial(self):
        bad = io.BytesIO()
        Image.new("RGBA", (100, 100), (0, 0, 0, 255)).save(bad, format="PNG")
        with tempfile.TemporaryDirectory() as tmp:
            holder = {}
            base = self.start_fake_figma(holder, {
                "/v1/img/iphone.png": bad.getvalue(),
                "/v1/img/iphone63.png": bad.getvalue(),
                "/v1/img/ipad.png": bad.getvalue()})
            holder.update({"err": "", "images": {
                "1:1": f"{base}/img/iphone.png",
                "3:3": f"{base}/img/iphone63.png",
                "2:2": f"{base}/img/ipad.png"}})
            out = Path(tmp) / "bezels"
            proc = run_fetch("--out", str(out),
                             "--file-key", "F",
                             "--iphone-node", "1:1",
                             "--iphone63-node", "3:3",
                             "--ipad-node", "2:2",
                             extra_env=self.fake_env(base))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("bezel verification failed", proc.stderr)
            self.assertFalse(
                (out / panels_builder.BEZEL_FILES["6.9"]).exists())
            self.assertFalse(list(out.glob("*.part")))


class BundleReadmeTests(unittest.TestCase):
    def test_readme_happy_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            panels_dir = root / "panels"
            (panels_dir / "iphone69" / "en").mkdir(parents=True)
            (panels_dir / "matrix-manifest.json").write_text(
                json.dumps({
                    "schema_version": 1, "status": "complete",
                    "counts": {"cells": 1, "rendered": 1, "blocked": 0},
                    "cells": [{"device": "iphone69", "language": "en",
                               "size": "6.9", "status": "rendered",
                               "run_id": "iphone69-en-r1",
                               "captions_version": "captions-v1",
                               "panels": {"a.png": "abc"}}]}),
                encoding="utf-8")
            Image.new("RGB", (8, 8)).save(
                panels_dir / "iphone69" / "en" / "panel-track-en-8x8.png")
            out = root / "bundle-readme.md"
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69"]', "--languages", '["en"]',
                "--out", str(out),
                "--commit", "deadbee", "--dirty", "false")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            text = out.read_text(encoding="utf-8")
            for needle in ("iphone69", "iOS 27.0", "deadbee", "dirty: false",
                           "en-austin-1", "light-v1", "iphone69-en-r1",
                           "REVIEW SET ONLY", "panel-track-en-8x8.png",
                           "1320x2868"):
                self.assertIn(needle, text)

    def test_readme_unverified_deck_marked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            (shots / "ipad13" / "ru").mkdir(parents=True)
            panels_dir = root / "panels"
            panels_dir.mkdir()
            out = root / "readme.md"
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["ipad13"]', "--languages", '["ru"]',
                "--out", str(out),
                "--commit", "x", "--dirty", "true")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("unverified",
                          out.read_text(encoding="utf-8"))

    def test_readme_missing_panels_dir_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            proc = run_readme(
                "--panels-dir", str(root / "no-panels"),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69"]', "--languages", '["en"]',
                "--out", str(root / "readme.md"))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("panels dir not found", proc.stderr)

    def test_readme_unknown_device_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            panels_dir = root / "panels"
            panels_dir.mkdir()
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["watch"]', "--languages", '["en"]',
                "--out", str(root / "readme.md"))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("unknown device", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
