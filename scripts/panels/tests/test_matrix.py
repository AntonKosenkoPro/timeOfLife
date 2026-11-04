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

# Session-evidence fixture pins (mirror scripts/screenshots session contract;
# consumed strictly via session_evidence.validate_run_evidence — never
# reimplemented here). Two nonces per run: one pinned, one realtime.
NONCE_PINNED = "0123456789abcdef0123456789abcdef"
NONCE_REALTIME = "fedcba9876543210fedcba9876543210"
APP_FRAMES = ("track-running", "insights", "history", "add-entry")
LA_FRAMES = ("la-lock", "la-compact", "la-expanded")
IPAD_LOCK_COLOR = (110, 110, 150)
# Attested iPad model — REAL catalog identifier (8GB variant only, not
# the unsuffixed family name): the shared validator requires an exact
# cataloged model. Name is operator-assigned evidence (presence, not
# value); udid must equal the run's unanimous frame device_udid.
IPAD_MODEL_ID = ("com.apple.CoreSimulator.SimDeviceType."
                 "iPad-Pro-13-inch-M4-8GB")
IPAD_MODEL_NAME = "shot-ci-ipad13"


def attested_probe(device: str, run_id: str,
                   canvas: tuple[int, int]) -> dict:
    """Producer-shaped attested island probe (simctl-list source)."""
    return {
        "schema_version": 1,
        "device_key": device,
        "island_available": False,
        "reason": "capability probe: no Dynamic Island",
        "run_id": run_id,
        "session_nonce": NONCE_REALTIME,
        "geometry": {"width": canvas[0], "height": canvas[1]},
        "model": {"deviceTypeIdentifier": IPAD_MODEL_ID,
                  "name": IPAD_MODEL_NAME,
                  "udid": "UDID-1"},
        "source": "simctl-list",
    }


def _req_sha(run_id: str, frame: str) -> str:
    return hashlib.sha256(f"req-{run_id}-{frame}".encode()).hexdigest()


def _domain_of(frame: str) -> str:
    return "pinned" if frame in APP_FRAMES else "realtime"


