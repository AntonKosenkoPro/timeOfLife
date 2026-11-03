#!/usr/bin/env python3
"""read_timer.py tests (no device; Vision-gated tests skip without macOS).

Vision integration tests run only on darwin with the `swift` driver
present; the retained-golden test additionally requires
LIFIO_RETAINED_FRAMES to point at a directory holding genuine la-lock /
la-compact / la-expanded PNGs with sibling frame-record JSONs carrying
``capture_window.observed_elapsed_s`` (e.g. runs/pilot27-r2/frames).
Everything else is hermetic: parsing/ROI selection run on synthetic
observation lists shaped like the real Vision output, and CLI wiring is
tested through the importable functions with a stubbed OCR backend.
"""

import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import read_timer as rt

SWIFT_PRESENT = shutil.which("swift") is not None
ON_DARWIN = sys.platform == "darwin"
VISION_TEST = ON_DARWIN and SWIFT_PRESENT

RETAINED_DIR = os.environ.get("LIFIO_RETAINED_FRAMES")
RETAINED_TEST = (
    VISION_TEST
    and bool(RETAINED_DIR)
    and Path(RETAINED_DIR).is_dir()
)


def obs(text, x, y, w=0.1, h=0.02, confidence=1.0):
    return {"text": text, "confidence": confidence,
            "bbox": [x, y, w, h]}


# Synthetic observations shaped like the real pilot27-r2 Vision output
# (normalized top-left boxes): each frame's ROI must keep the system
# timer and drop the 09:41 chrome confounder.
LOCK_OBS = [
    obs("Sat 1 Jan", 0.397, 0.090),
    obs("09:41", 0.145, 0.125, w=0.716, h=0.099),
    obs("Morning run", 0.154, 0.806),
    obs("12:49", 0.155, 0.830, w=0.095, h=0.015),
    obs("Swipe up to open", 0.360, 0.939),
]
COMPACT_OBS = [
    obs("09:41", 0.085, 0.026, w=0.114, h=0.017),
    obs("Fitness", 0.107, 0.177),
    obs("12:44", 0.672, 0.029, w=0.088, h=0.012),
    obs("Lifio", 0.811, 0.291),
]
EXPANDED_OBS = [
    obs("12:47", 0.088, 0.047, w=0.170, h=0.025),
    obs("Stop", 0.808, 0.049),
    obs("Morning run", 0.091, 0.102),
    obs("* Sport", 0.107, 0.131),
]


