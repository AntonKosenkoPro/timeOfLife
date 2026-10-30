#!/usr/bin/env python3
"""Preflight argv surface, restore policy, manifest stability, inspection.

Asserts the runner emits ONLY confirmed simctl surfaces (no guessed
locale/keyboard/global-prefs commands) and that human-observation gates
refuse final status until real evidence is supplied.
"""

import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import inspection as insp
import preflight as pf
import request_schema as rs
import run_manifest as rm


def base_request() -> dict:
    base = json.loads((HERE / "pilot_manifest.json").read_text(encoding="utf-8"))
    return {k: v for k, v in base.items() if k not in ("frame", "mode")}


def write_png(path: Path, width: int, height: int) -> None:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = (b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + ihdr
           + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))
    path.write_bytes(raw)


class PreflightSurfaceTests(unittest.TestCase):
    BANNED = ("locale", "keyboard", "global", "prefs", "AppleLocale",
              "AppleLanguages", "timezone", "defaults")

    def _all_argv(self):
        cmds = (pf.snapshot_commands("UDID-X") + pf.apply_commands("UDID-X")
                + [pf.launch_argv("UDID-X")]
                + [pf.screenshot_argv("UDID-X", "/tmp/x.png")])
        return [" ".join(c) for c in cmds]

    def test_no_guessed_surfaces(self):
        for line in self._all_argv():
            for banned in self.BANNED:
                self.assertNotIn(banned, line, f"banned token in: {line}")

    def test_snapshot_is_read_only(self):
        for argv in pf.snapshot_commands("U"):
            self.assertNotIn("override", argv)
            self.assertNotIn("clear", argv)

    def test_status_bar_override_uses_confirmed_flags(self):
        apply = pf.apply_commands("U")
        override = [c for c in apply if "status_bar" in c][0]
        for flag in ("--time", "--batteryState", "--batteryLevel",
                     "--wifiMode", "--wifiBars", "--dataNetwork"):
            self.assertIn(flag, override)

    def test_restore_exact_or_nothing(self):
        # session-owned override on clean snapshot -> clear emitted
        r = pf.restore_commands("U", "light", "large", True, True)
        self.assertIn(["xcrun", "simctl", "status_bar", "U", "clear"], r)
        # preexisting overrides -> never clear
        r2 = pf.restore_commands("U", "dark", "extra-large", True, False)
        self.assertNotIn(["xcrun", "simctl", "status_bar", "U", "clear"], r2)
        # exact prior values restored
        self.assertIn(["xcrun", "simctl", "ui", "U", "appearance", "dark"], r2)

    def test_launch_argv_binding(self):
        argv = pf.launch_argv("UDID-9")
        self.assertIn("--terminate-running-process", argv)
        self.assertEqual(argv[-2:], ["SCREENSHOT_REQUEST", "capture-request.json"])
        self.assertIn(rs.SCREENSHOT_BID, argv)

    def test_plan_run_guards(self):
        with self.assertRaises(ValueError):
            pf.plan_run(base_request(), ["track-running"], "", "/tmp", "r")
        with self.assertRaises(ValueError):
            pf.plan_run(base_request(), list(rs.PILOT_FRAMES), "booted", "/tmp", "r")
        # 'booted' auto-pick is a CLI-level reject; planner requires explicit UDID
        plan = pf.plan_run(base_request(), list(rs.PILOT_FRAMES), "A" * 8, "/tmp", "r1")
        self.assertEqual(len(plan["steps"]), 7)
        self.assertEqual(plan["geometry"], {"width": 1320, "height": 2868})
        # matrix geometries plan truthfully; CLI approval gate authorizes them
        ipad = pf.plan_run(base_request(), list(rs.PILOT_FRAMES), "A" * 8,
                           "/tmp", "r1", geometry=(2064, 2752))
        self.assertEqual(ipad["geometry"], {"width": 2064, "height": 2752})
        with self.assertRaises(ValueError):
            pf.plan_run(base_request(), list(rs.PILOT_FRAMES), "A" * 8,
                        "/tmp", "r1", geometry=(100, 100))


