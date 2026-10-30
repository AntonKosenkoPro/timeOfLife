#!/usr/bin/env python3
"""Regression proofs for runner review findings (all must pass post-fix).

Each class reproduces a proven finding as a failing test FIRST (red),
then the module fix turns it green. No device, no simctl, tmp dirs only.
"""

import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import approval as approval_mod
import inspection as insp
import output_guard as guard
import request_schema as rs
import run_manifest as rm
import state_check as sc


def framed_request(frame="track-running", run_id="t1"):
    base = {k: v for k, v in json.loads(
        (HERE / "pilot_manifest.json").read_text(encoding="utf-8")).items()
        if k not in ("frame", "mode")}
    base["run_id"] = run_id
    return rs.build_frame_request(base, frame)


PINNED_TOTALS = {
    "all_seconds": 1000,
    "today_seconds": 100,
    "week_seconds": 500,
    "category_seconds": {"Work": 500},
    "text_seconds": {"Gym": 100},
}


def ready_state(request, digest, frame="track-running", totals=None):
    return {
        "status": "ready",
        "request_sha256": digest,
        "deck_version": "en-austin-1",
        "frame": frame,
        "counts": {"entries": 55},
        "expected_totals": dict(PINNED_TOTALS) if totals is None else totals,
        "build": {"configuration": "Screenshot",
                  "bundle_id": rs.SCREENSHOT_BID},
    }


class FramesNeverCrashTests(unittest.TestCase):
    def test_missing_frames_is_invalid_not_crash(self):
        self.assertIsInstance(rs.validate_request_dict({}), list)

    def test_none_frames_is_invalid_not_crash(self):
        bad = framed_request()
        bad["frames"] = None
        self.assertIsInstance(rs.validate_request_dict(bad), list)
        self.assertTrue(rs.validate_request_dict(bad))

    def test_arbitrary_json_never_raises(self):
        probes = [None, [], "x", 42, True, 1.5,
                  {"frames": "track-running"}, {"frames": [{"frame": 1}]},
                  {"frame": None}, {"frame": ["track-running"]},
                  {"frames": None, "frame": None, "mode": 7},
                  {"keyboard": "qwerty", "status_bar": [1]}]
        for p in probes:
            with self.subTest(probe=repr(p)[:40]):
                self.assertIsInstance(rs.validate_request_dict(p), list)


class TotalsPinTests(unittest.TestCase):
    def test_ready_without_pin_is_refused(self):
        request = framed_request()
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        verdict, errs = sc.validate_state_dict(
            ready_state(request, digest), request, digest)
        self.assertEqual(verdict, sc.FAILED)
        self.assertTrue(any("pin" in e for e in errs))

    def test_ready_with_matching_pin_passes(self):
        request = framed_request()
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        verdict, errs = sc.validate_state_dict(
            ready_state(request, digest), request, digest,
            pinned_totals=dict(PINNED_TOTALS))
        self.assertEqual((verdict, errs), (sc.OK, []))

    def test_totals_mismatch_names_keys(self):
        request = framed_request()
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        drifted = dict(PINNED_TOTALS)
        drifted["week_seconds"] = 501
        verdict, errs = sc.validate_state_dict(
            ready_state(request, digest, totals=drifted), request, digest,
            pinned_totals=dict(PINNED_TOTALS))
        self.assertEqual(verdict, sc.FAILED)
        self.assertTrue(any("week_seconds" in e for e in errs))

    def test_bool_totals_rejected(self):
        request = framed_request()
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        totals = dict(PINNED_TOTALS)
        totals["all_seconds"] = True
        verdict, _ = sc.validate_state_dict(
            ready_state(request, digest, totals=totals), request, digest,
            pinned_totals=totals)
        self.assertEqual(verdict, sc.FAILED)

    def test_nan_and_inf_totals_rejected(self):
        for bad in (float("nan"), float("inf")):
            with self.subTest(bad=bad):
                request = framed_request()
                digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
                totals = dict(PINNED_TOTALS)
                totals["today_seconds"] = bad
                verdict, _ = sc.validate_state_dict(
                    ready_state(request, digest, totals=totals), request, digest,
                    pinned_totals=dict(PINNED_TOTALS))
                self.assertEqual(verdict, sc.FAILED)


