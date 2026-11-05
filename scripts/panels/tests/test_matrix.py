#!/usr/bin/env python3
"""Matrix render + bezel stage + bundle README tests (hermetic).

Stdlib unittest + Pillow; no device, no network. Synthetic capture runs
(frames + run manifests) and synthetic bezels are built in tmp dirs.
Bezel staging tests inject a test release manifest (+sha pair) — the
production pinned manifest hash is never weakened globally.
"""

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
PANELS_CLI = str(HERE / "panels.py")
STAGE_CLI = str(HERE / "stage_bezel_assets.py")
README_CLI = str(HERE / "write_bundle_readme.py")

sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "screenshots"))
sys.path.insert(0, str(HERE.parent / "screenshots" / "tests"))

import builder as panels_builder
# Real-producer harness for the end-to-end cross-locale negative
# below (stdlib-only imports: executor/session/capture; no Pillow).
# Importing a screenshots test module is intentional — it owns the
# fake-sim session harness (SessionFakeSimctl/two_domain_run), and
# duplicating ~300 lines here would rot. No side effects at import
# (defs + constants only; unittest.main is __main__-guarded there).
import test_session_run as producer_harness

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
# Attested iPad model — REAL catalog identifier (M5 12GB variant; the
# shared validator requires an exact cataloged model — catalog owner
# aligns SDK IDs separately). Name is operator-assigned evidence
# (presence, not value); udid must equal the run's unanimous frame
# device_udid.
IPAD_MODEL_ID = ("com.apple.CoreSimulator.SimDeviceType."
                 "iPad-Pro-13-inch-M5-12GB")
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


def run_stage(*argv: str):
    return subprocess.run([sys.executable, STAGE_CLI, *argv],
                          capture_output=True, text=True, timeout=120,
                          env=base_env())


def run_readme(*argv: str):
    return subprocess.run([sys.executable, README_CLI, *argv],
                          capture_output=True, text=True, timeout=120,
                          env=base_env())


def write_manifest(path: Path, frames_dir: Path, run_id: str,
                   canvas: tuple[int, int], frames: tuple[str, ...],
                   ci_approval_bypass: bool | None = None,
                   device: str = "iphone69",
                   la_capture: str = "genuine",
                   language: str = "en") -> None:
    """Session-valid manifest + frame records + receipts (+ iPad probe).

    la_capture: "genuine" (external-lock-screen with window/observation
    binding) or "pending" (external-lock-screen-pending with reason).
    PNG files must already exist in frames_dir; their hashes are bound.
    Frame record JSONs and session receipts are written alongside so the
    shared session_evidence validator passes strictly.
    Provenance: manifest carries top-level `locale` (B-field, coordinated
    via main; assumed name `locale`) and run_dir/requests holds one
    session envelope per frame whose inner request payload carries the
    same locale with hash binding (request_sha256 == sha256(request_json)
    == frame record request_sha256). Matrix selection enforces all locale
    claims unanimous == cell language; explicit single-render paths
    bypass selection (retained fixtures preserved).
    """
    run_dir = path.parent
    sessions_dir = run_dir / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    req_dir = run_dir / "requests"
    req_dir.mkdir(parents=True, exist_ok=True)
    # Per-domain seq counters (pinned 0..n, realtime 0..m).
    seq_counters = {"pinned": 0, "realtime": 0}
    recs = []
    transcripts: dict[str, list[dict]] = {}
    envelopes: list[tuple[str, str, int, str, str, str]] = []
    for frame in frames:
        png = frames_dir / f"{frame}.png"
        sha_png = hashlib.sha256(png.read_bytes()).hexdigest()
        domain = _domain_of(frame)
        seq = seq_counters[domain]
        seq_counters[domain] += 1
        nonce = _nonce_of(frame)
        mode = ("app-clock-pinned" if domain == "pinned"
                else "live-activity-realtime")
        payload = {"frame": frame, "locale": language, "run_id": run_id}
        request_json = (json.dumps(payload, sort_keys=True,
                                   separators=(",", ":"),
                                   ensure_ascii=False) + "\n")
        sha_req = hashlib.sha256(request_json.encode("utf-8")).hexdigest()
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
        envelopes.append((frame, nonce, seq, mode, sha_req, request_json))
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
    for frame, nonce, seq, mode, sha_req, request_json in envelopes:
        domain = _domain_of(frame)
        env = {
            "schema_version": 1, "run_id": run_id,
            "session_nonce": nonce, "session_domain": domain,
            "seq": seq, "frame": frame, "mode": mode,
            "request_sha256": sha_req, "request_json": request_json,
        }
        (req_dir /
         f"session-{nonce}-{seq}-{frame}.envelope.json").write_text(
            json.dumps(env, sort_keys=True), encoding="utf-8")
    if device == "ipad13":
        probe = attested_probe(device, run_id, canvas)
        (sessions_dir / "island-probe.json").write_text(
            json.dumps(probe, sort_keys=True), encoding="utf-8")
    manifest: dict = {
        "schema_version": 1, "run_id": run_id, "status": "complete",
        "deck_version": "en-austin-1", "treatment": "light-v1",
        "geometry": {"width": canvas[0], "height": canvas[1]},
        "locale": language,
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
             la_capture: str = "genuine",
             provenance_locale: str | None = None) -> None:
    """Create a synthetic run; provenance locale defaults to the path language.

    Pass provenance_locale != language to forge a cross-locale run (path
    claims one language, request archives + manifest claim another) for
    the real-renderer negative case.
    """
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
                   device=device, la_capture=la_capture,
                   language=(provenance_locale or language))