def _nonce_of(frame: str) -> str:
    return NONCE_PINNED if frame in APP_FRAMES else NONCE_REALTIME

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
                   canvas: tuple[int, int], frames: tuple[str, ...],
                   ci_approval_bypass: bool | None = None,
                   device: str = "iphone69",
                   la_capture: str = "genuine") -> None:
    """Session-valid manifest + frame records + receipts (+ iPad probe).

    la_capture: "genuine" (external-lock-screen with window/observation
    binding) or "pending" (external-lock-screen-pending with reason).
    PNG files must already exist in frames_dir; their hashes are bound.
    Frame record JSONs and session receipts are written alongside so the
    shared session_evidence validator passes strictly.
    """
    run_dir = path.parent
    sessions_dir = run_dir / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    # Per-domain seq counters (pinned 0..n, realtime 0..m).
    seq_counters = {"pinned": 0, "realtime": 0}
    recs = []
    transcripts: dict[str, list[dict]] = {}
    for frame in frames:
        png = frames_dir / f"{frame}.png"
        sha_png = hashlib.sha256(png.read_bytes()).hexdigest()
        domain = _domain_of(frame)
        seq = seq_counters[domain]
        seq_counters[domain] += 1
        sha_req = _req_sha(run_id, frame)
        rec: dict = {
            "schema_version": 1, "frame": frame,
            "mode": ("app-clock-pinned" if domain == "pinned"
                     else "live-activity-realtime"),
            "device_udid": "UDID-1", "device_key": device,
            "run_id": run_id,
            "deck_version": "en-austin-1", "treatment": "light-v1",
            "request_sha256": sha_req,
            "request_semantic_sha256": "b" * 64,
            "screenshot_sha256": sha_png,
            "geometry": {"width": canvas[0], "height": canvas[1]},
            "expected_totals": {"all_seconds": 1, "today_seconds": 1,
                                "week_seconds": 1,
                                "category_seconds": {"A": 1},
                                "text_seconds": {"B": 1}},
            "session_nonce": _nonce_of(frame),
            "session_domain": domain, "seq": seq,
        }
        if domain == "pinned":
            rec["capture"] = "native-simctl"
        elif la_capture == "genuine":
            rec["capture"] = "external-lock-screen"
            rec["capture_window"] = {
                "started_at": "2026-10-30T10:00:00+00:00",
                "captured_at_iso": "2026-10-30T10:00:10+00:00",
                "observed_elapsed_s": 10,
            }
            rec["observation_sha256"] = "d" * 64
        else:
            rec["capture"] = "external-lock-screen-pending"
            rec["captured_at_iso"] = "2026-10-30T10:00:10+00:00"
            rec["pending_reason"] = "CI simctl pixels; human handoff"
        (frames_dir / f"{frame}.json").write_text(
            json.dumps(rec, sort_keys=True), encoding="utf-8")
        recs.append(rec)
        nonce = rec["session_nonce"]
        transcripts.setdefault(nonce, []).append(
            {"seq": seq, "frame": frame, "request_sha256": sha_req,
             "request_semantic_sha256": "b" * 64})
    for nonce, transcript in transcripts.items():
        domain = ("pinned" if nonce == NONCE_PINNED else "realtime")
        receipt = {
            "schema_version": 1, "session_nonce": nonce,
            "run_id": run_id, "session_domain": domain,
            "final_seq": max(r["seq"] for r in transcript),
            "status": "complete", "failures": [],
            "transcript": sorted(transcript, key=lambda r: r["seq"]),
            "app_cleanup": {"status": "cleaned",
                            "removed_session": True,
                            "removed_session_queue": True,
                            "ended_activity_ids": []},
            "runner_verified": {"chrome_restored": True,
                                "process_terminated": True,
                                "lease_released": True},
        }
        (sessions_dir / f"{nonce}.receipt.json").write_text(
            json.dumps(receipt, sort_keys=True), encoding="utf-8")
    if device == "ipad13":
        probe = attested_probe(device, run_id, canvas)
        (sessions_dir / "island-probe.json").write_text(
            json.dumps(probe, sort_keys=True), encoding="utf-8")
    manifest: dict = {
        "schema_version": 1, "run_id": run_id, "status": "complete",
        "deck_version": "en-austin-1", "treatment": "light-v1",
        "geometry": {"width": canvas[0], "height": canvas[1]},
        "frames": recs}
    if device == "ipad13":
        # Producer-faithful N/A metadata (run_manifest.assemble shape):
        # explicit scope + embedded probe copy alongside the probe file.
        manifest["na_frames"] = ["la-compact", "la-expanded"]
        manifest["island_probe"] = probe
    if ci_approval_bypass is not None:
        manifest["ci_approval_bypass"] = ci_approval_bypass
    path.write_text(json.dumps(manifest), encoding="utf-8")


