#!/usr/bin/env python3
"""Legacy-removal regressions (task 8.5 Python portion).

The temporary v1 per-frame comparison path is gone: its CLI verbs no
longer parse, its request flag is unrecognized, and its runs are
explicitly rejected by finalization (never silently downgraded). These
tests fail against the old tree (verbs parse / v1 finalizes) and pass
after removal. No device, tmp only; subprocess CLI like test_cli.py.
"""

import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
CLI = str(HERE / "capture.py")

sys.path.insert(0, str(HERE))

REMOVED_VERBS = ("prepare-frame", "capture-app-frame", "teardown-frame",
                 "run-frame", "record-pending-frame")


def run_cli(*argv: str):
    import os
    env = dict(os.environ)
    env.pop("LIFIO_CAPTURE_LEASE", None)
    env.pop("LIFIO_CAPTURE_CI", None)
    return subprocess.run([sys.executable, CLI, *argv],
                          capture_output=True, text=True, timeout=60, env=env)


def write_png(path: Path, width: int = 1320, height: int = 2868) -> None:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                     + ihdr + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))


def write_v1_run(tmp: str) -> Path:
    """Minimal historical per-frame run: keyless records + PNGs + v1
    per-frame teardowns. Current tooling must explicitly reject it."""
    import hashlib

    run_dir = Path(tmp) / "runs" / "v1-old-r1"
    (run_dir / "frames").mkdir(parents=True)
    (run_dir / "sessions").mkdir(parents=True)
    totals = {"all_seconds": 1, "today_seconds": 1, "week_seconds": 1,
              "category_seconds": {"A": 1}, "text_seconds": {"B": 1}}
    for frame in ("track-running", "insights", "history", "add-entry",
                  "la-lock", "la-compact", "la-expanded"):
        png = run_dir / "frames" / f"{frame}.png"
        write_png(png)
        rec = {"schema_version": 1, "frame": frame,
               "mode": "live-activity-realtime"
               if frame.startswith("la-") else "app-clock-pinned",
               "device_udid": "UDID-1", "run_id": "v1-old-r1",
               "deck_version": "en-austin-1", "treatment": "light-v1",
               "request_sha256": "a" * 64,
               "request_semantic_sha256": "b" * 64,
               "screenshot_sha256": hashlib.sha256(
                   png.read_bytes()).hexdigest(),
               "geometry": {"width": 1320, "height": 2868},
               "expected_totals": dict(totals),
               "capture": ("external-lock-screen-pending"
                           if frame.startswith("la-") else "native-simctl"),
               "pending_reason": "old handoff"
               if frame.startswith("la-") else None}
        if rec["pending_reason"] is None:
            del rec["pending_reason"]
        (run_dir / "frames" / f"{frame}.json").write_text(
            json.dumps(rec, sort_keys=True), encoding="utf-8")
        (run_dir / "sessions" / f"{frame}.teardown.json").write_text(
            json.dumps({"schema_version": 1, "frame": frame,
                        "device_udid": "UDID-1", "run_id": "v1-old-r1",
                        "chrome_restored": True, "app_terminated": True,
                        "app_cleanup": {"status": "cleaned",
                                        "removed_session": True},
                        "status": "complete", "failures": []},
                       sort_keys=True), encoding="utf-8")
    return run_dir


class RemovedVerbsTests(unittest.TestCase):
    def test_removed_verbs_fail_at_parse(self):
        for verb in REMOVED_VERBS:
            with self.subTest(verb=verb):
                proc = run_cli(verb, "--help")
                self.assertEqual(proc.returncode, 2, (verb, proc.stdout))
                self.assertIn("invalid choice", proc.stderr, verb)

    def test_record_external_request_flag_unrecognized(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run_cli(
                "record-external-frame", "--out", tmp, "--run-id", "r1",
                "--frame", "la-lock", "--png", "/nonexistent.png",
                "--captured-at", "2026-10-30T10:12:34+00:00",
                "--observation", "/nonexistent.json",
                "--state", "/nonexistent.json",
                "--request", str(HERE / "pilot_manifest.json"))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("unrecognized arguments", proc.stderr)


class RejectedV1RunTests(unittest.TestCase):
    def test_finalize_rejects_v1_run(self):
        import executor as ex

        with tempfile.TemporaryDirectory() as tmp:
            run_dir = write_v1_run(tmp)
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(
                    run_dir,
                    provenance={"commit_base": "c3e5911-test", "dirty": True})
            self.assertIn("legacy", str(ctx.exception).lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