class ManifestStabilityTests(unittest.TestCase):
    TOTALS = {"all_seconds": 1, "today_seconds": 1, "week_seconds": 1,
              "category_seconds": {"A": 1}, "text_seconds": {"B": 1}}

    def _rec(self, frame, req_sha="a" * 64, sem="s" * 64, shot="p" * 64,
             totals=None):
        return {"frame": frame, "request_sha256": req_sha,
                "request_semantic_sha256": sem, "screenshot_sha256": shot,
                "expected_totals": dict(self.TOTALS) if totals is None else totals}

    def test_assemble_requires_seven_ordered(self):
        with self.assertRaises(rm.ManifestError):
            rm.assemble_run_manifest("r", "U", "en-austin-1", "light-v1",
                                     (1320, 2868), [self._rec("track-running")])

    def test_identical_runs_have_no_errors(self):
        recs = [self._rec(f) for f in rs.PILOT_FRAMES]
        m1 = rm.assemble_run_manifest("r1", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs)
        m2 = rm.assemble_run_manifest("r2", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), [dict(r) for r in recs])
        res = rm.compare_runs(m1, m2)
        self.assertEqual(res, {"errors": [], "unreviewed_variance": []})

    def test_png_drift_is_variance_totals_drift_is_error(self):
        recs = [self._rec(f) for f in rs.PILOT_FRAMES]
        m1 = rm.assemble_run_manifest("r1", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs)
        recs2 = [dict(r) for r in recs]
        recs2[0] = dict(recs2[0])
        recs2[0]["screenshot_sha256"] = "b" * 64  # caret/chrome drift
        m2 = rm.assemble_run_manifest("r2", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs2)
        res = rm.compare_runs(m1, m2)
        self.assertEqual(res["errors"], [])
        self.assertEqual(res["unreviewed_variance"], ["track-running"])
        recs3 = [dict(r) for r in recs]
        recs3[1] = dict(recs3[1])
        recs3[1]["expected_totals"] = dict(self.TOTALS, week_seconds=2)
        m3 = rm.assemble_run_manifest("r3", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs3)
        res3 = rm.compare_runs(m1, m3)
        self.assertTrue(any("insights" in e for e in res3["errors"]))


class InspectionGateTests(unittest.TestCase):
    def test_png_geometry_parse(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "f.png"
            write_png(p, 1320, 2868)
            self.assertEqual(insp.png_dimensions(str(p)), (1320, 2868))
            q = Path(tmp) / "bad.bin"
            q.write_bytes(b"not a png")
            with self.assertRaises(insp.InspectionError):
                insp.png_dimensions(str(q))

    def test_la_missing_observation_stays_needs_inspection(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "la.png"
            write_png(p, 1320, 2868)
            errs = insp.verify_la_observation(
                {"started_at": "2026-10-30T10:00:00+00:00"},
                str(p), "2026-10-30T10:12:34+00:00", None)
            self.assertTrue(errs and "missing" in errs[0])

    def test_la_valid_within_tolerance(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "la.png"
            write_png(p, 1320, 2868)
            sha = insp.sha256_file(str(p))
            errs = insp.verify_la_observation(
                {"started_at": "2026-10-30T10:00:00+00:00"},
                str(p), "2026-10-30T10:12:34+00:00",
                {"observed_elapsed_s": 754, "screenshot_sha256": sha})
            self.assertEqual(errs, [])

    def test_la_calculated_value_not_accepted_as_observed(self):
        # 754 passed while wall says 100s -> must fail, not silently pass
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "la.png"
            write_png(p, 1320, 2868)
            sha = insp.sha256_file(str(p))
            errs = insp.verify_la_observation(
                {"started_at": "2026-10-30T10:00:00+00:00"},
                str(p), "2026-10-30T10:01:40+00:00",
                {"observed_elapsed_s": 754, "screenshot_sha256": sha})
            self.assertTrue(errs)

    def test_picker_refuses_without_artifact(self):
        errs, _ = insp.verify_picker_inspection(
            {"keyboard_visible": True}, screenshot_path="/nonexistent.png",
            expected_language="en-US")
        self.assertTrue(errs)
        with tempfile.TemporaryDirectory() as tmp:
            ev = Path(tmp) / "picker-ax.txt"
            ev.write_text("keyboard visible en-US docked")
            shot = Path(tmp) / "s.png"
            write_png(shot, 1320, 2868)
            good = {"keyboard_visible": True,
                    "keyboard_language_observed": "en-US",
                    "presentation_observed": "docked",
                    "evidence_artifact": str(ev),
                    "screenshot_sha256": insp.sha256_file(str(shot))}
            errs, evidence = insp.verify_picker_inspection(
                good, screenshot_path=str(shot), expected_language="en-US")
            self.assertEqual(errs, [])
            self.assertEqual(evidence["screenshot_sha256"],
                             insp.sha256_file(str(shot)))
            self.assertTrue(evidence["artifact_sha256"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