def make_run(shots: Path, device: str, language: str, run_id: str,
             canvas: tuple[int, int], colors: dict,
             ci_approval_bypass: bool | None = None,
             la_capture: str = "genuine") -> None:
    run_dir = shots / device / language / "runs" / run_id
    frames_dir = run_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    frames = dict(colors)
    if device == "ipad13" and "la-lock" not in frames:
        frames["la-lock"] = IPAD_LOCK_COLOR
    for frame, color in frames.items():
        Image.new("RGB", canvas, color).save(frames_dir / f"{frame}.png")
    write_manifest(run_dir / "run-manifest.json", frames_dir, run_id,
                   canvas, tuple(frames),
                   ci_approval_bypass=ci_approval_bypass,
                   device=device, la_capture=la_capture)


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

    def test_readme_ci_bypass_surfaces(self):
        # Round-2 (PR #225): a CI bundle (gates satisfied by
        # LIFIO_CAPTURE_CI=1, ci_approval_bypass:true) must never read as
        # owner-approved at handoff — the README carries the bypass flag.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69, ci_approval_bypass=True)
            panels_dir = root / "panels"
            panels_dir.mkdir()
            out = root / "readme.md"
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69"]', "--languages", '["en"]',
                "--out", str(out),
                "--commit", "x", "--dirty", "false")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertIn("NOT OWNER-APPROVED", text)
            self.assertIn("ci_approval_bypass", text)
            self.assertIn("True", text)

    def test_readme_explicit_approval_clears_bypass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69, ci_approval_bypass=False)
            panels_dir = root / "panels"
            panels_dir.mkdir()
            out = root / "readme.md"
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69"]', "--languages", '["en"]',
                "--out", str(out),
                "--commit", "x", "--dirty", "false")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertNotIn("NOT OWNER-APPROVED", text)
            self.assertIn("ci_approval_bypass:false", text)

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

    def test_readme_handoff_vs_complete_labeling(self):
        # Task 6.7: an incomplete matrix must read as a handoff/debug
        # bundle, never as a complete approved set; a complete matrix
        # still carries REVIEW SET ONLY (never owner-approved).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            panels_dir = root / "panels"
            panels_dir.mkdir()
            (panels_dir / "matrix-manifest.json").write_text(
                json.dumps({
                    "schema_version": 1, "status": "incomplete",
                    "counts": {"cells": 2, "rendered": 1, "blocked": 1},
                    "cells": [
                        {"device": "iphone69", "language": "en",
                         "size": "6.9", "status": "rendered",
                         "run_id": "iphone69-en-r1",
                         "captions_version": "captions-v1",
                         "panels": {"a.png": "abc"}},
                        {"device": "iphone69", "language": "ru",
                         "size": "6.9", "status": "blocked",
                         "reason": "session receipt missing"},
                    ]}), encoding="utf-8")
            out = root / "readme.md"
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69"]',
                "--languages", '["en","ru"]',
                "--out", str(out),
                "--commit", "x", "--dirty", "false")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertIn("HANDOFF", text)
            self.assertIn("blocked", text)
            self.assertIn("approves nothing", text)
            self.assertNotIn("NOT OWNER-APPROVED", text.replace(
                "CI CAPTURE — NOT OWNER-APPROVED", ""))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            panels_dir = root / "panels"
            panels_dir.mkdir()
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
            out = root / "readme.md"
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69"]', "--languages", '["en"]',
                "--out", str(out),
                "--commit", "x", "--dirty", "false")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertIn("COMPLETE", text)
            self.assertIn("REVIEW SET ONLY", text)
            self.assertIn("approves nothing", text)


