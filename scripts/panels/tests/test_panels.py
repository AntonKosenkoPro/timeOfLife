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
from unittest import mock

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

V2_DIR = Path(os.environ.get("LIFIO_V2_BEZELS_DIR",
                             "/tmp/lifio-design-assets-v2"))
V2_18PM_BEZEL = V2_DIR / "iphone-18-pro-max-silver-portrait.png"
HAS_V2_18PM = V2_18PM_BEZEL.is_file()
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

# Archived pilot captions (in-git 9.2 review inputs; the matrix --captions-dir).
ARCHIVE_CAPTIONS_DIR = (HERE.parent.parent / "openspec" / "changes" /
                        "archive" / "2026-11-03-app-store-screenshot-pilot" /
                        "captions")

PANEL_TEXT_KEY = {
    "track": "track",
    "insights": "insights",
    "history": "history_primary",
    "add-entry": "add_entry",
    "la": "live_activity",
}

ALL_LOCALES = ("en", "ru", "zh-Hans", "es-419", "pt-BR")
IPHONE_PANELS = ("track", "insights", "history", "add-entry", "la")
IPAD_PANELS = ("track", "insights", "history", "add-entry")


def archived_texts(locale: str) -> dict:
    """Caption texts for a matrix locale (en: owner-fixed copy verbatim)."""
    if locale == "en":
        return dict(OWNER_EN)
    obj = json.loads(
        (ARCHIVE_CAPTIONS_DIR / f"{locale}.json").read_text(encoding="utf-8"))
    return {k: obj["captions"][k]["text"]
            for k in panels_builder.CAPTION_KEYS}

FRAME_COLORS = {
    "track-running": (70, 130, 180),
    "insights": (90, 160, 90),
    "history": (180, 130, 70),
    "add-entry": (150, 100, 170),
    "la-lock": (100, 100, 140),
    "la-compact": (140, 100, 100),
    "la-expanded": (100, 140, 120),
}

# Session-evidence fixture pins (strict consumer of the shared runner
# validator; never reimplemented here).
NONCE_PINNED = "0123456789abcdef0123456789abcdef"
NONCE_REALTIME = "fedcba9876543210fedcba9876543210"
APP_FRAMES = ("track-running", "insights", "history", "add-entry")


def _req_sha(run_id: str, frame: str) -> str:
    return hashlib.sha256(f"req-{run_id}-{frame}".encode()).hexdigest()


def _domain_of(frame: str) -> str:
    return "pinned" if frame in APP_FRAMES else "realtime"


def _nonce_of(frame: str) -> str:
    return NONCE_PINNED if frame in APP_FRAMES else NONCE_REALTIME


# Attested iPad model — REAL catalog identifier (M5 12GB variant; the
# shared validator requires an exact cataloged model — catalog owner
# aligns SDK IDs separately). Name is operator-assigned evidence
# (presence, not value); udid must equal the run's unanimous frame
# device_udid.
IPAD_MODEL_ID = ("com.apple.CoreSimulator.SimDeviceType."
                 "iPad-Pro-13-inch-M5-12GB")
IPAD_MODEL_NAME = "shot-ci-ipad13"


def _attested_probe(device: str, run_id: str,
                    canvas: tuple[int, int]) -> dict:
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


def _device_for_canvas(canvas: tuple[int, int]) -> str:
    if tuple(canvas) == (2064, 2752):
        return "ipad13"
    if tuple(canvas) == (1206, 2622):
        return "iphone63"
    return "iphone69"


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
    """Session-valid manifest + frame records + receipts (+ iPad probe)."""
    run_dir = path.parent
    sessions_dir = run_dir / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    device = _device_for_canvas(canvas)
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
        else:
            rec["capture"] = "external-lock-screen"
            rec["capture_window"] = {
                "started_at": "2026-10-30T10:00:00+00:00",
                "captured_at_iso": "2026-10-30T10:00:10+00:00",
                "observed_elapsed_s": 10,
            }
            rec["observation_sha256"] = "d" * 64
        (frames_dir / f"{frame}.json").write_text(
            json.dumps(rec, sort_keys=True), encoding="utf-8")
        recs.append(rec)
        nonce = rec["session_nonce"]
        transcripts.setdefault(nonce, []).append(
            {"seq": seq, "frame": frame, "request_sha256": sha_req,
             "request_semantic_sha256": "b" * 64})
    for nonce, transcript in transcripts.items():
        domain = "pinned" if nonce == NONCE_PINNED else "realtime"
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
        probe = _attested_probe(device, run_id, canvas)
        (sessions_dir / "island-probe.json").write_text(
            json.dumps(probe, sort_keys=True), encoding="utf-8")
    manifest_obj: dict = {
        "schema_version": 1, "run_id": run_id, "status": status,
        "deck_version": "en-austin-1", "treatment": "light-v1",
        "geometry": {"width": canvas[0], "height": canvas[1]},
        "frames": recs}
    if device == "ipad13":
        # Producer-faithful N/A metadata (run_manifest.assemble shape).
        manifest_obj["na_frames"] = ["la-compact", "la-expanded"]
        manifest_obj["island_probe"] = probe
    path.write_text(json.dumps(manifest_obj), encoding="utf-8")


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