def write_minimal_png(path: Path, width: int = 64, height: int = 64,
                       rgb: bytes = b"\xff\xff\xff") -> None:
    """Solid-color PNG via stdlib (proves the Vision bridge executes)."""
    raw = b"".join(b"\x00" + rgb * width for _ in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    idat = zlib.compress(raw)
    out = [b"\x89PNG\r\n\x1a\n"]
    for ctype, data in ((b"IHDR", ihdr), (b"IDAT", idat)):
        out.append(struct.pack(">I", len(data)) + ctype + data
                   + struct.pack(">I", zlib.crc32(ctype + data) & 0xFFFFFFFF))
    path.write_bytes(b"".join(out))


class ParseTimerTests(unittest.TestCase):
    def test_plain_m_ss(self):
        self.assertEqual(rt.parse_timer_text("12:49"), 12 * 60 + 49)
        self.assertEqual(rt.parse_timer_text("9:41"), 9 * 60 + 41)
        self.assertEqual(rt.parse_timer_text("0:00"), 0)

    def test_h_mm_ss(self):
        self.assertEqual(rt.parse_timer_text("1:02:03"), 3723)
        self.assertEqual(rt.parse_timer_text("12:34:56"), 45296)

    def test_ocr_separator_variants(self):
        self.assertEqual(rt.parse_timer_text("12.49"), 769)
        self.assertEqual(rt.parse_timer_text("12;49"), 769)
        self.assertEqual(rt.parse_timer_text("12 : 49"), 769)

    def test_non_timer_rejected(self):
        for text in ("Sat 1 Jan", "Morning run", "Swipe up to open",
                     "Stop", "* Sport", "Fitness", "", "12", "abc"):
            self.assertIsNone(rt.parse_timer_text(text), text)

    def test_out_of_range_rejected(self):
        self.assertIsNone(rt.parse_timer_text("12:99"))
        self.assertIsNone(rt.parse_timer_text("75:00"))
        self.assertIsNone(rt.parse_timer_text("1:02:99"))


class SelectTimerTests(unittest.TestCase):
    def test_lock_roi_drops_lock_clock(self):
        value, roi = rt.select_timer_value(LOCK_OBS, "la-lock")
        self.assertEqual(value, 769)
        self.assertNotIn("09:41", [o["text"] for o in roi])

    def test_compact_roi_drops_status_bar(self):
        value, roi = rt.select_timer_value(COMPACT_OBS, "la-compact")
        self.assertEqual(value, 764)
        self.assertNotIn("09:41", [o["text"] for o in roi])

    def test_expanded_roi_picks_card_timer(self):
        value, _ = rt.select_timer_value(EXPANDED_OBS, "la-expanded")
        self.assertEqual(value, 767)

    def test_unreadable_fails_loudly(self):
        with self.assertRaises(rt.ReadTimerError):
            rt.select_timer_value([obs("Morning run", 0.15, 0.83)],
                                  "la-lock")

    def test_ambiguous_values_fail_loudly(self):
        with self.assertRaises(rt.ReadTimerError):
            rt.select_timer_value(
                [obs("12:49", 0.15, 0.83), obs("12:50", 0.15, 0.86)],
                "la-lock")

    def test_duplicate_same_value_is_fine(self):
        value, _ = rt.select_timer_value(
            [obs("12:49", 0.15, 0.83), obs("12:49", 0.16, 0.835)],
            "la-lock")
        self.assertEqual(value, 769)

    def test_unknown_frame_fails(self):
        with self.assertRaises(rt.ReadTimerError):
            rt.select_timer_value(LOCK_OBS, "track-running")


class ReadTimerWiringTests(unittest.TestCase):
    def _png(self, tmp: str) -> str:
        p = str(Path(tmp) / "frame.png")
        write_minimal_png(Path(p))
        return p

    def test_wiring_writes_hash_bound_observation(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = self._png(tmp)
            sha = hashlib.sha256(Path(png).read_bytes()).hexdigest()
            fake = [dict(o) for o in LOCK_OBS]
            with mock.patch.object(rt, "run_ocr", return_value=fake):
                got = rt.read_timer("la-lock", png,
                                    "2026-10-30T13:14:48+02:00")
            self.assertEqual(got, {"observed_elapsed_s": 769,
                                   "screenshot_sha256": sha})

    def test_non_la_frame_refused_before_ocr(self):
        with mock.patch.object(rt, "run_ocr") as ocr:
            with self.assertRaises(rt.ReadTimerError):
                rt.read_timer("track-running", "/nonexistent.png",
                              "2026-10-30T13:14:48+02:00")
            ocr.assert_not_called()

    def test_naive_captured_at_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = self._png(tmp)
            with mock.patch.object(rt, "run_ocr") as ocr:
                with self.assertRaises(rt.ReadTimerError):
                    rt.read_timer("la-lock", png, "2026-10-30T13:14:48")
                ocr.assert_not_called()

    def test_missing_png_refused(self):
        with mock.patch.object(rt, "run_ocr") as ocr:
            with self.assertRaises(rt.ReadTimerError):
                rt.read_timer("la-lock", "/nonexistent/la.png",
                              "2026-10-30T13:14:48+02:00")
            ocr.assert_not_called()

    def test_non_png_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = str(Path(tmp) / "note.txt")
            Path(bad).write_text("not a png")
            with mock.patch.object(rt, "run_ocr") as ocr:
                with self.assertRaises(rt.ReadTimerError):
                    rt.read_timer("la-lock", bad,
                                  "2026-10-30T13:14:48+02:00")
                ocr.assert_not_called()


class CliTests(unittest.TestCase):
    CLI = str(HERE / "read_timer.py")

    def run_cli(self, *argv: str):
        env = dict(os.environ)
        return subprocess.run([sys.executable, self.CLI, *argv],
                              capture_output=True, text=True,
                              timeout=240, env=env)

    def test_cli_fail_closed_without_vision(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(Path(tmp) / "obs.json")
            proc = self.run_cli("--frame", "track-running", "--png", "/nope.png",
                                "--captured-at", "2026-10-30T13:14:48+02:00",
                                "--out", out)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("failed:", proc.stderr)
            proc = self.run_cli("--frame", "la-lock", "--png", "/nope.png",
                                "--captured-at", "2026-10-30T13:14:48",
                                "--out", out)
            self.assertEqual(proc.returncode, 2)
            self.assertFalse(Path(out).exists())

    def test_cli_missing_and_non_png(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(Path(tmp) / "obs.json")
            proc = self.run_cli("--frame", "la-lock", "--png",
                                str(Path(tmp) / "missing.png"),
                                "--captured-at", "2026-10-30T13:14:48+02:00",
                                "--out", out)
            self.assertEqual(proc.returncode, 2)
            bad = str(Path(tmp) / "note.txt")
            Path(bad).write_text("not a png")
            proc = self.run_cli("--frame", "la-lock", "--png", bad,
                                "--captured-at", "2026-10-30T13:14:48+02:00",
                                "--out", out)
            self.assertEqual(proc.returncode, 2)
            self.assertFalse(Path(out).exists())

    @unittest.skipUnless(VISION_TEST, "requires macOS with the swift driver")
    def test_cli_blank_png_fails_loudly(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = str(Path(tmp) / "blank.png")
            write_minimal_png(Path(png), width=200, height=80)
            out = str(Path(tmp) / "obs.json")
            proc = self.run_cli("--frame", "la-lock", "--png", png,
                                "--captured-at", "2026-10-30T13:14:48+02:00",
                                "--out", out)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("no timer-shaped text", proc.stderr)
            self.assertFalse(Path(out).exists())

    @unittest.skipUnless(RETAINED_TEST,
                         "requires LIFIO_RETAINED_FRAMES with genuine LA PNGs")
    def test_retained_frames_match_known_observations(self):
        assert RETAINED_DIR is not None
        retained = Path(RETAINED_DIR)
        for frame in ("la-lock", "la-compact", "la-expanded"):
            with self.subTest(frame=frame):
                png = str(retained / f"{frame}.png")
                record = json.loads(
                    (retained / f"{frame}.json").read_text(encoding="utf-8"))
                expected = record["capture_window"]["observed_elapsed_s"]
                captured_at = record["capture_window"]["captured_at_iso"]
                with tempfile.TemporaryDirectory() as tmp:
                    out = str(Path(tmp) / "obs.json")
                    proc = self.run_cli("--frame", frame, "--png", png,
                                        "--captured-at", captured_at,
                                        "--out", out)
                    self.assertEqual(proc.returncode, 0, proc.stderr)
                    got = json.loads(Path(out).read_text(encoding="utf-8"))
                    self.assertEqual(got["observed_elapsed_s"], expected)
                    self.assertEqual(got["screenshot_sha256"],
                                     record["screenshot_sha256"])
                    self.assertEqual(
                        got, json.loads(Path(out).read_bytes().decode()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