def forge_ru_cell_from_run(shots: Path, run_dir: Path,
                             src_run_id: str = "sess-en-r1",
                             dst_run_id: str = "sess-ru-r1") -> Path:
    """Copy a REAL producer run under the ru cell with outer run
    identities rewritten (inner hash-bound commands intact — the exact
    inconsistency a copied run produces). Returns the cell dir."""
    cell = shots / "iphone69" / "ru"
    dest = cell / "runs" / dst_run_id
    shutil.copytree(run_dir, dest)

    def _rewrite(obj):
        if isinstance(obj, dict):
            for key, val in obj.items():
                if key == "run_id" and val == src_run_id:
                    obj[key] = dst_run_id
                else:
                    _rewrite(val)
        elif isinstance(obj, list):
            for val in obj:
                _rewrite(val)

    for child in sorted(dest.rglob("*.json")):
        try:
            obj = json.loads(child.read_text(encoding="utf-8"))
        except ValueError:
            continue
        before = json.dumps(obj, sort_keys=True)
        _rewrite(obj)
        if json.dumps(obj, sort_keys=True) != before:
            child.write_text(json.dumps(obj, sort_keys=True) + "\n",
                             encoding="utf-8")
    return cell


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


def make_apple_profile_bytes(native: tuple[int, int],
                             at: tuple[int, int],
                             slot: tuple[int, int],
                             frame_rgb: tuple[int, int, int] = (20, 20, 20)
                             ) -> bytes:
    """Synthetic Apple-profile bezel: exact native dims + exact cavity.

    Sharp-corner transparent slot (no rounded corners, no pill) at the
    exact pinned origin — passes the exact-profile verifiers, which pin
    dimensions/slot/origin (never corner art). Frame RGB is alpha-only
    evidence: verifiers ignore it, so variants stay interchangeable.
    """
    nw, nh = native
    im = Image.new("RGBA", (nw, nh), frame_rgb + (255,))
    # NOTE: PIL rectangles are endpoint-inclusive: far corner at+slot-1.
    ImageDraw.Draw(im).rectangle(
        [at[0], at[1], at[0] + slot[0] - 1, at[1] + slot[1] - 1],
        fill=(0, 0, 0, 0))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def write_stage_manifest(root: Path, items: list, release: str | None = None,
                       repo: str | None = None) -> tuple[Path, Path, str]:
    """Write a synthetic release source dir + manifest from explicit items.

    items: (release_name, png_bytes, geometry_pins) per asset; geometry
    (native/cavity/model/color) is taken from the pins dict while sha256
    is the TRUE hash of the given bytes. Returns (src, manifest, sha).
    """
    src = root / "stage-src"
    src.mkdir(parents=True, exist_ok=True)
    assets = []
    for name, data, pins in items:
        (src / name).write_bytes(data)
        assets.append({
            "name": name,
            "sha256": hashlib.sha256(data).hexdigest(),
            "native": {"width": pins["native"][0],
                       "height": pins["native"][1]},
            "cavity_slot": {"x": pins["at"][0], "y": pins["at"][1],
                            "width": pins["slot"][0],
                            "height": pins["slot"][1]},
            "orientation": "Portrait",
            "model": pins["model"],
            "color": pins["color"],
        })
    manifest = {
        "release": release or panels_builder.APPLE_RELEASE,
        "repo": repo or panels_builder.APPLE_RELEASE_REPO,
        "assets": assets,
    }
    manifest_path = root / "apple-bezels-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True),
                             encoding="utf-8")
    manifest_sha = hashlib.sha256(
        manifest_path.read_bytes()).hexdigest()
    return src, manifest_path, manifest_sha


