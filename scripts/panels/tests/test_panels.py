#!/usr/bin/env python3
"""Panel builder tests (stdlib unittest + Pillow; no device, no network).

Hermetic core (synthetic frames/bezel/manifest in tmp dirs) runs anywhere
Pillow is installed. Retained byte-identical proofs (`test_retained_*`)
run only when the external retention root is present, else skip — they
prove the in-git builder reproduces the owner-approved EN compositions
byte-for-byte. CLI tests run the real `panels.py` via subprocess.
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
CLI = str(HERE / "panels.py")

sys.path.insert(0, str(HERE))

import builder as panels_builder

RETAINED = Path(os.environ.get(
    "LIFIO_RETAINED_ROOT",
    "/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot"))
RETAINED_RUN_69 = RETAINED / "runs" / "pilot27-g2-r2"
RETAINED_RUN_IPAD = RETAINED / "runs" / "en-ipad13-g2-r2"
RETAINED_BEZEL_69 = RETAINED / "assets" / "iphone-18pm-black-bezel.png"
RETAINED_BEZEL_IPAD = RETAINED / "assets" / "ipad-13in-silver-bezel-portrait.png"

HAS_RETAINED_69 = (
    (RETAINED_RUN_69 / "run-manifest.json").is_file()
    and (RETAINED_RUN_69 / "frames" / "track-running.png").is_file()
    and RETAINED_BEZEL_69.is_file())
HAS_RETAINED_IPAD = (
    (RETAINED_RUN_IPAD / "run-manifest.json").is_file()
    and (RETAINED_RUN_IPAD / "frames" / "track-running.png").is_file()
    and RETAINED_BEZEL_IPAD.is_file())

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

FRAME_COLORS = {
    "track-running": (70, 130, 180),
    "insights": (90, 160, 90),
    "history": (180, 130, 70),
    "add-entry": (150, 100, 170),
    "la-lock": (100, 100, 140),
    "la-compact": (140, 100, 100),
    "la-expanded": (100, 140, 120),
}


def run(*argv: str):
    env = dict(os.environ)
    env.pop("LIFIO_CAPTURE_LEASE", None)
    return subprocess.run([sys.executable, CLI, *argv],
                          capture_output=True, text=True, timeout=300, env=env)


def make_captions(tmp: str, locale: str, texts: dict | None = None,
                  en_override: dict | None = None,
                  file_locale: str | None = None) -> str:
    texts = texts or {}
    en_override = en_override or {}
    caps = {}
    for key in panels_builder.CAPTION_KEYS:
        caps[key] = {"text": texts.get(key, OWNER_EN[key]),
                     "en": en_override.get(key, OWNER_EN[key])}
    obj = {"locale": file_locale or locale, "version": "captions-v1",
           "status": "test fixture", "captions": caps}
    p = str(Path(tmp) / f"captions-{locale}.json")
    Path(p).write_text(json.dumps(obj), encoding="utf-8")
    return p


def make_frames(frames_dir: Path, canvas: tuple[int, int],
                frames: tuple[str, ...]) -> None:
    from PIL import Image
    frames_dir.mkdir(parents=True, exist_ok=True)
    for frame in frames:
        Image.new("RGB", canvas, FRAME_COLORS[frame]).save(frames_dir / f"{frame}.png")


def make_manifest(path: Path, frames_dir: Path, run_id: str,
                  canvas: tuple[int, int], frames: tuple[str, ...],
                  status: str = "complete") -> None:
    recs = []
    for frame in frames:
        png = frames_dir / f"{frame}.png"
        recs.append({"frame": frame,
                     "screenshot_sha256": hashlib.sha256(png.read_bytes()).hexdigest(),
                     "geometry": {"width": canvas[0], "height": canvas[1]}})
    path.write_text(json.dumps({
        "schema_version": 1, "run_id": run_id, "status": status,
        "deck_version": "en-austin-1", "treatment": "light-v1",
        "geometry": {"width": canvas[0], "height": canvas[1]},
        "frames": recs}), encoding="utf-8")


def make_bezel_69(path: Path) -> None:
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (980, 2000), (20, 20, 20, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([50, 44, 50 + 880, 44 + 1912], fill=(0, 0, 0, 0))
    im.save(path)


def make_bezel_63(path: Path) -> None:
    """Synthetic 6.3 bezel passing verify_bezel_63 (sharp slot + pill)."""
    from PIL import Image, ImageDraw
    bw, bh, sw, sh, ax, ay = 880, 1800, 804, 1748, 38, 26
    im = Image.new("RGBA", (bw, bh), (20, 20, 20, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([ax, ay, ax + sw, ay + sh], fill=(0, 0, 0, 0))
    d.rounded_rectangle([ax + sw // 2 - 90, ay + 30,
                         ax + sw // 2 + 90, ay + 30 + 64],
                        radius=32, fill=(20, 20, 20, 255))
    im.save(path)


def make_bezel_ipad(path: Path) -> None:
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (2300, 3000), (200, 200, 200, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([118, 124, 118 + 2064, 124 + 2752], fill=(0, 0, 0, 0))
    im.save(path)


def make_kit_69(tmp: str) -> dict:
    """Synthetic EN 6.9 fixture kit (hermetic)."""
    root = Path(tmp)
    frames_dir = root / "frames"
    make_frames(frames_dir, (1320, 2868), panels_builder.NEEDED_FRAMES_69)
    manifest = root / "run-manifest.json"
    make_manifest(manifest, frames_dir, "test-69-r1", (1320, 2868),
                  panels_builder.NEEDED_FRAMES_69)
    bezel = root / "bezel-69.png"
    make_bezel_69(bezel)
    captions = make_captions(tmp, "en")
    out = root / "out"
    out.mkdir()
    return {"frames": str(frames_dir), "manifest": str(manifest),
            "bezel": str(bezel), "captions": captions, "out": str(out)}


def make_kit_ipad(tmp: str) -> dict:
    root = Path(tmp)
    frames_dir = root / "frames"
    needed = tuple(panels_builder.PANEL_FRAMES_IPAD.values())
    make_frames(frames_dir, (2064, 2752), needed)
    manifest = root / "run-manifest.json"
    make_manifest(manifest, frames_dir, "test-ipad-r1", (2064, 2752), needed)
    bezel = root / "bezel-ipad.png"
    make_bezel_ipad(bezel)
    captions = make_captions(tmp, "en")
    out = root / "out"
    out.mkdir()
    return {"frames": str(frames_dir), "manifest": str(manifest),
            "bezel": str(bezel), "captions": captions, "out": str(out)}


def make_kit_63(tmp: str) -> dict:
    """Synthetic EN 6.3 fixture kit (hermetic)."""
    root = Path(tmp)
    frames_dir = root / "frames"
    make_frames(frames_dir, (1206, 2622), panels_builder.NEEDED_FRAMES_69)
    manifest = root / "run-manifest.json"
    make_manifest(manifest, frames_dir, "test-63-r1", (1206, 2622),
                  panels_builder.NEEDED_FRAMES_69)
    bezel = root / "bezel-63.png"
    make_bezel_63(bezel)
    captions = make_captions(tmp, "en")
    out = root / "out"
    out.mkdir()
    return {"frames": str(frames_dir), "manifest": str(manifest),
            "bezel": str(bezel), "captions": captions, "out": str(out)}


@unittest.skipUnless(HAS_PILLOW, "Pillow required")
class BuilderUnitTests(unittest.TestCase):
    def test_en_copy_constants_verbatim(self):
        self.assertEqual(panels_builder.EN_FLAT, OWNER_EN)

    def test_captions_en_file_valid(self):
        obj = panels_builder.load_captions(HERE / "captions_en.json")
        caps = panels_builder.validate_captions_for_locale(obj, "en")
        self.assertEqual(obj.get("version"), "captions-v1")
        for key, want in OWNER_EN.items():
            self.assertEqual(caps[key]["text"], want)
            self.assertEqual(caps[key]["en"], want)

    def test_build_en69_synthetic_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out1 = Path(kit["out"]) / "a"
            out2 = Path(kit["out"]) / "b"
            r1 = panels_builder.build_69(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out1)
            r2 = panels_builder.build_69(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out2)
            self.assertEqual(r1["template_version"], 13)
            self.assertEqual(len(r1["panels"]), 5)
            for name in r1["panels"]:
                b1 = (out1 / name).read_bytes()
                b2 = (out2 / name).read_bytes()
                self.assertEqual(b1, b2, f"non-deterministic {name}")
                with Image.open(out1 / name) as probed:
                    self.assertEqual(probed.size, (1320, 2868))

    def test_selftest_69_green_on_synthetic(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out = Path(kit["out"]) / "a"
            recipe = panels_builder.build_69(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out)
            lines = panels_builder.selftest_69(out, recipe)
            self.assertEqual(len(lines), 5)

    def test_selftest_ipad_green_on_synthetic(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_ipad(tmp)
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out = Path(kit["out"]) / "a"
            recipe = panels_builder.build_ipad(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out)
            self.assertEqual(recipe["template_version"], "ipad-v1")
            self.assertEqual(len(recipe["panels"]), 4)
            lines = panels_builder.selftest_ipad(out, recipe)
            self.assertEqual(len(lines), 4)

    def test_expected_tables_pinned(self):
        self.assertEqual(set(panels_builder.EXPECTED_EN69),
                         {"track", "insights", "history", "add-entry", "la"})
        self.assertEqual(set(panels_builder.EXPECTED_EN_IPAD),
                         {"track", "insights", "history", "add-entry"})

    def test_63_scale_factors_pinned(self):
        self.assertAlmostEqual(panels_builder.SX63, 1206 / 1320)
        self.assertAlmostEqual(panels_builder.SY63, 2622 / 2868)
        self.assertEqual(panels_builder.CANVAS_63, (1206, 2622))
        self.assertEqual(panels_builder.SIZES["6.3"]["template"],
                         panels_builder.TEMPLATE_69)
        self.assertEqual(panels_builder.MATRIX_DEVICES["iphone63"],
                         {"size": "6.3", "canvas": (1206, 2622),
                          "island": True})

    def test_build_en63_synthetic_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_63(tmp)
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out1 = Path(kit["out"]) / "a"
            out2 = Path(kit["out"]) / "b"
            r1 = panels_builder.build_63(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out1)
            r2 = panels_builder.build_63(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out2)
            self.assertEqual(r1["template_version"], 13)
            self.assertEqual(r1["template_variant"], "v13-scaled-63")
            self.assertEqual(len(r1["panels"]), 5)
            for name in r1["panels"]:
                b1 = (out1 / name).read_bytes()
                b2 = (out2 / name).read_bytes()
                self.assertEqual(b1, b2, f"non-deterministic {name}")
                with Image.open(out1 / name) as probed:
                    self.assertEqual(probed.size, (1206, 2622))

    def test_selftest_63_green_on_synthetic(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_63(tmp)
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out = Path(kit["out"]) / "a"
            recipe = panels_builder.build_63(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out)
            lines = panels_builder.selftest_63(out, recipe)
            self.assertEqual(len(lines), 5)

    def test_detect_slot_matches_drawn_rect(self):
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "b63.png"
            make_bezel_63(bezel)
            # PIL rectangles are endpoint-inclusive: 804x1748 draw -> 805x1749.
            self.assertEqual(panels_builder.detect_bezel_slot(bezel),
                             ((805, 1749), (38, 26)))

    def test_verify_63_rejects_wrong_aspect(self):
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "bad.png"
            make_bezel_ipad(bezel)
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.verify_bezel_63(bezel)
            self.assertIn("aspect drift", str(ctx.exception))

    def test_verify_63_rejects_opaque(self):
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "opaque.png"
            Image.new("RGB", (900, 1900), (10, 10, 10)).save(bezel)
            with self.assertRaises(panels_builder.BuilderError):
                panels_builder.verify_bezel_63(bezel)

    def test_device_shot_63_rejects_cross_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_63(tmp)
            bezel = panels_builder.load_bezel(Path(kit["bezel"]))
            info = panels_builder.verify_bezel_63(Path(kit["bezel"]))
            slot = tuple(info["screen_slot_px"])
            at = tuple(info["screen_at_px"])
            big = Image.new("RGB", (1320, 2868), (1, 2, 3))
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.device_shot_63(big, bezel, slot, at,
                                              tuple(bezel.size))
            self.assertIn("cross-size art rejected", str(ctx.exception))


@unittest.skipUnless(HAS_PILLOW, "Pillow required")
class CliTests(unittest.TestCase):
    def test_cli_build_en69_selftest(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"], "--selftest")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("selftest green", proc.stdout)
            for word in ("track", "insights", "history", "add-entry",
                         "live-activities"):
                matches = list(Path(kit["out"]).glob(f"panel-{word}-en-1320x2868.png"))
                self.assertEqual(len(matches), 1, word)
            self.assertEqual(
                len(list(Path(kit["out"]).glob("panels-en-1320x2868.recipe.json"))), 1)

    def test_cli_check_template_fails_on_synthetic(self):
        # The byte-identical gate is real: synthetic art must NOT pass it.
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"], "--check-template")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("template mismatch", proc.stderr)

    def test_cli_ipad_build_selftest_no_la(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_ipad(tmp)
            proc = run("--locale", "en", "--size", "ipad13",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"], "--selftest")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("selftest green", proc.stdout)
            self.assertEqual(
                len(list(Path(kit["out"]).glob("panel-*-en-2064x2752.png"))), 4)
            self.assertEqual(
                len(list(Path(kit["out"]).glob("panel-live-activities-*.png"))), 0)

    def test_cli_63_build_selftest(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_63(tmp)
            proc = run("--locale", "en", "--size", "6.3",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"], "--selftest")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("selftest green", proc.stdout)
            self.assertEqual(
                len(list(Path(kit["out"]).glob("panel-*-en-1206x2622.png"))), 5)
            self.assertEqual(
                len(list(Path(kit["out"]).glob("panels-en-1206x2622.recipe.json"))), 1)
            recipe = json.loads(
                next(Path(kit["out"]).glob("panels-en-1206x2622.recipe.json")
                     ).read_text(encoding="utf-8"))
            self.assertEqual(recipe.get("template_variant"), "v13-scaled-63")

    def test_cli_63_check_template_refused(self):
        # No owner-approved 6.3 hashes exist: the byte-identical gate
        # refuses 6.3 loudly instead of passing it.
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_63(tmp)
            proc = run("--locale", "en", "--size", "6.3",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"], "--check-template")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("no approved template hashes", proc.stderr)

    def test_cli_63_cross_size_art_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_63(tmp)
            from PIL import Image
            frames_dir = Path(kit["frames"])
            Image.new("RGB", (1320, 2868), (1, 2, 3)).save(frames_dir / "history.png")
            manifest_path = Path(kit["manifest"])
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for rec in manifest["frames"]:
                if rec["frame"] == "history":
                    rec["screenshot_sha256"] = hashlib.sha256(
                        (frames_dir / "history.png").read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            proc = run("--locale", "en", "--size", "6.3",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("cross-size art rejected", proc.stderr)

    def test_cli_zh_hans_renders(self):
        # Short CJK captions fit the fixed template; exercises the
        # Hiragino font path + character-level wrap.
        zh = {"track": "时间记录，触手可及。",
              "insights": "一眼看清时间的去向。",
              "history_primary": "每分每秒，一目了然。",
              "history_secondary": "仅你可见。",
              "live_activity": "计时器，时刻在眼前。",
              "add_entry": "所需细节，一应俱全。"}
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            captions = make_captions(tmp, "zh-Hans", texts=zh)
            proc = run("--locale", "zh-Hans", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", captions,
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"], "--selftest")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(
                len(list(Path(kit["out"]).glob("panel-*-zh-Hans-1320x2868.png"))), 5)

    def test_cli_long_caption_fails_loudly(self):
        # Overflowing captions are 9.2 findings, never silently shrunk.
        long_track = " ".join(["palabra"] * 24)
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            captions = make_captions(tmp, "es-419", texts={"track": long_track})
            proc = run("--locale", "es-419", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", captions,
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("does not fit", proc.stderr)

    def test_cli_altered_en_text_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            captions = make_captions(tmp, "en", texts={"track": "Edited copy here."})
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", captions,
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("drift", proc.stderr)

    def test_cli_altered_en_reference_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            captions = make_captions(tmp, "ru", en_override={"track": "Changed."})
            proc = run("--locale", "ru", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", captions,
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("drift", proc.stderr)

    def test_cli_wrong_locale_captions_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            captions = make_captions(tmp, "ru", file_locale="ru")
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", captions,
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("cross-locale", proc.stderr)

    def test_cli_size_65_gated(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            proc = run("--locale", "en", "--size", "6.5",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("no owner-approved 6.5", proc.stderr)

    def test_cli_unknown_locale_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            proc = run("--locale", "fr", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"])
            self.assertEqual(proc.returncode, 2)

    def test_cli_repo_panels_dir_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            repo_dir = str(Path(HERE).resolve())
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", repo_dir, "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("inside the repository", proc.stderr)

    def test_cli_missing_panels_dir_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            missing = str(Path(tmp) / "no-such-dir")
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", missing, "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)

    def test_cli_run_manifest_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("--run-manifest is required", proc.stderr)

    def test_cli_bezel_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("--bezel is required", proc.stderr)

    def test_cli_missing_frame_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            Path(kit["frames"], "insights.png").unlink()
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("missing source", proc.stderr)

    def test_cli_hash_drift_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            with open(os.path.join(kit["frames"], "history.png"), "ab") as fh:
                fh.write(b"\x00")
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("hash drift", proc.stderr)

    def test_cli_stretched_art_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            from PIL import Image
            frames_dir = Path(kit["frames"])
            Image.new("RGB", (1242, 2688), (1, 2, 3)).save(frames_dir / "history.png")
            manifest_path = Path(kit["manifest"])
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for rec in manifest["frames"]:
                if rec["frame"] == "history":
                    rec["screenshot_sha256"] = hashlib.sha256(
                        (frames_dir / "history.png").read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            # File-level size guard fires (manifest still claims 1320x2868).
            self.assertEqual(proc.returncode, 2)
            self.assertIn("cross-size art rejected", proc.stderr)
            # Manifest-level geometry guard fires when the manifest itself
            # claims the wrong size.
            for rec in manifest["frames"]:
                if rec["frame"] == "history":
                    rec["geometry"] = {"width": 1242, "height": 2688}
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("no cross-size stretching", proc.stderr)

    def test_cli_incomplete_run_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            manifest_path = Path(kit["manifest"])
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["status"] = "needs-inspection"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("needs-inspection", proc.stderr)

    def test_cli_bezel_size_drift_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            from PIL import Image
            bad = str(Path(tmp) / "bad-bezel.png")
            Image.new("RGBA", (100, 100), (0, 0, 0, 255)).save(bad)
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", bad)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("bezel size drift", proc.stderr)


@unittest.skipUnless(HAS_PILLOW and HAS_RETAINED_69,
                     "retained v13 sources required")
class RetainedByteIdentical69Tests(unittest.TestCase):
    """The promotion proof: in-git builder reproduces approved v13 PNGs."""

    def test_retained_en69_byte_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(Path(tmp) / "out")
            Path(out).mkdir()
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", out,
                       "--captions", str(HERE / "captions_en.json"),
                       "--frames-dir", str(RETAINED_RUN_69 / "frames"),
                       "--run-manifest",
                       str(RETAINED_RUN_69 / "run-manifest.json"),
                       "--bezel", str(RETAINED_BEZEL_69),
                       "--selftest", "--check-template")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("template check green", proc.stdout)
            key_to_retained = {
                "track": "panel-track-en-1320x2868-v13.png",
                "insights": "panel-insights-en-1320x2868-v13.png",
                "history": "panel-history-en-1320x2868-v13.png",
                "add-entry": "panel-add-entry-en-1320x2868-v13.png",
                "la": "panel-live-activities-en-1320x2868-v13.png",
            }
            key_to_built = {
                "track": "panel-track-en-1320x2868.png",
                "insights": "panel-insights-en-1320x2868.png",
                "history": "panel-history-en-1320x2868.png",
                "add-entry": "panel-add-entry-en-1320x2868.png",
                "la": "panel-live-activities-en-1320x2868.png",
            }
            for key, want in panels_builder.EXPECTED_EN69.items():
                built = Path(out) / key_to_built[key]
                self.assertTrue(built.is_file(), key)
                got = hashlib.sha256(built.read_bytes()).hexdigest()
                self.assertEqual(got, want, f"{key} != approved v13 hash")
                retained = RETAINED / "panels" / key_to_retained[key]
                self.assertTrue(retained.is_file(), f"retained {key} missing")
                self.assertEqual(built.read_bytes(), retained.read_bytes(),
                                 f"{key} bytes differ from retained v13 file")


@unittest.skipUnless(HAS_PILLOW and HAS_RETAINED_IPAD,
                     "retained ipad-v1 sources required")
class RetainedByteIdenticalIpadTests(unittest.TestCase):
    def test_retained_ipad_byte_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(Path(tmp) / "out")
            Path(out).mkdir()
            proc = run("--locale", "en", "--size", "ipad13",
                       "--panels-dir", out,
                       "--captions", str(HERE / "captions_en.json"),
                       "--frames-dir", str(RETAINED_RUN_IPAD / "frames"),
                       "--run-manifest",
                       str(RETAINED_RUN_IPAD / "run-manifest.json"),
                       "--bezel", str(RETAINED_BEZEL_IPAD),
                       "--selftest", "--check-template")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("template check green", proc.stdout)
            for key, want in panels_builder.EXPECTED_EN_IPAD.items():
                built = Path(out) / f"panel-{key}-en-2064x2752.png"
                self.assertTrue(built.is_file(), key)
                got = hashlib.sha256(built.read_bytes()).hexdigest()
                self.assertEqual(got, want, f"{key} != approved ipad-v1 hash")


if __name__ == "__main__":
    unittest.main(verbosity=2)