class LaBindingTests(unittest.TestCase):
    def _png(self, tmp):
        import struct
        import zlib
        p = Path(tmp) / "la.png"
        ihdr = struct.pack(">IIBBBBB", 1320, 2868, 8, 2, 0, 0, 0)
        p.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                      + ihdr + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))
        return str(p)

    def test_observation_without_sha_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = self._png(tmp)
            errs = insp.verify_la_observation(
                {"started_at": "2026-10-30T10:00:00+00:00"},
                png, "2026-10-30T10:12:34+00:00",
                {"observed_elapsed_s": 754})
            self.assertTrue(errs)

    def test_naive_timestamps_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = self._png(tmp)
            sha = insp.sha256_file(png)
            obs = {"observed_elapsed_s": 754, "screenshot_sha256": sha}
            errs = insp.verify_la_observation(
                {"started_at": "2026-10-30T10:00:00"},
                png, "2026-10-30T10:12:34+00:00", obs)
            self.assertTrue(any("naive" in e.lower() for e in errs))
            errs = insp.verify_la_observation(
                {"started_at": "2026-10-30T10:00:00+00:00"},
                png, "2026-10-30T10:12:34", obs)
            self.assertTrue(any("naive" in e.lower() for e in errs))

    def test_bool_and_nan_observed_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            png = self._png(tmp)
            sha = insp.sha256_file(png)
            for bad in (True, float("nan"), float("inf"), "754"):
                with self.subTest(bad=repr(bad)):
                    errs = insp.verify_la_observation(
                        {"started_at": "2026-10-30T10:00:00+00:00"},
                        png, "2026-10-30T10:12:34+00:00",
                        {"observed_elapsed_s": bad, "screenshot_sha256": sha})
                    self.assertTrue(errs)

    def test_canonical_la_keys(self):
        for la_frame in ("la-lock", "la-compact", "la-expanded"):
            request = framed_request(la_frame)
            digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
            st = ready_state(request, digest, frame=la_frame)
            st["live_activity"] = {
                "activity_id": "act-1",
                "started_at": "2026-10-30T10:00:00+00:00",
                "request_acknowledged_at": "2026-10-30T10:00:01+00:00",
            }
            verdict, errs = sc.validate_state_dict(
                st, request, digest, pinned_totals=dict(PINNED_TOTALS))
            self.assertEqual((verdict, errs), (sc.OK, []), la_frame)


class PickerBindingTests(unittest.TestCase):
    def test_wrong_language_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            shot = Path(tmp) / "s.png"
            shot.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32)
            ev = Path(tmp) / "ax.txt"
            ev.write_text("keyboard dump")
            rec = {"keyboard_visible": True,
                   "keyboard_language_observed": "fr-FR",
                   "presentation_observed": "docked",
                   "evidence_artifact": str(ev),
                   "screenshot_sha256": insp.sha256_file(str(shot))}
            errs, _ = insp.verify_picker_inspection(
                rec, screenshot_path=str(shot), expected_language="en-US")
            self.assertTrue(any("language" in e.lower() for e in errs))

    def test_unbound_sha_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            shot = Path(tmp) / "s.png"
            shot.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32)
            ev = Path(tmp) / "ax.txt"
            ev.write_text("keyboard dump")
            rec = {"keyboard_visible": True,
                   "keyboard_language_observed": "en-US",
                   "presentation_observed": "docked",
                   "evidence_artifact": str(ev),
                   "screenshot_sha256": "0" * 64}
            errs, _ = insp.verify_picker_inspection(
                rec, screenshot_path=str(shot), expected_language="en-US")
            self.assertTrue(errs)

    def test_empty_artifact_rejected_and_hash_returned(self):
        with tempfile.TemporaryDirectory() as tmp:
            shot = Path(tmp) / "s.png"
            shot.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32)
            ev = Path(tmp) / "ax.txt"
            ev.write_text("")
            rec = {"keyboard_visible": True,
                   "keyboard_language_observed": "en-US",
                   "presentation_observed": "docked",
                   "evidence_artifact": str(ev),
                   "screenshot_sha256": insp.sha256_file(str(shot))}
            errs, _ = insp.verify_picker_inspection(
                rec, screenshot_path=str(shot), expected_language="en-US")
            self.assertTrue(errs)