def write_stage_source(root: Path) -> tuple[Path, Path, str]:
    """Synthetic release source dir + test manifest; returns (src, manifest, sha).

    Test equivalent of the private release: 3 exact-profile PNGs under the
    canonical release filenames plus a manifest carrying their TRUE hashes.
    Callers pass the manifest + its sha via --manifest/--expected-manifest-sha
    (test injection — the production pinned manifest hash stays strict).
    """
    profiles = (
        (panels_builder.APPLE_SOURCE_69, "6.9"),
        (panels_builder.APPLE_SOURCE_63, "6.3"),
        (panels_builder.APPLE_SOURCE_IPAD, "ipad13"),
    )
    items = []
    for pins, _size in profiles:
        items.append((pins["name"],
                      make_apple_profile_bytes(tuple(pins["native"]),
                                               tuple(pins["at"]),
                                               tuple(pins["slot"])),
                      pins))
    return write_stage_manifest(root, items)


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

    def test_matrix_single_fresh_run_id_renders(self):
        # Single-pass (owner decision 2026-11-04): the run identity is a
        # fresh invocation ID, no longer guaranteed to be
        # <device>-<language>-r1. Exactly one selected manifest renders
        # regardless of its name; device binding still enforced.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            fresh = "single-20261104-abc123"
            make_run(shots, "iphone63", "en", fresh,
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
            self.assertEqual(manifest["status"], "complete")
            self.assertEqual(manifest["cells"][0]["run_id"], fresh)
            self.assertEqual(
                len(list((out / "iphone63" / "en").glob(
                    "panel-*-en-1206x2622.png"))), 5)

    def test_matrix_ambiguous_two_runs_blocked(self):
        # Single-pass: two manifests (legacy r1+r2, or two fresh IDs) are
        # ambiguous — the cell blocks, never picks/merges. No r2 fallback.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone63", "en", "iphone63-en-r1",
                     (1206, 2622), FRAME_COLORS_69)
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
            self.assertEqual(proc.returncode, 2)
            self.assertIn("ambiguous", proc.stderr.lower())
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("ambiguous",
                          manifest["cells"][0]["reason"].lower())
            self.assertEqual(
                list((out / "iphone63" / "en").glob("panel-*.png"))
                if (out / "iphone63" / "en").exists() else [], [])

    def test_matrix_status_pointer_selects_single(self):
        # Canonical status pointer (device-worker per-pass
        # <device>-<language>-*.status.json) selects among multiple
        # manifests; without it the same layout is ambiguous-blocked
        # (proven above). Selection is explicit, never a fallback pick.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            fresh = "single-20261104-xyz789"
            make_run(shots, "iphone69", "en", fresh,
                     (1320, 2868), FRAME_COLORS_69)
            cell = shots / "iphone69" / "en"
            (cell / "iphone69-en-r1.status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone69",
                            "locale": "en", "pass": "r1", "status": "ok",
                            "reason": "", "run_id": fresh}),
                encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 0, proc.stderr)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "rendered")
            self.assertEqual(manifest["cells"][0]["run_id"], fresh)

    def test_matrix_malformed_pointer_blocks(self):
        # Fail-closed pointers: a present but malformed status pointer must
        # block even when exactly one manifest exists (no fallback render).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            (shots / "iphone69" / "en" /
             "iphone69-en-r1.status.json").write_text(
                "{not json", encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("pointer",
                          manifest["cells"][0]["reason"].lower())

    def test_matrix_symlink_pointer_blocks(self):
        # Symlinked pointers escape the owned cell; refuse, never follow.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            cell = shots / "iphone69" / "en"
            (cell / "real-status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone69",
                            "locale": "en", "pass": "r1", "status": "ok",
                            "reason": "", "run_id": "only-run"}),
                encoding="utf-8")
            (cell / "iphone69-en-r1.status.json").symlink_to(
                cell / "real-status.json")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("pointer",
                          manifest["cells"][0]["reason"].lower())

    def test_matrix_mismatched_pointer_blocks(self):
        # A pointer declaring another cell's identity must block, even with
        # a unique manifest present (no silent fallback render).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            (shots / "iphone69" / "en" /
             "iphone69-en-r1.status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone63",
                            "locale": "en", "pass": "r1", "status": "ok",
                            "reason": "", "run_id": "only-run"}),
                encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("pointer",
                          manifest["cells"][0]["reason"].lower())

    def test_matrix_bad_runid_pointer_blocks(self):
        # A pointer carrying an unsafe run_id must block (no traversal,
        # no fallback to the lone manifest).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            (shots / "iphone69" / "en" /
             "iphone69-en-r1.status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone69",
                            "locale": "en", "pass": "r1", "status": "ok",
                            "reason": "", "run_id": "../escape"}),
                encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("pointer",
                          manifest["cells"][0]["reason"].lower())

    def test_matrix_ambiguous_pointers_block(self):
        # Two valid pointers selecting different runs are ambiguous: block,
        # never pick one.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "run-a",
                     (1320, 2868), FRAME_COLORS_69)
            make_run(shots, "iphone69", "en", "run-b",
                     (1320, 2868), FRAME_COLORS_69)
            cell = shots / "iphone69" / "en"
            (cell / "iphone69-en-r1.status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone69",
                            "locale": "en", "pass": "r1", "status": "ok",
                            "reason": "", "run_id": "run-a"}),
                encoding="utf-8")
            (cell / "iphone69-en-r2.status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone69",
                            "locale": "en", "pass": "r2", "status": "ok",
                            "reason": "", "run_id": "run-b"}),
                encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("ambiguous",
                          manifest["cells"][0]["reason"].lower())

    def test_matrix_cross_locale_blocked(self):
        # Real-renderer locale binding: an en cell whose selected run
        # carries ru locale provenance (manifest + hash-bound request
        # archives) must block with a locale reason, never render ru art
        # as en. Provenance is hash-bound: forged locale without matching
        # frame hashes also blocks.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69,
                     provenance_locale="ru")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("locale",
                          manifest["cells"][0]["reason"].lower())
            self.assertEqual(
                list((out / "iphone69" / "en").glob("panel-*.png"))
                if (out / "iphone69" / "en").exists() else [], [])

    def test_matrix_missing_locale_provenance_blocked(self):
        # Fail-closed provenance: a run with no manifest locale and no
        # request envelopes must block (locale never inferred from the
        # directory or captions).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "only-run"
            manifest_path = run_dir / "run-manifest.json"
            obj = json.loads(manifest_path.read_text(encoding="utf-8"))
            obj.pop("locale", None)
            manifest_path.write_text(json.dumps(obj), encoding="utf-8")
            shutil.rmtree(run_dir / "requests")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("locale",
                          manifest["cells"][0]["reason"].lower())

    def test_matrix_cross_locale_real_producer_blocked(self):
        # End-to-end cross-locale negative with REAL producer output
        # (moved here from the stdlib-only screenshots lane, which must
        # never import Pillow-dependent panels): a complete EN run
        # built by run_session + genuine registration + finalize_run,
        # copied under the ru cell with outer run identities rewritten.
        # The full matrix renderer must block with a locale reason and
        # emit no ru pixels — EN art must never render as ru.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            udid = f"UDID-xloc-{os.getpid()}"
            run_id = "sess-en-r1"
            _fake, run_dir, _p, realtime = \
                producer_harness.two_domain_run(tmp, udid, run_id)
            gen = producer_harness.PendingToGenuineE2ETests()
            base = producer_harness.base_request(run_id)
            for seq, frame in enumerate(("la-lock", "la-compact",
                                         "la-expanded")):
                request, digest, state, png, sha = \
                    gen._genuine_inputs(tmp, base, frame, seq)
                producer_harness.ex.record_external_frame(
                    run_dir=run_dir, frame=frame, png_src=str(png),
                    captured_at_iso="2026-10-30T10:12:34+00:00",
                    state=state,
                    request=request, request_sha256=digest,
                    pinned_totals=dict(producer_harness.PINNED),
                    device_udid=udid,
                    session_binding={
                        "session_nonce": producer_harness.NONCE_RT,
                        "session_domain": "realtime", "seq": seq})
            manifest, pending = producer_harness.ex.finalize_run(
                run_dir, provenance=dict(producer_harness.PROV))
            self.assertEqual(pending, [])
            self.assertEqual(manifest["status"], "complete")
            self.assertEqual(manifest.get("locale"), "en")
            shots = root / "shots"
            forge_ru_cell_from_run(shots, run_dir)
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["ru"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("locale",
                          manifest["cells"][0]["reason"].lower())
            self.assertEqual(
                list((out / "iphone69" / "ru").glob("panel-*.png"))
                if (out / "iphone69" / "ru").exists() else [], [])

    def test_matrix_device_mismatch_blocked(self):
        # Declared device binding: a manifest whose frames declare a
        # different device_key than the cell refuses cross-device use.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "only-run"
            manifest_path = run_dir / "run-manifest.json"
            obj = json.loads(manifest_path.read_text(encoding="utf-8"))
            for rec in obj.get("frames", []):
                if isinstance(rec, dict):
                    rec["device_key"] = "iphone63"
            manifest_path.write_text(json.dumps(obj), encoding="utf-8")
            for rec_path in (run_dir / "frames").glob("*.json"):
                try:
                    rec_obj = json.loads(
                        rec_path.read_text(encoding="utf-8"))
                except (OSError, ValueError):
                    continue
                if isinstance(rec_obj, dict) and "device_key" in rec_obj:
                    rec_obj["device_key"] = "iphone63"
                    rec_path.write_text(json.dumps(rec_obj, sort_keys=True),
                                        encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("device",
                          manifest["cells"][0]["reason"].lower())

    def test_matrix_run_id_mismatch_blocked(self):
        # Declared run identity: manifest run_id must equal its directory
        # name, else the selection is refused (no silent remap).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            run_dir = shots / "iphone69" / "en" / "runs" / "only-run"
            manifest_path = run_dir / "run-manifest.json"
            obj = json.loads(manifest_path.read_text(encoding="utf-8"))
            obj["run_id"] = "different-id"
            manifest_path.write_text(json.dumps(obj), encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 2)
            manifest = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["cells"][0]["status"], "blocked")
            self.assertIn("run_id",
                          manifest["cells"][0]["reason"].lower())

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
            self.assertIn("no run", proc.stderr)

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
@unittest.skipUnless(HAS_PILLOW, "Pillow required")
class StageBezelTests(unittest.TestCase):
    """Local staging: exact hash + geometry gates, no network, no Figma.

    Production strictness comes from the pinned manifest hash (baked
    default); every test below injects its own manifest (+sha pair) via
    --manifest/--expected-manifest-sha, so the production pin is never
    weakened globally. Synthetic sources use the exact Apple profiles
    (native dims + exact cavities), keeping geometry-code coverage real.
    """

    def _stage(self, src: Path, out: Path, manifest: Path,
               sha: str) -> "subprocess.CompletedProcess[str]":
        return run_stage("--source-dir", str(src), "--out", str(out),
                         "--manifest", str(manifest),
                         "--expected-manifest-sha", sha)

    def test_happy_path_stages_all_three(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            staged = {
                "6.9": panels_builder.APPLE_SOURCE_69,
                "6.3": panels_builder.APPLE_SOURCE_63,
                "ipad13": panels_builder.APPLE_SOURCE_IPAD,
            }
            for size, pins in staged.items():
                final = out / panels_builder.BEZEL_FILES[size]
                self.assertTrue(final.is_file(), size)
                self.assertEqual(
                    hashlib.sha256(final.read_bytes()).hexdigest(),
                    hashlib.sha256(
                        (src / pins["name"]).read_bytes()).hexdigest(),
                    size)
            stage_manifest = json.loads(
                (out / panels_builder.STAGE_MANIFEST_FILE).read_text(
                    encoding="utf-8"))
            self.assertEqual(stage_manifest["release"],
                             panels_builder.APPLE_RELEASE)
            self.assertEqual(stage_manifest["manifest_sha256"], sha)
            self.assertEqual(len(stage_manifest["assets"]), 3)
            self.assertFalse(list(out.glob("*.part")))
            panels_builder.verify_bezel_69(
                out / panels_builder.BEZEL_FILES["6.9"])
            panels_builder.verify_bezel_63(
                out / panels_builder.BEZEL_FILES["6.3"])
            panels_builder.verify_bezel_ipad(
                out / panels_builder.BEZEL_FILES["ipad13"])

    def test_manifest_hash_mismatch_blocks_before_use(self):
        # The pinned manifest hash is checked BEFORE any metadata is
        # used: a one-byte-drifted manifest stages nothing.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            manifest.write_bytes(manifest.read_bytes() + b" ")
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("manifest hash mismatch", proc.stderr)
            self.assertFalse(list(out.glob("*.png"))
                             if out.is_dir() else [])
            self.assertFalse(list(out.glob("*.part"))
                             if out.is_dir() else [])
            self.assertFalse((out / panels_builder.STAGE_MANIFEST_FILE
                              ).exists() if out.is_dir() else False)

    def test_missing_manifest_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, _manifest, _sha = write_stage_source(root)
            out = root / "bezels"
            proc = self._stage(src, out, root / "no-manifest.json",
                               "0" * 64)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("not readable", proc.stderr)

    def test_missing_source_dir_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _src, manifest, sha = write_stage_source(root)
            out = root / "bezels"
            proc = self._stage(root / "no-src", out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("source dir not found", proc.stderr)

    def test_missing_source_file_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            (src / panels_builder.APPLE_ASSET_69).unlink()
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("missing", proc.stderr)
            self.assertFalse(list(out.glob("*.png")))
            self.assertFalse(list(out.glob("*.part")))

    def test_tampered_bytes_blocked_without_partial(self):
        # Tampered first asset: hash gate fires before geometry, nothing
        # staged, no leftovers.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            victim = src / panels_builder.APPLE_ASSET_69
            raw = victim.read_bytes()
            victim.write_bytes(raw[:-8] + b"\x00" * 8)
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("hash mismatch", proc.stderr)
            self.assertFalse(
                (out / panels_builder.BEZEL_FILES["6.9"]).exists())
            self.assertFalse(list(out.glob("*.part")))

    def test_wrong_orientation_blocked(self):
        # Landscape bytes with a truthful manifest (true sha, landscape
        # native dims): the hash gate passes, the profile gate refuses —
        # orientation is never rotated into place.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, _sha = write_stage_source(root)
            bad = io.BytesIO()
            Image.new("RGBA", (3000, 2300), (20, 20, 20, 255)).save(
                bad, format="PNG")
            obj = json.loads(manifest.read_text(encoding="utf-8"))
            landscape = obj["assets"][2]
            landscape["native"] = {"width": 3000, "height": 2300}
            landscape["sha256"] = hashlib.sha256(
                bad.getvalue()).hexdigest()
            (src / landscape["name"]).write_bytes(bad.getvalue())
            manifest.write_text(json.dumps(obj, indent=2, sort_keys=True),
                                encoding="utf-8")
            sha = hashlib.sha256(manifest.read_bytes()).hexdigest()
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("no pinned Apple source profile", proc.stderr)
            self.assertFalse(list(out.glob("*.part")))

    def test_cavity_drift_blocked(self):
        # Right size, shifted cavity, truthful manifest (true sha): the
        # exact-slot gate refuses without scaling or substituting art.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, _sha = write_stage_source(root)
            pins = panels_builder.APPLE_SOURCE_69
            nw, nh = tuple(pins["native"])
            drift = Image.new("RGBA", (nw, nh), (20, 20, 20, 255))
            ImageDraw.Draw(drift).rectangle(
                [100, 100, 100 + pins["slot"][0], 100 + pins["slot"][1]],
                fill=(0, 0, 0, 0))
            buf = io.BytesIO()
            drift.save(buf, format="PNG")
            obj = json.loads(manifest.read_text(encoding="utf-8"))
            obj["assets"][0]["sha256"] = hashlib.sha256(
                buf.getvalue()).hexdigest()
            (src / pins["name"]).write_bytes(buf.getvalue())
            manifest.write_text(json.dumps(obj, indent=2, sort_keys=True),
                                encoding="utf-8")
            sha = hashlib.sha256(manifest.read_bytes()).hexdigest()
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("slot drift", proc.stderr)
            self.assertFalse(
                (out / panels_builder.BEZEL_FILES["6.9"]).exists())
            self.assertFalse(list(out.glob("*.part")))

    def test_malformed_manifest_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            manifest.write_text("{not json", encoding="utf-8")
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("manifest", proc.stderr.lower())

    def test_wrong_release_tag_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, _sha = write_stage_source(root)
            obj = json.loads(manifest.read_text(encoding="utf-8"))
            obj["release"] = "something-else-v9"
            manifest.write_text(json.dumps(obj, indent=2, sort_keys=True),
                                encoding="utf-8")
            sha = hashlib.sha256(manifest.read_bytes()).hexdigest()
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("release", proc.stderr)
            self.assertFalse(list(out.glob("*.png")))

    def test_unsafe_asset_name_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, _sha = write_stage_source(root)
            obj = json.loads(manifest.read_text(encoding="utf-8"))
            obj["assets"][0]["name"] = "../escape.png"
            manifest.write_text(json.dumps(obj, indent=2, sort_keys=True),
                                encoding="utf-8")
            sha = hashlib.sha256(manifest.read_bytes()).hexdigest()
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("unsafe", proc.stderr)

    def test_symlink_source_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            victim = src / panels_builder.APPLE_ASSET_69
            raw = victim.read_bytes()
            victim.unlink()
            (src / "real.png").write_bytes(raw)
            victim.symlink_to(src / "real.png")
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("symlink", proc.stderr)

    def test_repo_out_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            proc = self._stage(src, HERE / "stage-out", manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("inside the repository", proc.stderr)

    def test_bad_ipad_yields_partial_bundle(self):
        """A bad iPad source blocks staging but keeps verified iPhones.

        Mirrors the retired landscape-fetch partial bundle: successfully
        staged bezels persist (no partial writes, no .part leftovers),
        and render-matrix over them renders iPhone cells while blocking
        the iPad cell with an explicit reason — a partial handoff
        bundle, never fabricated iPad panels and never a silent no-ZIP.
        """
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            victim = src / panels_builder.APPLE_ASSET_IPAD
            raw = victim.read_bytes()
            victim.write_bytes(raw[:-8] + b"\x00" * 8)
            bezels = root / "bezels"
            staged = self._stage(src, bezels, manifest, sha)
            self.assertEqual(staged.returncode, 2)
            self.assertIn("hash mismatch", staged.stderr)
            panels_builder.verify_bezel_69(
                bezels / panels_builder.BEZEL_FILES["6.9"])
            panels_builder.verify_bezel_63(
                bezels / panels_builder.BEZEL_FILES["6.3"])
            self.assertFalse(
                (bezels / panels_builder.BEZEL_FILES["ipad13"]).exists())
            self.assertFalse(list(bezels.glob("*.part")))

            shots = root / "shots"
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            out = root / "out"
            rendered = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69","ipad13"]',
                "--languages", '["en"]')
            self.assertEqual(rendered.returncode, 2)
            manifest_out = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest_out["status"], "incomplete")
            self.assertEqual(manifest_out["counts"],
                             {"blocked": 1, "cells": 2, "rendered": 1})
            by_device = {c["device"]: c for c in manifest_out["cells"]}
            self.assertEqual(by_device["iphone69"]["status"], "rendered")
            self.assertEqual(by_device["ipad13"]["status"], "blocked")
            self.assertIn("missing bezel asset",
                          by_device["ipad13"]["reason"])
            self.assertEqual(
                list((out / "ipad13").rglob("panel-*.png"))
                if (out / "ipad13").exists() else [], [])

    def test_staged_apple_bezels_render_matrix_green(self):
        # End-to-end over staged Apple-profile art: one en cell per size
        # renders complete (selection + evidence + selftests green).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src, manifest, sha = write_stage_source(root)
            bezels = root / "bezels"
            staged = self._stage(src, bezels, manifest, sha)
            self.assertEqual(staged.returncode, 0, staged.stderr)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            make_run(shots, "iphone63", "en", "iphone63-en-r1",
                     (1206, 2622), FRAME_COLORS_69)
            make_run(shots, "ipad13", "en", "ipad13-en-r1",
                     (2064, 2752), FRAME_COLORS_IPAD)
            out = root / "out"
            proc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69","iphone63","ipad13"]',
                "--languages", '["en"]')
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("status=complete", proc.stdout)
            matrix = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(matrix["status"], "complete")
            self.assertEqual(
                len(list((out / "iphone69" / "en").glob(
                    "panel-*-en-1320x2868.png"))), 5)
            self.assertEqual(
                len(list((out / "iphone63" / "en").glob(
                    "panel-*-en-1206x2622.png"))), 5)
            self.assertEqual(
                len(list((out / "ipad13" / "en").glob(
                    "panel-*-en-2064x2752.png"))), 4)

    def _apple_items(self, extra_69=None):
        """Standard 3 synthetic items plus an optional extra 6.9 asset.

        extra_69: (release_name, png_bytes) staged alongside the 17PM
        file — both map to size 6.9, exercising preferred selection.
        """
        std = [(p["name"],
                make_apple_profile_bytes(tuple(p["native"]),
                                         tuple(p["at"]),
                                         tuple(p["slot"])), p)
               for p in (panels_builder.APPLE_SOURCE_69,
                         panels_builder.APPLE_SOURCE_63,
                         panels_builder.APPLE_SOURCE_IPAD)]
        if extra_69 is not None:
            name, data = extra_69
            std.append((name, data, panels_builder.APPLE_SOURCE_18PM))
        return std

    def test_v2_18pm_preferred_over_17pm(self):
        # v2 carries the 17PM file for history next to the current 18PM
        # file: the 6.9 frame stages the preferred 18PM bytes, never the
        # superseded file and never a merge of both.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pins18 = panels_builder.APPLE_SOURCE_18PM
            extra = make_apple_profile_bytes(tuple(pins18["native"]),
                                             tuple(pins18["at"]),
                                             tuple(pins18["slot"]),
                                             frame_rgb=(30, 30, 32))
            items = self._apple_items(extra_69=(pins18["name"], extra))
            src, manifest, sha = write_stage_manifest(root, items)
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("selects preferred", proc.stdout)
            final = out / panels_builder.BEZEL_FILES["6.9"]
            self.assertEqual(final.read_bytes(), extra)
            stage_manifest = json.loads(
                (out / panels_builder.STAGE_MANIFEST_FILE).read_text(
                    encoding="utf-8"))
            by_file = {a["staged_file"]: a
                       for a in stage_manifest["assets"]}
            self.assertEqual(by_file["iphone-69-bezel.png"]["release_name"],
                             pins18["name"])
            self.assertEqual(len(stage_manifest["assets"]), 3)
            self.assertFalse(list(out.glob("*.part")))

    def test_v2_duplicate_without_preferred_refuses(self):
        # Same-geometry candidates, none the pinned preferred file:
        # refuse everything (fail-closed before any write), never pick one.
        # NOTE: the standard 17PM-named file is itself non-preferred once
        # 18PM is pinned preferred — three competing 6.9 files here.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pins = panels_builder.APPLE_SOURCE_69
            items = self._apple_items()[:1] + [
                ("legacy-a.png",
                 make_apple_profile_bytes(tuple(pins["native"]),
                                          tuple(pins["at"]),
                                          tuple(pins["slot"])), pins),
                ("legacy-b.png",
                 make_apple_profile_bytes(tuple(pins["native"]),
                                          tuple(pins["at"]),
                                          tuple(pins["slot"])), pins),
            ]
            src, manifest, sha = write_stage_manifest(root, items)
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("no single preferred", proc.stderr)
            self.assertFalse(list(out.glob("*.png")))
            self.assertFalse(list(out.glob("*.part")))

    def test_v1_release_still_stages_with_explicit_sha(self):
        # v1 stays supported for historical bundles already staged: an
        # explicit v1-tagged manifest + its sha stages the 17PM file as
        # the sole 6.9 candidate. New staging defaults to v2 (suite
        # default), never to v1.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            std = [(p["name"],
                    make_apple_profile_bytes(tuple(p["native"]),
                                             tuple(p["at"]),
                                             tuple(p["slot"])), p)
                   for p in (panels_builder.APPLE_SOURCE_69,
                             panels_builder.APPLE_SOURCE_63,
                             panels_builder.APPLE_SOURCE_IPAD)]
            src, manifest, sha = write_stage_manifest(
                root, std, release=panels_builder.APPLE_RELEASE_V1)
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            final = out / panels_builder.BEZEL_FILES["6.9"]
            self.assertTrue(final.is_file())
            info = panels_builder.verify_bezel_69(final)
            self.assertEqual(info["profile"], "apple-17pm-v1")
            stage_manifest = json.loads(
                (out / panels_builder.STAGE_MANIFEST_FILE).read_text(
                    encoding="utf-8"))
            self.assertEqual(
                stage_manifest["release"], panels_builder.APPLE_RELEASE_V1)

    def test_wrong_release_tag_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            std = [(p["name"],
                    make_apple_profile_bytes(tuple(p["native"]),
                                             tuple(p["at"]),
                                             tuple(p["slot"])), p)
                   for p in (panels_builder.APPLE_SOURCE_69,
                             panels_builder.APPLE_SOURCE_63,
                             panels_builder.APPLE_SOURCE_IPAD)]
            src, manifest, sha = write_stage_manifest(
                root, std, release="apple-bezels-v9")
            out = root / "bezels"
            proc = self._stage(src, out, manifest, sha)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("not in pinned", proc.stderr)
            self.assertFalse(list(out.glob("*.png")))
            self.assertFalse(list(out.glob("*.part")))

    def test_stage_real_v2_when_present(self):
        # Real-file acceptance against the /tmp working-copy release dir
        # (exact bytes, canonical names) with the BAKED v2 default — no
        # sha override. Skips where the private bytes are absent; raw art
        # is only ever read, never committed.
        src = Path(os.environ.get("LIFIO_V2_BEZELS_DIR",
                                  "/tmp/lifio-design-assets-v2"))
        manifest = src / panels_builder.APPLE_MANIFEST_NAME
        wanted = [panels_builder.APPLE_ASSET_18PM,
                  panels_builder.APPLE_ASSET_63,
                  panels_builder.APPLE_ASSET_IPAD]
        if not manifest.is_file() or any(
                not (src / name).is_file() for name in wanted):
            self.skipTest("v2 working-copy bytes absent")
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "bezels"
            proc = run_stage("--source-dir", str(src),
                             "--out", str(out),
                             "--manifest", str(manifest))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            final = out / panels_builder.BEZEL_FILES["6.9"]
            self.assertEqual(
                hashlib.sha256(final.read_bytes()).hexdigest(),
                panels_builder.APPLE_SOURCE_18PM["sha256"])
            info = panels_builder.verify_bezel_69(final)
            self.assertEqual(info["profile"], "apple-18pm-v1")
            stage_manifest = json.loads(
                (out / panels_builder.STAGE_MANIFEST_FILE).read_text(
                    encoding="utf-8"))
            self.assertEqual(stage_manifest["release"], "apple-bezels-v2")
            self.assertEqual(
                stage_manifest["manifest_sha256"],
                panels_builder.APPLE_MANIFEST_SHA256)


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

    def test_readme_inventories_bezel_stage_log(self):
        # Handoff/debug bundle: the bezel-stage transcript travels in the
        # ZIP, so the README file inventory must name it WITH its sha256
        # (evidence present, not merely mentioned in a blocked reason).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = make_shots_matrix(root)
            panels_dir = root / "panels"
            (panels_dir / "iphone69" / "en").mkdir(parents=True)
            (panels_dir / "matrix-manifest.json").write_text(
                json.dumps({
                    "schema_version": 1, "status": "incomplete",
                    "counts": {"cells": 2, "rendered": 1, "blocked": 1},
                    "cells": [{"device": "iphone69", "language": "en",
                               "size": "6.9", "status": "rendered",
                               "run_id": "iphone69-en-r1",
                               "captions_version": "captions-v1",
                               "panels": {"a.png": "abc"}},
                              {"device": "ipad13", "language": "en",
                               "size": "ipad13", "status": "blocked",
                               "reason": "missing bezel asset X"}]}),
                encoding="utf-8")
            Image.new("RGB", (8, 8)).save(
                panels_dir / "iphone69" / "en" / "panel-track-en-8x8.png")
            stage_log = panels_dir / "bezel-stage.json"
            stage_log.write_text(
                json.dumps({"schema_version": 1,
                            "release": "apple-bezels-v1",
                            "manifest_sha256": "0" * 64,
                            "assets": []}), encoding="utf-8")
            digest = hashlib.sha256(
                stage_log.read_bytes()).hexdigest()
            out = root / "bundle-readme.md"
            proc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69","ipad13"]',
                "--languages", '["en"]',
                "--out", str(out),
                "--commit", "deadbee", "--dirty", "false")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertIn("HANDOFF", text)
            self.assertIn(f"bezel-stage.json {digest}", text)

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

    def test_readme_single_fresh_run_id_harvests(self):
        # Single-pass README: a fresh invocation run ID harvests (no
        # hardcoded <device>-<language>-r1 lookup, no r2 fallback).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            fresh = "single-20261104-abc123"
            make_run(shots, "iphone69", "en", fresh,
                     (1320, 2868), FRAME_COLORS_69,
                     ci_approval_bypass=False)
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
            self.assertIn(fresh, text)
            self.assertIn("en-austin-1", text)
            self.assertNotIn("ambiguous", text.lower())

    def test_readme_ambiguous_two_runs_marked(self):
        # Single-pass README: multiple manifests never pick/merge — the
        # deck row reads ambiguous (truthful handoff, never invented).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            make_run(shots, "iphone69", "en", "iphone69-en-r2",
                     (1320, 2868), FRAME_COLORS_69)
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
            self.assertIn("ambiguous", text.lower())

    def test_readme_matches_rendered_matrix_run_id(self):
        # Shared selection: with two manifests + a pointer selecting the
        # fresh run, the rendered matrix cell and the README deck row must
        # report the SAME run_id (no divergence).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "iphone69-en-r1",
                     (1320, 2868), FRAME_COLORS_69)
            fresh = "single-20261104-xyz789"
            make_run(shots, "iphone69", "en", fresh,
                     (1320, 2868), FRAME_COLORS_69)
            (shots / "iphone69" / "en" /
             "iphone69-en-r1.status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone69",
                            "locale": "en", "pass": "r1", "status": "ok",
                            "reason": "", "run_id": fresh}),
                encoding="utf-8")
            bezels = root / "bezels"
            write_bezels(bezels)
            out = root / "out"
            mproc = run_panels(
                "--render-matrix", "--shots-dir", str(shots),
                "--bezels-dir", str(bezels), "--out", str(out),
                "--devices", '["iphone69"]', "--languages", '["en"]')
            self.assertEqual(mproc.returncode, 0, mproc.stderr)
            matrix = json.loads(
                (out / "matrix-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(matrix["cells"][0]["status"], "rendered")
            panels_run = matrix["cells"][0]["run_id"]
            self.assertEqual(panels_run, fresh)
            panels_dir = root / "panels"
            panels_dir.mkdir()
            readme_out = root / "readme.md"
            rproc = run_readme(
                "--panels-dir", str(panels_dir),
                "--shots-dir", str(shots),
                "--ios-runtime", "iOS 27.0",
                "--devices", '["iphone69"]', "--languages", '["en"]',
                "--out", str(readme_out),
                "--commit", "x", "--dirty", "false")
            self.assertEqual(rproc.returncode, 0, rproc.stderr)
            text = readme_out.read_text(encoding="utf-8")
            m = re.search(r"\| iphone69 \| en \| ([^|]+) \|", text)
            self.assertIsNotNone(m, text)
            self.assertEqual(m.group(1).strip(), panels_run)

    def test_readme_pointer_missing_manifest_marked(self):
        # A pointer selecting an absent manifest blocks the README deck
        # too (never harvests the lone unselected manifest).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            (shots / "iphone69" / "en" /
             "iphone69-en-r1.status.json").write_text(
                json.dumps({"schema_version": 1, "device": "iphone69",
                            "locale": "en", "pass": "r1", "status": "ok",
                            "reason": "", "run_id": "ghost-run"}),
                encoding="utf-8")
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
            self.assertNotIn("| iphone69 | en | only-run |", text)
            self.assertTrue(
                "unreadable" in text.lower() or "ambiguous" in text.lower()
                or "unverified" in text.lower(), text)

    def test_readme_malformed_pointer_marked(self):
        # A malformed pointer blocks README harvesting (fail-closed, never
        # falls back to the lone manifest).
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            make_run(shots, "iphone69", "en", "only-run",
                     (1320, 2868), FRAME_COLORS_69)
            (shots / "iphone69" / "en" /
             "iphone69-en-r1.status.json").write_text(
                "{not json", encoding="utf-8")
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
            self.assertNotIn("| iphone69 | en | only-run |", text)


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