@unittest.skipUnless(HAS_PILLOW, "Pillow required")
class SessionEvidenceConsumerTests(unittest.TestCase):
    """Task 6.7 consumer gate: strict shared-helper evidence, no weaker
    duplicate verification. Each test drives the real panels CLI matrix
    path so blocked cells surface with explicit reasons."""

    def _matrix(self, shots, bezels, out, devices, languages,
                captions_dir=None):
        argv = ["--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", json.dumps(devices),
                "--languages", json.dumps(languages)]
        if captions_dir is not None:
            argv += ["--captions-dir", str(captions_dir)]
        return run_panels(*argv)

    def _setup(self, tmp: str):
        root = Path(tmp)
        shots = root / "shots"
        bezels = root / "bezels"
        write_bezels(bezels)
        return root, shots, bezels

    def test_missing_receipt_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
            for receipt in (run_dir / "sessions").glob("*.receipt.json"):
                receipt.unlink()
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("receipt",
                          manifest["cells"][0]["reason"].lower())

    def test_partial_receipt_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
            receipt_path = run_dir / "sessions" / f"{NONCE_PINNED}.receipt.json"
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            receipt["status"] = "partial"
            receipt["failures"] = ["cleanup failed"]
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("partial",
                          manifest["cells"][0]["reason"].lower())

    def test_missing_queue_proof_blocks(self):
        # Shared-validator queue proof: a complete receipt without
        # app_cleanup.removed_session_queue:true must block (fixed old
        # acks stay fixed). No local guard — helper-owned.
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
            receipt_path = run_dir / "sessions" / f"{NONCE_PINNED}.receipt.json"
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            del receipt["app_cleanup"]["removed_session_queue"]
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("removed_session_queue",
                          manifest["cells"][0]["reason"])

    def test_false_queue_proof_blocks(self):
        # removed_session_queue:false (queue dir survived) must block.
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
            receipt_path = run_dir / "sessions" / f"{NONCE_PINNED}.receipt.json"
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            receipt["app_cleanup"]["removed_session_queue"] = False
            receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("removed_session_queue",
                          manifest["cells"][0]["reason"])

    def test_tampered_png_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
            png = run_dir / "frames" / "history.png"
            png.write_bytes(png.read_bytes() + b"\x00")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")

    def test_foreign_receipt_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
            src = run_dir / "sessions" / f"{NONCE_PINNED}.receipt.json"
            receipt = json.loads(src.read_text(encoding="utf-8"))
            src.unlink()
            receipt["session_nonce"] = "f" * 32
            (run_dir / "sessions" / ("f" * 32 + ".receipt.json")).write_text(
                json.dumps(receipt), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("nonce",
                          manifest["cells"][0]["reason"].lower())

    def test_pending_la_blocks_whole_cell(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69,
                     la_capture="pending")
            run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
            manifest_path = run_dir / "run-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["status"] = "needs-inspection"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            cell_manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(cell_manifest["cells"][0]["status"], "blocked")
            self.assertEqual(cell_manifest["status"], "incomplete")

    def _honest_pending_iphone(self, tmp: str):
        """Honest pending session run: valid receipts, pending LA records,
        manifest status needs-inspection (finalize shape); disk untouched
        by callers except via the returned manifest object."""
        _root, shots, bezels = self._setup(tmp)
        make_run(shots, "iphone69", "en", "iphone69-en-r1",
                 (1320, 2868), FRAME_COLORS_69, la_capture="pending")
        run_dir = shots / "iphone69" / "en" / "runs" / "iphone69-en-r1"
        manifest_path = run_dir / "run-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["status"] = "needs-inspection"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        return shots, bezels, run_dir, manifest_path

    def test_manifest_status_flip_only_blocked(self):
        # AUDIT R1a (bypass): honest pending run, manifest top status
        # flipped to complete, disk records/PNGs/receipts untouched →
        # must block. Currently RED: builder trusts status → renders.
        # Fix is runner-owned (disk semantic/evidence agreement + status
        # eligibility in the shared helper); no local guard here.
        with tempfile.TemporaryDirectory() as tmp:
            shots, bezels, _run_dir, manifest_path = \
                self._honest_pending_iphone(tmp)
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["status"] = "complete"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            cell_manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(cell_manifest["cells"][0]["status"], "blocked")

    def test_manifest_genuine_invention_blocked(self):
        # AUDIT R1b (bypass): honest pending run, manifest LA records
        # rewritten to self-consistent genuine (capture_window +
        # observation binding invented) + status complete, disk untouched
        # → must block. Currently RED: helper does not compare manifest
        # capture semantics against disk. Runner-owned fix; no local
        # guard here.
        with tempfile.TemporaryDirectory() as tmp:
            shots, bezels, _run_dir, manifest_path = \
                self._honest_pending_iphone(tmp)
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for rec in manifest["frames"]:
                if rec["frame"] in LA_FRAMES:
                    rec["capture"] = "external-lock-screen"
                    rec["capture_window"] = {
                        "started_at": "2026-10-30T10:00:00+00:00",
                        "captured_at_iso": "2026-10-30T10:00:10+00:00",
                        "observed_elapsed_s": 10,
                    }
                    rec["observation_sha256"] = "e" * 64
                    rec.pop("pending_reason", None)
            manifest["status"] = "complete"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["iphone69"], ["en"])
            self.assertEqual(proc.returncode, 2)
            cell_manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(cell_manifest["cells"][0]["status"], "blocked")

    def test_ipad_forged_probe_udid_blocked(self):
        # Forged model UDID must fail (runner: strict model schema fix
        # pending). Currently RED: helper ignores model.udid.
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            probe_path = run_dir / "sessions" / "island-probe.json"
            probe = json.loads(probe_path.read_text(encoding="utf-8"))
            probe["model"] = dict(probe["model"], udid="UDID-FORGED")
            probe_path.write_text(json.dumps(probe), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")

    def test_ipad_na_probe_correct_subset_renders(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 0, proc.stderr)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "rendered")

    def test_ipad_missing_probe_blocked(self):
        # MANDATORY negative (contract §6 / spec probed N/A): an iPad run
        # with no island probe must block — N/A is never inferred from
        # missing PNGs. Currently RED: the shared helper passes probeless
        # runs when island frames aren't required; awaiting runner fix.
        # No local duplicate guard — helper-owned.
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            (run_dir / "sessions" / "island-probe.json").unlink()
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("probe",
                          manifest["cells"][0]["reason"].lower())

    def test_ipad_na_metadata_removed_blocked(self):
        # Downgrade guard: stripping the producer's N/A metadata
        # (manifest na_frames/island_probe + probe file) must not sneak an
        # unattested run through. Currently RED for the same helper gap as
        # missing-probe; awaiting runner fix. No local duplicate guard.
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            (run_dir / "sessions" / "island-probe.json").unlink()
            manifest_path = run_dir / "run-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest.pop("na_frames", None)
            manifest.pop("island_probe", None)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            cell_manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(cell_manifest["cells"][0]["status"], "blocked")

    def test_ipad_forged_probe_model_blocked(self):
        # Helper-owned attestation: an island-reporting model refuses N/A.
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            probe_path = run_dir / "sessions" / "island-probe.json"
            probe = json.loads(probe_path.read_text(encoding="utf-8"))
            probe["model"] = {
                "deviceTypeIdentifier":
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max",
                "name": "iPhone 17 Pro Max", "udid": "UDID-9"}
            probe_path.write_text(json.dumps(probe), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("probe",
                          manifest["cells"][0]["reason"].lower())

    def test_ipad_forged_probe_device_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            probe_path = run_dir / "sessions" / "island-probe.json"
            probe = json.loads(probe_path.read_text(encoding="utf-8"))
            probe["device_key"] = "iphone69"
            probe_path.write_text(json.dumps(probe), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("probe",
                          manifest["cells"][0]["reason"].lower())

    def test_ipad_forged_probe_geometry_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            probe_path = run_dir / "sessions" / "island-probe.json"
            probe = json.loads(probe_path.read_text(encoding="utf-8"))
            probe["geometry"] = {"width": 1320, "height": 2868}
            probe_path.write_text(json.dumps(probe), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("probe",
                          manifest["cells"][0]["reason"].lower())

    def test_ipad_forged_probe_nonce_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            probe_path = run_dir / "sessions" / "island-probe.json"
            probe = json.loads(probe_path.read_text(encoding="utf-8"))
            probe["session_nonce"] = "f" * 32
            probe_path.write_text(json.dumps(probe), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("probe",
                          manifest["cells"][0]["reason"].lower())

    def test_ipad_fabricated_island_blocked(self):
        # Helper-owned fabrication gate: island pixels+record filed beside
        # an N/A probe are refused (manifest entry forces helper coverage).
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            Image.new("RGB", (2064, 2752), (1, 2, 3)).save(
                run_dir / "frames" / "la-compact.png")
            manifest_path = run_dir / "run-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            lock_rec = next(r for r in manifest["frames"]
                            if r["frame"] == "la-lock")
            forged = dict(lock_rec, frame="la-compact")
            (run_dir / "frames" / "la-compact.json").write_text(
                json.dumps(forged, sort_keys=True), encoding="utf-8")
            manifest["frames"].append(forged)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            cell_manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(cell_manifest["cells"][0]["status"], "blocked")
            self.assertIn("fabricat",
                          cell_manifest["cells"][0]["reason"].lower())

    def test_ipad_missing_lock_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            _root, shots, bezels = self._setup(tmp)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            run_dir = shots / "ipad13" / "en" / "runs" / "ipad13-en-r1"
            (run_dir / "frames" / "la-lock.png").unlink()
            out = Path(tmp) / "out"
            proc = self._matrix(shots, bezels, out, ["ipad13"], ["en"])
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("la-lock",
                          manifest["cells"][0]["reason"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