def make_bezel_69_apple(path: Path) -> None:
    """Synthetic Apple-profile 6.9 bezel: exact 1470x3000 native dims with
    the exact 1320x2868@(75,66) cavity (sharp corners — verifiers pin
    dimensions/slot/origin, never corner art). NOTE: PIL rectangles are
    endpoint-inclusive, so the far corner is at+slot-1."""
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (1470, 3000), (20, 20, 20, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([75, 66, 75 + 1320 - 1, 66 + 2868 - 1], fill=(0, 0, 0, 0))
    im.save(path)


def make_bezel_63_apple(path: Path) -> None:
    """Synthetic Apple-profile 6.3 bezel: exact 1350x2760 native dims with
    the exact 1206x2622@(72,69) cavity — a 1:1 native paste, never
    resampled."""
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (1350, 2760), (20, 20, 20, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([72, 69, 72 + 1206 - 1, 69 + 2622 - 1], fill=(0, 0, 0, 0))
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
    # Evidence includes the required Lock Screen alongside the 4 rendered
    # app frames (Island stays N/A via probe, never filed).
    evidenced = (*needed, "la-lock")
    make_frames(frames_dir, (2064, 2752), evidenced)
    manifest = root / "run-manifest.json"
    make_manifest(manifest, frames_dir, "test-ipad-r1", (2064, 2752),
                  evidenced)
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


def stage_retained_with_session(src_frames: Path, src_manifest: Path,
                                staged_run: Path, run_id: str,
                                device: str) -> tuple[str, str]:
    """Copy retained approved sources into a tmp run dir + session evidence.

    Retained originals stay untouched: PNG bytes are copied verbatim (so
    the byte-identical proof still binds the approved pixels) while the
    staged manifest/frame records carry the session nonce/transcript
    bindings the strict shared validator requires. Rendering inputs are
    unchanged; only evidence bindings are added.
    """
    import shutil

    frames_dir = staged_run / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    for png in Path(src_frames).glob("*.png"):
        shutil.copy(png, frames_dir / png.name)
    manifest = json.loads(Path(src_manifest).read_text(encoding="utf-8"))
    recs = manifest.get("frames", [])
    seq_counters = {"pinned": 0, "realtime": 0}
    transcripts: dict[str, list[dict]] = {}
    for rec in recs:
        frame = rec.get("frame")
        domain = _domain_of(frame)
        seq = seq_counters[domain]
        seq_counters[domain] += 1
        sha_req = _req_sha(run_id, frame)
        rec["run_id"] = run_id
        rec.setdefault("device_udid", "UDID-retained")
        rec["device_key"] = device
        rec["request_sha256"] = sha_req
        rec.setdefault("request_semantic_sha256", "b" * 64)
        rec["session_nonce"] = _nonce_of(frame)
        rec["session_domain"] = domain
        rec["seq"] = seq
        rec.setdefault(
            "mode", "app-clock-pinned" if domain == "pinned"
            else "live-activity-realtime")
        if domain == "pinned":
            rec.setdefault("capture", "native-simctl")
        else:
            rec.setdefault("capture", "external-lock-screen")
            rec.setdefault("capture_window", {
                "started_at": "2026-10-30T10:00:00+00:00",
                "captured_at_iso": "2026-10-30T10:00:10+00:00",
                "observed_elapsed_s": 10})
            rec.setdefault("observation_sha256", "d" * 64)
        (frames_dir / f"{frame}.json").write_text(
            json.dumps(rec, sort_keys=True), encoding="utf-8")
        nonce = rec["session_nonce"]
        transcripts.setdefault(nonce, []).append(
            {"seq": seq, "frame": frame, "request_sha256": sha_req,
             "request_semantic_sha256": "b" * 64})
    sessions_dir = staged_run / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    for nonce, transcript in transcripts.items():
        domain = "pinned" if nonce == NONCE_PINNED else "realtime"
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
        udids = {r.get("device_udid") for r in recs
                 if isinstance(r, dict)}
        probe = {
            "schema_version": 1,
            "device_key": device,
            "island_available": False,
            "reason": "capability probe: no Dynamic Island",
            "run_id": run_id,
            "session_nonce": next(
                (r["session_nonce"] for r in recs
                 if r.get("session_domain") == "realtime"),
                NONCE_REALTIME),
            "geometry": {"width": 2064, "height": 2752},
            "model": {
                "deviceTypeIdentifier": IPAD_MODEL_ID,
                "name": IPAD_MODEL_NAME,
                # Producer shape: simctl-reported udid == the run's
                # unanimous frame device_udid (retained recs keep theirs).
                "udid": next(iter(udids)) if len(udids) == 1
                else "UDID-retained",
            },
            "source": "simctl-list",
        }
        (sessions_dir / "island-probe.json").write_text(
            json.dumps(probe, sort_keys=True),
            encoding="utf-8")
    manifest["status"] = "complete"
    manifest["run_id"] = run_id
    staged_manifest = staged_run / "run-manifest.json"
    staged_manifest.write_text(json.dumps(manifest), encoding="utf-8")
    return str(frames_dir), str(staged_manifest)


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
                          "island": True, "model": "iPhone 17",
                          "color": "White",
                          "apple_asset": panels_builder.APPLE_ASSET_63})

    def test_matrix_catalog_matches_owner_lineup(self):
        # Owner lineup 2026-11-03: iphone69/iphone63/ipad13 only —
        # iphone65 was dropped, so the catalog must not list it.
        self.assertEqual(set(panels_builder.MATRIX_DEVICES),
                         {"iphone69", "iphone63", "ipad13"})
        self.assertEqual(set(panels_builder.SIZES),
                         {"6.9", "6.3", "ipad13"})

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

    def test_verify_69_apple_profile_green(self):
        # Official Apple 17 Pro Max art: exact native profile verifies with
        # the pinned slot/origin/mask radius (hash gate lives in staging).
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "apple-69.png"
            make_bezel_69_apple(bezel)
            info = panels_builder.verify_bezel_69(bezel)
            self.assertEqual(info["profile"], "apple-17pm-v1")
            self.assertEqual(info["size"], [1470, 3000])
            self.assertEqual(info["screen_slot_px"], [1320, 2868])
            self.assertEqual(info["screen_at_px"], [75, 66])
            self.assertEqual(info["screen_mask_radius_px"], 192)

    def test_verify_69_apple_rejects_landscape(self):
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "land.png"
            Image.new("RGBA", (3000, 1470), (20, 20, 20, 255)).save(bezel)
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.verify_bezel_69(bezel)
            self.assertIn("size drift", str(ctx.exception))

    def test_verify_69_apple_rejects_shifted_cavity(self):
        # Right native size, wrong cavity origin: no silent substitution.
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "shifted.png"
            im = Image.new("RGBA", (1470, 3000), (20, 20, 20, 255))
            ImageDraw.Draw(im).rectangle(
                [100, 100, 100 + 1320, 100 + 2868], fill=(0, 0, 0, 0))
            im.save(bezel)
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.verify_bezel_69(bezel)
            self.assertIn("slot drift", str(ctx.exception))

    def test_verify_69_apple_rejects_opaque(self):
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "opaque.png"
            Image.new("RGB", (1470, 3000), (10, 10, 10)).save(bezel)
            with self.assertRaises(panels_builder.BuilderError):
                panels_builder.verify_bezel_69(bezel)

    def test_device_shot_69_rejects_unknown_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "odd.png"
            make_bezel_63(bezel)
            loaded = panels_builder.load_bezel(bezel)
            src = Image.new("RGB", (1320, 2868), (1, 2, 3))
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.device_shot_69(src, loaded)
            self.assertIn("unverified 6.9 bezel dimensions",
                          str(ctx.exception))

    def test_verify_63_apple_profile_green(self):
        # Official Apple 17 art: exact profile verifies 1:1 (never
        # resampled) with the pinned mask radius.
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "apple-63.png"
            make_bezel_63_apple(bezel)
            info = panels_builder.verify_bezel_63(bezel)
            self.assertEqual(info["profile"], "apple-17-v1")
            self.assertEqual(info["size"], [1350, 2760])
            self.assertEqual(info["screen_slot_px"], [1206, 2622])
            self.assertEqual(info["screen_at_px"], [72, 69])
            self.assertEqual(info["screen_mask_radius_px"], 190)

    def test_verify_63_apple_rejects_shifted_cavity(self):
        with tempfile.TemporaryDirectory() as tmp:
            bezel = Path(tmp) / "shifted.png"
            im = Image.new("RGBA", (1350, 2760), (20, 20, 20, 255))
            ImageDraw.Draw(im).rectangle(
                [100, 100, 100 + 1206, 100 + 2622], fill=(0, 0, 0, 0))
            im.save(bezel)
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.verify_bezel_63(bezel)
            self.assertIn("slot drift", str(ctx.exception))

    def test_device_shot_63_apple_pastes_native_1_to_1(self):
        # Apple 17 slot == canvas: the capture must land byte-identical
        # (no LANCZOS resampling blur) under the bezel hole.
        with tempfile.TemporaryDirectory() as tmp:
            bezel_path = Path(tmp) / "apple-63.png"
            make_bezel_63_apple(bezel_path)
            bezel = panels_builder.load_bezel(bezel_path)
            info = panels_builder.verify_bezel_63(bezel_path)
            slot = tuple(info["screen_slot_px"])
            at = tuple(info["screen_at_px"])
            shot = Image.new("RGB", (1206, 2622), (70, 130, 180))
            dev = panels_builder.device_shot_63(
                shot, bezel, slot, at, tuple(bezel.size),
                mask_r=int(info["screen_mask_radius_px"]))
            self.assertEqual(dev.size, (1350, 2760))
            pasted = dev.crop((at[0] + 400, at[1] + 400,
                               at[0] + 500, at[1] + 500)).convert("RGB")
            for px in list(pasted.getdata())[::997]:
                self.assertEqual(tuple(px), (70, 130, 180))

    def test_ipad_transparent_rgb_ignored(self):
        # Official iPad art ships transparent WHITE while legacy fixtures
        # use transparent BLACK: alpha-only composition must render
        # byte-identical panels either way (RGB under alpha==0 ignored).
        with tempfile.TemporaryDirectory() as tmp:
            black = Path(tmp) / "black.png"
            white = Path(tmp) / "white.png"
            make_bezel_ipad(black)
            im = Image.new("RGBA", (2300, 3000), (200, 200, 200, 255))
            d = ImageDraw.Draw(im)
            d.rectangle([118, 124, 118 + 2064, 124 + 2752],
                        fill=(255, 255, 255, 0))
            im.save(white)
            panels_builder.verify_bezel_ipad(black)
            panels_builder.verify_bezel_ipad(white)
            raw = Image.new("RGB", (2064, 2752), (70, 130, 180))
            dev_b = panels_builder.device_sheet_ipad(
                raw, panels_builder.load_bezel(black))
            dev_w = panels_builder.device_sheet_ipad(
                raw, panels_builder.load_bezel(white))
            self.assertEqual(dev_b.tobytes(), dev_w.tobytes())

    def test_build_en69_apple_deterministic_selftest_green(self):
        # New-art review template: deterministic build + structural
        # selftest green on the Apple profile (no approval implied).
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            apple = str(Path(tmp) / "apple-69.png")
            make_bezel_69_apple(Path(apple))
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out1 = Path(kit["out"]) / "a"
            out2 = Path(kit["out"]) / "b"
            r1 = panels_builder.build_69(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(apple), out1)
            r2 = panels_builder.build_69(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(apple), out2)
            self.assertEqual(r1["bezel"]["profile"], "apple-17pm-v1")
            self.assertEqual(r1["bezel"]["screen_slot_px"], [1320, 2868])
            for name in r1["panels"]:
                self.assertEqual((out1 / name).read_bytes(),
                                 (out2 / name).read_bytes(),
                                 f"non-deterministic {name}")
                with Image.open(out1 / name) as probed:
                    self.assertEqual(probed.size, (1320, 2868))
            self.assertEqual(len(panels_builder.selftest_69(out1, r1)), 5)

    def test_build_en63_apple_deterministic_selftest_green(self):
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_63(tmp)
            apple = str(Path(tmp) / "apple-63.png")
            make_bezel_63_apple(Path(apple))
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out = Path(kit["out"]) / "a"
            recipe = panels_builder.build_63(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(apple), out)
            self.assertEqual(recipe["bezel"]["profile"], "apple-17-v1")
            self.assertEqual(recipe["bezel"]["screen_slot_px"], [1206, 2622])
            self.assertEqual(len(panels_builder.selftest_63(out, recipe)), 5)

    def test_check_template_refuses_new_art_profile(self):
        # New review template version: refusal (no historical approval
        # transfer, no auto-blessed goldens) — never a byte comparison.
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            apple = str(Path(tmp) / "apple-69.png")
            make_bezel_69_apple(Path(apple))
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out = Path(kit["out"]) / "a"
            recipe = panels_builder.build_69(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(apple), out)
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.check_template(recipe, "en", "6.9")
            self.assertIn("template mismatch", str(ctx.exception))
            self.assertIn("no historical approval transfer",
                          str(ctx.exception))

    def test_check_template_refuses_18pm_profile(self):
        # The 18PM review profile is refused by name (no art needed —
        # the guard reads the recipe label before any byte comparison).
        with self.assertRaises(panels_builder.BuilderError) as ctx:
            panels_builder.check_template(
                {"bezel": {"profile": "apple-18pm-v1"}, "panels": {}},
                "en", "6.9")
        self.assertIn("apple-18pm-v1", str(ctx.exception))
        self.assertIn("no historical approval transfer",
                      str(ctx.exception))

    @unittest.skipUnless(HAS_PILLOW and HAS_V2_18PM,
                         "v2 18PM working-copy bytes required")
    def test_real_18pm_verifies_renders_refuses(self):
        # Real-file acceptance against the /tmp working copy (exact
        # bytes, canonical name): exact profile resolves by SHA, the
        # review build + selftest go green, check-template refuses.
        # Raw art is only ever read here, never committed.
        info = panels_builder.verify_bezel_69(V2_18PM_BEZEL)
        self.assertEqual(info["profile"], "apple-18pm-v1")
        self.assertEqual(info["sha256"],
                         panels_builder.APPLE_SOURCE_18PM["sha256"])
        self.assertEqual(info["screen_slot_px"], [1320, 2868])
        self.assertEqual(info["screen_at_px"], [75, 66])
        with Image.open(V2_18PM_BEZEL) as im:
            # Documented quirk: no iCCP chunk (default sRGB) — accepted,
            # color management never gates composition.
            self.assertIsNone(im.info.get("icc_profile"))
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            caps_obj = panels_builder.load_captions(Path(kit["captions"]))
            caps = panels_builder.validate_captions_for_locale(caps_obj, "en")
            out = Path(kit["out"]) / "real18"
            recipe = panels_builder.build_69(
                "en", caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), V2_18PM_BEZEL, out)
            self.assertEqual(recipe["bezel"]["profile"], "apple-18pm-v1")
            self.assertEqual(len(panels_builder.selftest_69(out, recipe)), 5)
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.check_template(recipe, "en", "6.9")
            self.assertIn("apple-18pm-v1", str(ctx.exception))

    def test_pair_scales_pinned(self):
        # Owner table 2026-11-05 (ru single-liners per owner marks): iphone
        # pair en 0.94 / ru 0.69 / es 0.93 / pt 0.97 / zh-Hans 1.0;
        # ipad13 1.0 all locales.
        for locale, want in (("en", 0.94), ("ru", 0.69), ("es-419", 0.93),
                             ("pt-BR", 0.97), ("zh-Hans", 1.0)):
            self.assertEqual(panels_builder.pair_scale("iphone", locale),
                             want)
        for locale in ALL_LOCALES:
            self.assertEqual(panels_builder.pair_scale("ipad13", locale),
                             1.0)
        # Flooring, not rounding: 96pt en -> 90, ru -> 66.
        self.assertEqual(panels_builder.scaled_size(96, "iphone", "en"), 90)
        self.assertEqual(panels_builder.scaled_size(92, "iphone", "en"), 86)
        self.assertEqual(panels_builder.scaled_size(96, "iphone", "ru"), 66)
        self.assertEqual(panels_builder.scaled_size(92, "iphone", "ru"), 63)
        self.assertEqual(panels_builder.scaled_size(96, "ipad13", "en"), 64)
        self.assertEqual(panels_builder.scaled_size(52, "ipad13", "en"), 52)

    def test_preferred_breaks_collapse_when_fits(self):
        # Rule (1): joined text fitting max width renders ONE line even
        # when the table holds two preferred lines (ru la, en insights).
        from PIL import Image, ImageDraw
        probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
        cases = [
            # (locale, pair, panel, size_pt, bold, max_w, want_nlines)
            ("en", "iphone", "insights", 90, True, 1140, 1),
            ("en", "iphone", "la", 86, True, 1140, 1),
            ("ru", "iphone", "la", 60, True, 1140, 1),
            ("ru", "iphone", "add-entry", 63, True, 1140, 1),
            ("zh-Hans", "iphone", "track", 96, True, 1140, 1),
            ("es-419", "ipad13", "insights", 96, True, 1820, 1),
            ("en", "iphone", "track", 90, True, 1140, 2),
            ("es-419", "iphone", "track", 89, True, 1140, 2),
            ("pt-BR", "iphone", "la", 89, True, 1140, 2),
            ("es-419", "ipad13", "track", 96, True, 1820, 2),
        ]
        texts = {loc: archived_texts(loc) for loc in ALL_LOCALES}
        for locale, pair, panel, size, bold, max_w, want in cases:
            text = texts[locale][PANEL_TEXT_KEY[panel]]
            fnt = panels_builder.font_for(locale, size, bold)
            lines = panels_builder.preferred_lines(
                probe, locale, pair, panel, text, fnt, max_w)
            self.assertEqual(len(lines), want,
                             f"{locale}/{pair}/{panel}")
            if want == 1:
                self.assertEqual(lines, [text])
            else:
                want_lines = [ln.strip() for ln in
                              panels_builder.BREAKS[
                                  (panels_builder.locale_root(locale),
                                   panel)]]
                self.assertEqual(lines, want_lines)

    def test_preferred_lines_honored_each_fits_width_70_combos(self):
        # All 70 device-locale-panel combos (50 iPhone + 20 iPad, no iPad
        # LA): preferred lines honored, every line fits its device width.
        from PIL import Image, ImageDraw
        probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
        texts = {loc: archived_texts(loc) for loc in ALL_LOCALES}
        combos = 0
        for size, pair, max_w in (("6.9", "iphone", 1140),
                                  ("6.3", "iphone", 1040),
                                  ("ipad13", "ipad13", 1820)):
            base = {"6.9": panels_builder.TYPE_69,
                    "6.3": panels_builder.TYPE_63,
                    "ipad13": panels_builder.TYPE_IPAD}[size]
            panels = IPAD_PANELS if pair == "ipad13" else IPHONE_PANELS
            for locale in ALL_LOCALES:
                table = panels_builder.scale_type_table(base, pair, locale)
                for panel in panels:
                    size_pt, bold, _gap = table[panel][0]
                    text = texts[locale][PANEL_TEXT_KEY[panel]]
                    fnt = panels_builder.font_for(locale, size_pt, bold)
                    lines = panels_builder.preferred_lines(
                        probe, locale, pair, panel, text, fnt, max_w)
                    for ln in lines:
                        got = probe.textlength(ln, font=fnt)
                        self.assertLessEqual(
                            got, max_w,
                            f"{size}/{locale}/{panel} line {ln!r} "
                            f"{got:.0f}px > {max_w}px")
                    joined_fits = (probe.textlength(text, font=fnt)
                                   <= max_w)
                    if joined_fits:
                        self.assertEqual(lines, [text],
                                         f"{size}/{locale}/{panel} must "
                                         "collapse to one line")
                    else:
                        want = [ln.strip() for ln in panels_builder.BREAKS[
                            (panels_builder.locale_root(locale), panel)]]
                        self.assertEqual(lines, want,
                                         f"{size}/{locale}/{panel} must "
                                         "render preferred lines verbatim")
                    combos += 1
        self.assertEqual(combos, 70)

    def _build_real_cell(self, root: str, size: str,
                         locale: str) -> tuple[Path, dict]:
        """Synthetic-frames cell rendered with the real matrix captions."""
        cell = Path(root) / f"{size}-{locale}"
        cell.mkdir(parents=True)
        tmp = str(cell)
        if size == "6.9":
            kit = make_kit_69(tmp)
        elif size == "6.3":
            kit = make_kit_63(tmp)
        else:
            kit = make_kit_ipad(tmp)
        texts = archived_texts(locale)
        captions = make_captions(tmp, locale, texts=texts)
        caps_obj = panels_builder.load_captions(Path(captions))
        caps = panels_builder.validate_captions_for_locale(caps_obj, locale)
        out = Path(kit["out"])
        if size == "6.9":
            recipe = panels_builder.build_69(
                locale, caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out)
            lines = panels_builder.selftest_69(out, recipe)
        elif size == "6.3":
            recipe = panels_builder.build_63(
                locale, caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out)
            lines = panels_builder.selftest_63(out, recipe)
        else:
            recipe = panels_builder.build_ipad(
                locale, caps, "captions-v1", Path(kit["frames"]),
                Path(kit["manifest"]), Path(kit["bezel"]), out)
            lines = panels_builder.selftest_ipad(out, recipe)
        self.assertTrue(lines, f"{size}/{locale} selftest empty")
        return out, recipe

    def test_la_band_210_all_10_iphone_cells(self):
        # All 10 iPhone LA cells (2 sizes x 5 locales, real captions):
        # headline text stays inside the owner band (69: h210, 63: h192).
        with tempfile.TemporaryDirectory() as tmp:
            checked = 0
            for size in ("6.9", "6.3"):
                canvas = (panels_builder.CANVAS_69 if size == "6.9"
                          else panels_builder.CANVAS_63)
                band = (panels_builder.HEADLINE_BOX_FIGMA if size == "6.9"
                        else panels_builder.HEADLINE_BOX_63)
                for locale in ALL_LOCALES:
                    _out, recipe = self._build_real_cell(tmp, size, locale)
                    name = panels_builder.panel_filename(
                        "la", locale, canvas)
                    p = recipe["panels"][name]
                    self.assertEqual(p["headline_box"], band,
                                     f"{size}/{locale} band drift")
                    tt, tb = p["headline_text_box"]
                    hy0, hy1 = p["headline_box"]
                    self.assertGreaterEqual(tt, hy0)
                    self.assertLessEqual(tb, hy1)
                    checked += 1
            self.assertEqual(checked, 10)

    def test_single_centered_equal_pads_all_60_cells(self):
        # All 60 single cells (4 panels x 5 locales x 3 sizes, real
        # captions): owner centered rule — device pads equal
        # left/right/bottom, title spacing equal to device and upper
        # boundary (off-by-one from flooring).
        with tempfile.TemporaryDirectory() as tmp:
            checked = 0
            for size, canvas in (
                    ("6.9", panels_builder.CANVAS_69),
                    ("6.3", panels_builder.CANVAS_63),
                    ("ipad13", panels_builder.CANVAS_IPAD)):
                for locale in ALL_LOCALES:
                    _out, recipe = self._build_real_cell(tmp, size, locale)
                    for panel in IPAD_PANELS:
                        name = panels_builder.panel_filename(
                            panel, locale, canvas)
                        p = recipe["panels"][name]
                        box = (p["shot_box"] if size != "ipad13"
                               else p["device_box"])
                        W, H = canvas
                        self.assertEqual(
                            p["headline_anchor"], "centered",
                            f"{size}/{locale}/{panel} anchor")
                        self.assertEqual(
                            box[0], W - box[2],
                            f"{size}/{locale}/{panel} side pads")
                        self.assertEqual(
                            H - box[3], box[0],
                            f"{size}/{locale}/{panel} bottom pad")
                        hy0, hy1 = p["headline_box"]
                        self.assertLessEqual(
                            abs((box[1] - hy1) - hy0), 1,
                            f"{size}/{locale}/{panel} centering")
                        checked += 1
            self.assertEqual(checked, 60)


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
            for word, num in (("track", "1"), ("insights", "4"),
                              ("history", "3"), ("add-entry", "5"),
                              ("live-activities", "2")):
                matches = list(Path(kit["out"]).glob(
                    f"panel-{num}-{word}-en-1320x2868.png"))
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

    def test_cli_check_template_refuses_new_art_profile(self):
        # New review template version: loud refusal (no approval transfer),
        # never a byte comparison against historical goldens.
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            apple = str(Path(tmp) / "apple-69.png")
            make_bezel_69_apple(Path(apple))
            proc = run("--locale", "en", "--size", "6.9",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", apple, "--selftest", "--check-template")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("template mismatch", proc.stderr)
            self.assertIn("no historical approval transfer", proc.stderr)

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
            # Strict evidence fires before the legacy cross-size guard;
            # either blocks fail-closed.
            self.assertTrue(
                "cross-size art rejected" in proc.stderr
                or "disagrees with manifest" in proc.stderr
                or "manifest disagrees with on-disk record" in proc.stderr
                or "screenshot geometry" in proc.stderr,
                proc.stderr)

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

    def test_cli_size_65_rejected(self):
        # Owner lineup 2026-11-03 dropped the 6.5-inch device: --size 6.5
        # is no longer a choice and fails closed at argparse (exit 2).
        with tempfile.TemporaryDirectory() as tmp:
            kit = make_kit_69(tmp)
            proc = run("--locale", "en", "--size", "6.5",
                       "--panels-dir", kit["out"], "--captions", kit["captions"],
                       "--frames-dir", kit["frames"],
                       "--run-manifest", kit["manifest"],
                       "--bezel", kit["bezel"])
            self.assertEqual(proc.returncode, 2)
            self.assertIn("invalid choice", proc.stderr)

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
            # Strict session evidence fires first (missing PNG), then the
            # legacy source gate; either blocks fail-closed.
            self.assertTrue(
                "missing source" in proc.stderr
                or "screenshot file missing" in proc.stderr
                or "missing from manifest" in proc.stderr,
                proc.stderr)

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
            # Strict evidence (tampered/stale binding) fires before the
            # legacy hash gate; either blocks fail-closed.
            self.assertTrue(
                "hash drift" in proc.stderr
                or "changed after capture" in proc.stderr
                or "disagrees with manifest" in proc.stderr,
                proc.stderr)

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
            # Strict evidence (record/PNG drift) fires before the legacy
            # file-level size guard; either blocks fail-closed.
            self.assertEqual(proc.returncode, 2)
            self.assertTrue(
                "cross-size art rejected" in proc.stderr
                or "disagrees with manifest" in proc.stderr
                or "manifest disagrees with on-disk record" in proc.stderr
                or "screenshot geometry" in proc.stderr,
                proc.stderr)
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
            self.assertTrue(
                "no cross-size stretching" in proc.stderr
                or "screenshot geometry" in proc.stderr
                or "disagrees with manifest" in proc.stderr
                or "manifest disagrees with on-disk record" in proc.stderr,
                proc.stderr)

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
    """Historical v13 pixels: strict rejection + renderer-only proof.

    The retained 69 run predates sessions (three distinct real LA anchors)
    and MUST be rejected by current production evidence. Its byte-identical
    compositor proof is preserved separately as a renderer-only test with
    the evidence boundary mocked at the smallest in-process scope — never
    a CLI feature or env bypass, never an approval claim.
    """

    def test_retained_en69_rejected_by_current_evidence(self):
        """Production verify_sources rejects the historical 3-anchor set.

        Unmocked; asserts the one-anchor session rule fires. No
        re-anchoring, no window edits, no carve-out.
        """
        with tempfile.TemporaryDirectory() as tmp:
            staged = Path(tmp) / "staged-69"
            frames_dir, manifest_path = stage_retained_with_session(
                RETAINED_RUN_69 / "frames",
                RETAINED_RUN_69 / "run-manifest.json",
                staged, "retained-69-r1", "iphone69")
            with self.assertRaises(panels_builder.BuilderError) as ctx:
                panels_builder.verify_sources(
                    Path(frames_dir), Path(manifest_path),
                    panels_builder.NEEDED_FRAMES_69,
                    panels_builder.CANVAS_69)
            self.assertIn("anchor", str(ctx.exception).lower())

    def test_retained_en69_review_only_after_owner_breaks(self):
        """Historical pixels rendering only; NOT current session
        evidence/approval.

        Owner-approved headline breaks + pair scales (2026-11-05, EN
        layout change included) moved EN 6.9 off the frozen v13 bytes:
        EN69 is REVIEW-ONLY — deterministic build + selftest green, while
        check-template reports a mismatch (never byte-compared against
        historical goldens, no auto-blessed hash update).

        Calls builder.build_69 directly with the shared evidence validator
        mocked to [] ONLY inside this test process (mock scope:
        panels_builder._sev.validate_run_evidence). Source PNGs, manifest
        hashes, geometry, and template assertions are all real and
        unchanged; retained originals untouched.
        """
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            out.mkdir()
            staged = Path(tmp) / "staged-69"
            frames_dir, manifest_path = stage_retained_with_session(
                RETAINED_RUN_69 / "frames",
                RETAINED_RUN_69 / "run-manifest.json",
                staged, "retained-69-r1", "iphone69")
            caps_obj = panels_builder.load_captions(
                HERE / "captions_en.json")
            caps = panels_builder.validate_captions_for_locale(
                caps_obj, "en")
            captions_version = str(caps_obj.get("version", "unknown"))
            with mock.patch.object(
                    panels_builder._sev, "validate_run_evidence",
                    return_value=[]) as mocked:
                recipe = panels_builder.build_69(
                    "en", caps, captions_version,
                    Path(frames_dir), Path(manifest_path),
                    RETAINED_BEZEL_69, out)
                lines = panels_builder.selftest_69(out, recipe)
                mismatches = panels_builder.check_template(
                    recipe, "en", "6.9")
            mocked.assert_called_once()
            self.assertEqual(len(lines), 5)
            # Review-only: the new approved EN layout no longer reproduces
            # the frozen v13 bytes — the gate must report (not bless) this.
            self.assertTrue(
                mismatches,
                "EN69 with owner-approved breaks/scales must mismatch the "
                "frozen v13 goldens (review-only, never auto-approved)")
            # The approved new EN layout on the retained pixels: insights
            # collapses to one line at the 0.94 pair size, track keeps its
            # preferred two lines.
            key_to_built = {
                "track": "panel-1-track-en-1320x2868.png",
                "insights": "panel-4-insights-en-1320x2868.png",
                "history": "panel-3-history-en-1320x2868.png",
                "add-entry": "panel-5-add-entry-en-1320x2868.png",
                "la": "panel-2-live-activities-en-1320x2868.png",
            }
            for key, built in key_to_built.items():
                self.assertTrue((Path(out) / built).is_file(), key)


@unittest.skipUnless(HAS_PILLOW and HAS_RETAINED_IPAD,
                     "retained ipad-v1 sources required")
class RetainedByteIdenticalIpadTests(unittest.TestCase):
    def test_retained_ipad_byte_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(Path(tmp) / "out")
            Path(out).mkdir()
            staged = Path(tmp) / "staged-ipad"
            frames_dir, manifest_path = stage_retained_with_session(
                RETAINED_RUN_IPAD / "frames",
                RETAINED_RUN_IPAD / "run-manifest.json",
                staged, "retained-ipad-r1", "ipad13")
            proc = run("--locale", "en", "--size", "ipad13",
                       "--panels-dir", out,
                       "--captions", str(HERE / "captions_en.json"),
                       "--frames-dir", frames_dir,
                       "--run-manifest", manifest_path,
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