class ApprovalGuardTests(unittest.TestCase):
    def _retained(self, tmp, deck="en-austin-1", treatment="light-v1"):
        root = Path(tmp)
        (root / "frames").mkdir(exist_ok=True)
        manifest = {"schema_version": 1, "deck_version": deck,
                    "treatment": treatment, "frames": list(rs.PILOT_FRAMES)}
        (root / "pilot_manifest.json").write_bytes(
            json.dumps(manifest, sort_keys=True).encode() + b"\n")
        hashes = {}
        for frame in rs.PILOT_FRAMES:
            data = f"png-{frame}".encode()
            (root / "frames" / f"{frame}.png").write_bytes(data)
            hashes[frame] = hashlib.sha256(data).hexdigest()
        return {
            "schema_version": 1, "decision": "approved",
            "pilot_manifest_sha256": hashlib.sha256(
                (root / "pilot_manifest.json").read_bytes()).hexdigest(),
            "deck_version": deck, "treatment": treatment,
            "frame_hashes": hashes, "retained_location": tmp,
        }

    def test_repo_retained_dir_rejected(self):
        ap = {"decision": "approved", "deck_version": "en-austin-1",
              "treatment": "light-v1", "pilot_manifest_sha256": "x",
              "frame_hashes": {}, "retained_location": str(HERE.parent.parent)}
        errs = approval_mod.verify_approval(ap, str(HERE.parent.parent))
        self.assertTrue(errs)

    def test_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            link = Path(tmp) / "link"
            link.symlink_to(HERE.parent.parent, target_is_directory=True)
            ap = {"decision": "approved", "deck_version": "en-austin-1",
                  "treatment": "light-v1", "pilot_manifest_sha256": "x",
                  "frame_hashes": {}, "retained_location": str(link)}
            errs = approval_mod.verify_approval(ap, str(link))
            self.assertTrue(errs)

    def test_location_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap = self._retained(tmp)
            ap["retained_location"] = str(Path(tmp) / "elsewhere")
            errs = approval_mod.verify_approval(ap, tmp)
            self.assertTrue(any("retained_location" in e for e in errs))

    def test_manifest_content_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap = self._retained(tmp, deck="en-austin-1")
            ap["deck_version"] = "ru-moscow-1"
            errs = approval_mod.verify_approval(ap, tmp)
            self.assertTrue(errs)


class LockStrictnessTests(unittest.TestCase):
    def test_partial_run_id_release_refused(self):
        udid = f"UDID-strict-{os.getpid()}-repro"
        lp = guard.acquire_lock(udid, "run-abc")
        try:
            with self.assertRaises(guard.GuardError):
                guard.release_lock(lp, "run-a")
        finally:
            guard.release_lock(lp, "run-abc")

    def test_lock_path_is_device_global(self):
        self.assertEqual(guard.lock_path_for("UDID-9"),
                         guard.lock_path_for("UDID-9"))
        # two out-roots, same UDID -> second acquire fails (device-global)
        udid = f"UDID-glob-{os.getpid()}-repro"
        guard.acquire_lock(udid, "run-1")
        try:
            with self.assertRaises(guard.GuardError):
                guard.acquire_lock(udid, "run-2")
        finally:
            guard.release_lock(guard.lock_path_for(udid), "run-1")


class SemanticCompareTests(unittest.TestCase):
    def _rec(self, frame, req_sha="a" * 64, sem="s" * 64, shot="p" * 64):
        return {"frame": frame, "request_sha256": req_sha,
                "request_semantic_sha256": sem, "screenshot_sha256": shot,
                "expected_totals": dict(PINNED_TOTALS)}

    def test_same_semantic_different_run_id_has_no_errors(self):
        recs1 = [self._rec(f) for f in rs.PILOT_FRAMES]
        recs2 = [self._rec(f, req_sha="b" * 64) for f in rs.PILOT_FRAMES]
        m1 = rm.assemble_run_manifest("r1", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs1)
        m2 = rm.assemble_run_manifest("r2", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs2)
        res = rm.compare_runs(m1, m2)
        self.assertEqual(res["errors"], [])

    def test_png_drift_is_variance_not_error(self):
        recs1 = [self._rec(f) for f in rs.PILOT_FRAMES]
        recs2 = [self._rec(f, req_sha="b" * 64) for f in rs.PILOT_FRAMES]
        recs2[0] = dict(recs2[0])
        recs2[0]["screenshot_sha256"] = "q" * 64
        m1 = rm.assemble_run_manifest("r1", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs1)
        m2 = rm.assemble_run_manifest("r2", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs2)
        res = rm.compare_runs(m1, m2)
        self.assertEqual(res["errors"], [])
        self.assertIn("track-running", res["unreviewed_variance"])

    def test_totals_drift_is_error(self):
        recs1 = [self._rec(f) for f in rs.PILOT_FRAMES]
        recs2 = [self._rec(f, req_sha="b" * 64) for f in rs.PILOT_FRAMES]
        recs2[1] = dict(recs2[1])
        recs2[1]["expected_totals"] = dict(PINNED_TOTALS, week_seconds=9)
        m1 = rm.assemble_run_manifest("r1", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs1)
        m2 = rm.assemble_run_manifest("r2", "U", "en-austin-1", "light-v1",
                                      (1320, 2868), recs2)
        res = rm.compare_runs(m1, m2)
        self.assertTrue(any("insights" in e for e in res["errors"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
