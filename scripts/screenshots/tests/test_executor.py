#!/usr/bin/env python3
"""Executor tests with a fake simctl backend (no device, no lease, tmp only).

The fake answers get_app_container/status_bar/ui/launch/io/terminate and
plays the app side by writing capture-state.json into the staged container.
"""

import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import executor as ex
import inspection as insp
import request_schema as rs

PINNED = {"all_seconds": 1000, "today_seconds": 100, "week_seconds": 500,
          "category_seconds": {"Work": 500}, "text_seconds": {"Gym": 100}}
LA_BLOCK = {"activity_id": "act-1", "started_at": "2026-10-30T10:00:00+00:00",
            "request_acknowledged_at": "2026-10-30T10:00:01+00:00"}


def write_png(path: Path, width: int = 1320, height: int = 2868) -> None:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                     + ihdr + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))


def base_request():
    base = json.loads((HERE / "pilot_manifest.json").read_text(encoding="utf-8"))
    return {k: v for k, v in base.items() if k not in ("frame", "mode")}


class FakeSimctl:
    """Scripted backend. App side derives ready state from staged request."""

    def __init__(self, container: Path, totals=None, la_block=None,
                 status_bar_list="", fail_launch=False, png_size=(1320, 2868),
                 app_status="ready", delete_state_on_launch=False,
                 defer_app_write=False, defer_cleanup_write=False,
                 cleanup_status="cleaned", ended_activity_ids=(),
                 removed_session=True, fail_cleanup_launch=False):
        self.container = container
        self.calls: list[list[str]] = []
        self.totals = PINNED if totals is None else totals
        self.la_block = la_block
        self.status_bar_list = status_bar_list
        self.fail_launch = fail_launch
        self.png_size = png_size
        self.app_status = app_status
        self.delete_state_on_launch = delete_state_on_launch
        self.defer_app_write = defer_app_write
        self.defer_cleanup_write = defer_cleanup_write
        self.cleanup_status = cleanup_status
        self.ended_activity_ids = ended_activity_ids
        self.removed_session = removed_session
        self.fail_cleanup_launch = fail_cleanup_launch
        # app bundle side for Mach-O provenance (host-readable)
        self.app_bundle = container.parent / "appbundle" / "TimeOfLife.app"
        self.app_bundle.mkdir(parents=True, exist_ok=True)
        (self.app_bundle / "Info.plist").write_bytes(
            b'<?xml version="1.0" encoding="UTF-8"?>'
            b'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            b'"http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
            b'<plist version="1.0"><dict>'
            b'<key>CFBundleExecutable</key><string>TimeOfLife</string>'
            b'</dict></plist>')
        (self.app_bundle / "TimeOfLife").write_bytes(b"fake-macho-bytes")

    def __call__(self, argv):
        self.calls.append(list(argv))
        verb = argv[2] if len(argv) > 2 else ""
        if verb == "get_app_container":
            if argv[-1] == "data":
                return SimpleNamespace(returncode=0, stdout=str(self.container) + "\n",
                                       stderr="")
            return SimpleNamespace(returncode=0, stdout=str(self.app_bundle) + "\n",
                                   stderr="")
        if verb == "status_bar":
            if argv[4] == "list":
                return SimpleNamespace(returncode=0, stdout=self.status_bar_list,
                                       stderr="")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if verb == "ui":
            if len(argv) == 5:
                return SimpleNamespace(returncode=0,
                                       stdout={"appearance": "dark",
                                               "content_size": "medium"}[argv[4]],
                                       stderr="")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if verb == "launch":
            if self.fail_launch:
                return SimpleNamespace(returncode=1, stdout="",
                                       stderr="launch failed")
            cleanup = {a.split("=", 1)[0]: a.split("=", 1)[1]
                       for a in argv if "=" in a and a.startswith("SCREENSHOT_CLEANUP")}
            if "SCREENSHOT_CLEANUP" in cleanup:
                return self._cleanup_launch(argv, cleanup)
            docs = self.container / "Documents"
            req_raw = (docs / "capture-request.json").read_bytes()
            digest = rs.request_sha256_of_bytes(req_raw)
            req_doc = json.loads(req_raw.decode("utf-8"))
            state: dict = {"status": self.app_status,
                           "request_sha256": digest,
                           "deck_version": req_doc.get("deck_version"),
                           "frame": req_doc.get("frame"),
                           "run_id": req_doc.get("run_id", "default"),
                           "counts": {"entries": 55},
                           "expected_totals": self.totals,
                           "build": {"configuration": "Screenshot",
                                    "bundle_id": rs.SCREENSHOT_BID}}
            if self.app_status == "failure":
                state = {"status": "failure", "request_sha256": digest,
                         "frame": req_doc.get("frame"),
                         "error": {"code": "seed_failed", "detail": "fake"}}
            if self.la_block and req_doc.get("frame") in rs.LA_FRAMES:
                state["live_activity"] = dict(self.la_block)
            if not self.defer_app_write:
                (docs / "capture-state.json").write_text(json.dumps(state),
                                                         encoding="utf-8")
            if self.delete_state_on_launch:
                (docs / "capture-state.json").unlink(missing_ok=True)
            return SimpleNamespace(returncode=0, stdout="pid: 123\n", stderr="")
        if verb == "io":
            write_png(Path(argv[-1]), *self.png_size)
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if verb == "terminate":
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        raise AssertionError(f"unexpected argv {argv}")

    def _cleanup_launch(self, argv, cleanup):
        if self.fail_cleanup_launch:
            return SimpleNamespace(returncode=1, stdout="", stderr="cleanup launch failed")
        if not self.defer_cleanup_write:
            self.write_cleanup_ack(status=self.cleanup_status)
        return SimpleNamespace(returncode=0, stdout="pid: 456\n", stderr="")

    def write_cleanup_ack(self, status="cleaned", run_id=None, sha=None,
                          ended=None, removed=None):
        """App-side ack write, verified against the staged request like the app."""
        docs = self.container / "Documents"
        req_doc = json.loads((docs / "capture-request.json").read_text(encoding="utf-8"))
        digest = rs.request_sha256_of_bytes(
            (docs / "capture-request.json").read_bytes())
        ack: dict = {"status": status,
                     "run_id": run_id or req_doc.get("run_id", "default"),
                     "request_sha256": sha or digest,
                     "ended_activity_ids": self.ended_activity_ids
                     if ended is None else ended,
                     "removed_session": self.removed_session
                     if removed is None else removed}
        if status != "cleaned":
            ack["error"] = {"code": "cleanup-fake-" + status, "detail": "fake " + status}
        (docs / "capture-cleanup.json").write_text(json.dumps(ack), encoding="utf-8")

    def verbs(self):
        return [c[2] for c in self.calls]

    def write_state_for_staged(self, status="ready", sha_override=None,
                               frame_override=None):
        """App-side write matching the currently staged request (or overrides)."""
        docs = self.container / "Documents"
        req_doc = json.loads((docs / "capture-request.json").read_text(encoding="utf-8"))
        digest = rs.request_sha256_of_bytes(
            (docs / "capture-request.json").read_bytes())
        state: dict = {"status": status,
                       "request_sha256": sha_override or digest,
                       "deck_version": req_doc.get("deck_version"),
                       "frame": frame_override or req_doc.get("frame"),
                       "counts": {"entries": 55},
                       "expected_totals": self.totals,
                       "build": {"configuration": "Screenshot",
                                "bundle_id": rs.SCREENSHOT_BID}}
        if self.la_block and state["frame"] in rs.LA_FRAMES:
            state["live_activity"] = dict(self.la_block)
        (docs / "capture-state.json").write_text(json.dumps(state), encoding="utf-8")


class PrepareFrameTests(unittest.TestCase):
    def test_happy_path_first_frame(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "r1"
            session = ex.prepare_frame(
                fake, "UDID-1", base_request(), "track-running", run_dir,
                pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            self.assertEqual(session["state_verdict"], "ready")
            self.assertEqual(session["mode"], "app-clock-pinned")
            # staged request is the ONLY file the runner copies in
            staged = (container / "Documents" / "capture-request.json").read_bytes()
            self.assertEqual(staged, Path(session["request_file"]).read_bytes())
            # order: container resolved before launch; snapshot before override
            verbs = fake.verbs()
            self.assertLess(verbs.index("get_app_container"), verbs.index("launch"))
            sb_ops = [c[4] for c in fake.calls if c[2] == "status_bar"]
            self.assertEqual(sb_ops[0], "list")
            self.assertIn("override", sb_ops)
            launch = next(c for c in fake.calls if c[2] == "launch")
            self.assertEqual(launch[-2:], ["SCREENSHOT_REQUEST", "capture-request.json"])
            self.assertIn("--terminate-running-process", launch)

    def test_live_activity_prepare_records_realtime_mode(self):
        for la_frame in ("la-lock", "la-compact", "la-expanded"):
            with tempfile.TemporaryDirectory() as tmp:
                container = Path(tmp) / "container"
                container.mkdir()
                fake = FakeSimctl(container, la_block=dict(LA_BLOCK))
                run_dir = Path(tmp) / "runs" / "r1"
                session = ex.prepare_frame(
                    fake, "UDID-1", base_request(), la_frame, run_dir,
                    pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
                self.assertEqual(session["mode"], "live-activity-realtime",
                                 la_frame)

    def test_preexisting_overrides_abort_before_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, status_bar_list="time 9:41 leftover")
            with self.assertRaises(ex.FrameError):
                ex.prepare_frame(fake, "UDID-1", base_request(), "insights",
                                 Path(tmp) / "runs" / "r1",
                                 pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            self.assertNotIn("override", [c[4] for c in fake.calls
                                          if c[2] == "status_bar"])
            self.assertNotIn("launch", fake.verbs())

    def test_app_failure_state_restores_and_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, app_status="failure")
            with self.assertRaises(ex.FrameError):
                ex.prepare_frame(fake, "UDID-1", base_request(), "history",
                                 Path(tmp) / "runs" / "r1",
                                 pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            # restore re-applied the snapshotted dark appearance
            restores = [c for c in fake.calls
                        if c[2] == "ui" and len(c) > 5 and c[4] == "appearance"]
            self.assertTrue(any(c[5] == "dark" for c in restores))

    def test_totals_drift_from_pin_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            drifted = dict(PINNED, week_seconds=1)
            fake = FakeSimctl(container, totals=drifted)
            with self.assertRaises(ex.FrameError) as ctx:
                ex.prepare_frame(fake, "UDID-1", base_request(), "insights",
                                 Path(tmp) / "runs" / "r1",
                                 pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            self.assertIn("week_seconds", str(ctx.exception))

    def test_poll_timeout_without_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, delete_state_on_launch=True)
            with self.assertRaises(ex.FrameError) as ctx:
                ex.prepare_frame(fake, "UDID-1", base_request(), "insights",
                                 Path(tmp) / "runs" / "r1",
                                 pinned_totals=dict(PINNED),
                                 timeout_s=0.0, interval_s=0.0,
                                 sleeper=ex.no_sleep)
            self.assertIn("never arrived", str(ctx.exception))


class CaptureAppFrameTests(unittest.TestCase):
    def _prepared(self, tmp: str):
        container = Path(tmp) / "container"
        container.mkdir()
        fake = FakeSimctl(container)
        run_dir = Path(tmp) / "runs" / "r1"
        ex.prepare_frame(fake, "UDID-1", base_request(), "track-running", run_dir,
                         pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
        return fake, run_dir

    def test_native_export_after_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir = self._prepared(tmp)
            record = ex.capture_app_frame(fake, "UDID-1", run_dir, "track-running")
            self.assertEqual(record["geometry"], {"width": 1320, "height": 2868})
            self.assertEqual(record["capture"], "native-simctl")
            self.assertTrue((run_dir / "frames" / "track-running.png").is_file())

    def test_live_activity_has_no_native_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir = self._prepared(tmp)
            for la_frame in ("la-lock", "la-compact", "la-expanded"):
                with self.assertRaises(ex.FrameError) as ctx:
                    ex.capture_app_frame(fake, "UDID-1", run_dir, la_frame)
                self.assertIn("record-external-frame", str(ctx.exception))

    def test_wrong_geometry_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, png_size=(100, 100))
            run_dir = Path(tmp) / "runs" / "r1"
            ex.prepare_frame(fake, "UDID-1", base_request(), "insights", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            with self.assertRaises(ex.FrameError):
                ex.capture_app_frame(fake, "UDID-1", run_dir, "insights")

    def test_matrix_geometry_export_accepted(self):
        # 13-inch iPad geometry passes executor checks; CLI approval gate
        # (not the executor) authorizes expansion vs pilot.
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, png_size=(2064, 2752))
            run_dir = Path(tmp) / "runs" / "r1"
            ex.prepare_frame(fake, "UDID-1", base_request(), "track-running",
                             run_dir, pinned_totals=dict(PINNED),
                             sleeper=ex.no_sleep)
            record = ex.capture_app_frame(fake, "UDID-1", run_dir,
                                          "track-running",
                                          expected_geometry=(2064, 2752))
            self.assertEqual(record["geometry"], {"width": 2064, "height": 2752})
            # claiming pilot geometry against iPad bytes still fails
            ex.prepare_frame(fake, "UDID-1", base_request(), "insights",
                             run_dir, pinned_totals=dict(PINNED),
                             sleeper=ex.no_sleep)
            with self.assertRaises(ex.FrameError):
                ex.capture_app_frame(fake, "UDID-1", run_dir, "insights",
                                     expected_geometry=(1320, 2868))


class RecordExternalFrameTests(unittest.TestCase):
    def _la_inputs(self, tmp: str, frame: str = "la-lock"):
        base = base_request()
        request = rs.build_frame_request(base, frame)
        raw = rs.canonical_bytes(request)
        req_path = Path(tmp) / "la.request.json"
        req_path.write_bytes(raw)
        digest = rs.request_sha256_of_bytes(raw)
        state = {"status": "ready", "request_sha256": digest,
                 "deck_version": "en-austin-1", "frame": frame,
                 "counts": {"entries": 55}, "expected_totals": dict(PINNED),
                 "build": {"configuration": "Screenshot",
                          "bundle_id": rs.SCREENSHOT_BID},
                 "live_activity": dict(LA_BLOCK)}
        sp = Path(tmp) / "la.state.json"
        sp.write_text(json.dumps(state), encoding="utf-8")
        png = Path(tmp) / "lock.png"
        write_png(png)
        sha = insp.sha256_file(str(png))
        obs = {"observed_elapsed_s": 754, "screenshot_sha256": sha}
        op = Path(tmp) / "obs.json"
        op.write_text(json.dumps(obs), encoding="utf-8")
        return request, digest, state, png, op

    def test_external_lock_screen_registered(self):
        for la_frame in ("la-lock", "la-compact", "la-expanded"):
            with tempfile.TemporaryDirectory() as tmp:
                request, digest, state, png, op = self._la_inputs(tmp, la_frame)
                run_dir = Path(tmp) / "runs" / "r1"
                record = ex.record_external_frame(
                    run_dir=run_dir, frame=la_frame, png_src=str(png),
                    captured_at_iso="2026-10-30T10:12:34+00:00",
                    observation_path=str(op), state=state, request=request,
                    request_sha256=digest, pinned_totals=dict(PINNED),
                    device_udid="UDID-1")
                self.assertEqual(record["capture"], "external-lock-screen")
                self.assertEqual(record["capture_window"]["observed_elapsed_s"], 754)
                self.assertTrue((run_dir / "frames" / f"{la_frame}.png").is_file())

    def test_wrong_frame_or_unbound_observation_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            request, digest, state, png, op = self._la_inputs(tmp)
            run_dir = Path(tmp) / "runs" / "r1"
            with self.assertRaises(ex.FrameError):
                ex.record_external_frame(
                    run_dir=run_dir, frame="insights", png_src=str(png),
                    captured_at_iso="2026-10-30T10:12:34+00:00",
                    observation_path=str(op), state=state, request=request,
                    request_sha256=digest, pinned_totals=dict(PINNED))
            bad_obs = Path(tmp) / "bad.json"
            bad_obs.write_text(json.dumps({"observed_elapsed_s": 754}),
                               encoding="utf-8")
            with self.assertRaises(ex.FrameError):
                ex.record_external_frame(
                    run_dir=run_dir, frame="la-lock", png_src=str(png),
                    captured_at_iso="2026-10-30T10:12:34+00:00",
                    observation_path=str(bad_obs), state=state, request=request,
                    request_sha256=digest, pinned_totals=dict(PINNED))


PROV = {"commit_base": "c3e5911-test", "dirty": True}


class FinalizeRunTests(unittest.TestCase):
    def _full_run(self, tmp: str, run_id: str, geometry=(1320, 2868)):
        container = Path(tmp) / f"c-{run_id}"
        container.mkdir()
        fake = FakeSimctl(container, la_block=dict(LA_BLOCK), png_size=geometry)
        run_dir = Path(tmp) / "runs" / run_id
        base = base_request()
        for frame in ("track-running", "insights", "history", "add-entry"):
            ex.prepare_frame(fake, "UDID-1", base, frame, run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            ex.capture_app_frame(fake, "UDID-1", run_dir, frame,
                                 expected_geometry=geometry)
            ex.teardown_frame(fake, "UDID-1", run_dir, frame)
        # la-* frames via external registration
        for la_frame in ("la-lock", "la-compact", "la-expanded"):
            request = rs.build_frame_request(base, la_frame)
            raw = rs.canonical_bytes(request)
            req_path = run_dir / "requests" / f"{la_frame}.capture-request.json"
            req_path.parent.mkdir(parents=True, exist_ok=True)
            req_path.write_bytes(raw)
            digest = rs.request_sha256_of_bytes(raw)
            ex.prepare_frame(fake, "UDID-1", base, la_frame, run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            state = {"status": "ready", "request_sha256": digest,
                     "deck_version": "en-austin-1", "frame": la_frame,
                     "counts": {"entries": 55}, "expected_totals": dict(PINNED),
                     "build": {"configuration": "Screenshot",
                              "bundle_id": rs.SCREENSHOT_BID},
                     "live_activity": dict(LA_BLOCK)}
            lock_png = Path(tmp) / f"{la_frame}-{run_id}.png"
            write_png(lock_png, *geometry)
            obs = {"observed_elapsed_s": 754,
                   "screenshot_sha256": insp.sha256_file(str(lock_png))}
            op = Path(tmp) / f"obs-{la_frame}-{run_id}.json"
            op.write_text(json.dumps(obs), encoding="utf-8")
            ex.record_external_frame(
                run_dir=run_dir, frame=la_frame, png_src=str(lock_png),
                captured_at_iso="2026-10-30T10:12:34+00:00",
                observation_path=str(op), state=state, request=request,
                request_sha256=digest, pinned_totals=dict(PINNED),
                expected_geometry=geometry, device_udid="UDID-1")
            fake.ended_activity_ids = ["act-1"]
            ex.teardown_frame(fake, "UDID-1", run_dir, la_frame)
        return run_dir

    def test_finalize_complete_with_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._full_run(tmp, "r1")
            manifest, pending = ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertEqual(pending, [])
            self.assertEqual(manifest["status"], "complete")
            self.assertTrue((run_dir / "run-manifest.json").is_file())
            self.assertEqual(manifest["provenance"]["repo_commit_base"],
                             "c3e5911-test")
            self.assertTrue(manifest["provenance"]["dirty"])
            self.assertIn("macho_sha256", manifest["provenance"]["app"])
            self.assertEqual(len(manifest["frames"]), 7)

    def test_finalize_without_provenance_pends(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._full_run(tmp, "r1")
            manifest, pending = ex.finalize_run(run_dir)
            self.assertEqual(manifest["status"], "needs-inspection")
            self.assertTrue(any("provenance" in p for p in pending))

    def test_finalize_ipad_geometry_complete(self):
        # 13-inch iPad run finalizes truthfully at its native size;
        # expansion authorization lives at the CLI approval gate.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._full_run(tmp, "r1", geometry=(2064, 2752))
            manifest, pending = ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertEqual(pending, [])
            self.assertEqual(manifest["status"], "complete")
            self.assertEqual(manifest["geometry"], {"width": 2064, "height": 2752})


class ReadinessPollTests(unittest.TestCase):
    """Defect 1: poll must await CURRENT sha/frame, not the first dict."""

    def test_stale_ready_then_preparing_then_matching_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, defer_app_write=True)
            run_dir = Path(tmp) / "runs" / "r1"
            # stale ready from a previous frame launch sits in Documents
            docs = container / "Documents"
            docs.mkdir(parents=True, exist_ok=True)
            docs.joinpath("capture-state.json").write_text(json.dumps({
                "status": "ready", "request_sha256": "0" * 64,
                "deck_version": "en-austin-1", "frame": "insights",
                "counts": {"entries": 55}, "expected_totals": dict(PINNED),
                "build": {"configuration": "Screenshot",
                         "bundle_id": rs.SCREENSHOT_BID}}), encoding="utf-8")
            script = iter(["preparing", "ready"])

            def staged_sleeper(_s):
                step = next(script)
                if step == "preparing":
                    fake.write_state_for_staged(status="preparing")
                else:
                    fake.write_state_for_staged(status="ready")

            session = ex.prepare_frame(
                fake, "UDID-1", base_request(), "track-running", run_dir,
                pinned_totals=dict(PINNED), timeout_s=30.0, interval_s=0.0,
                sleeper=staged_sleeper, clock=lambda: 1000.0)
            self.assertEqual(session["state_verdict"], "ready")
            self.assertEqual(session["poll_attempts"], 3)

    def test_current_failure_fails_promptly(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, app_status="failure")
            sleeps = []
            with self.assertRaises(ex.FrameError) as ctx:
                ex.prepare_frame(
                    fake, "UDID-1", base_request(), "history",
                    Path(tmp) / "runs" / "r1",
                    pinned_totals=dict(PINNED), timeout_s=120.0, interval_s=60.0,
                    sleeper=sleeps.append, clock=lambda: 1000.0)
            self.assertIn("failure", str(ctx.exception))
            self.assertEqual(sleeps, [])

    def test_timeout_uses_injected_clock_no_real_wait(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, delete_state_on_launch=True)
            now = [1000.0]
            sleeps = []

            def tick(s):
                sleeps.append(s)
                now[0] += s

            with self.assertRaises(ex.FrameError) as ctx:
                ex.prepare_frame(
                    fake, "UDID-1", base_request(), "insights",
                    Path(tmp) / "runs" / "r1",
                    pinned_totals=dict(PINNED), timeout_s=5.0, interval_s=60.0,
                    sleeper=tick, clock=lambda: now[0])
            self.assertIn("never arrived", str(ctx.exception))
            self.assertEqual(sleeps, [60.0])

    def test_unknown_status_for_current_request_fails_promptly(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, app_status="bogus")
            sleeps = []
            with self.assertRaises(ex.FrameError) as ctx:
                ex.prepare_frame(
                    fake, "UDID-1", base_request(), "insights",
                    Path(tmp) / "runs" / "r1",
                    pinned_totals=dict(PINNED), timeout_s=120.0, interval_s=60.0,
                    sleeper=sleeps.append, clock=lambda: 1000.0)
            self.assertIn("unknown status", str(ctx.exception))
            self.assertEqual(sleeps, [])


class TeardownTests(unittest.TestCase):
    """Defect 2: success path must restore chrome + terminate; teardown persists."""

    BANNED = ("locale", "keyboard", "global", "prefs", "AppleLocale",
              "AppleLanguages", "timezone", "defaults")

    def test_two_sequential_frames_with_teardown(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "r1"
            base = base_request()
            ex.prepare_frame(fake, "UDID-1", base, "track-running", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            ex.capture_app_frame(fake, "UDID-1", run_dir, "track-running")
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "track-running")
            self.assertEqual(td["status"], "complete")
            self.assertTrue(td["chrome_restored"])
            self.assertTrue(td["app_terminated"])
            self.assertEqual(td["app_cleanup"]["status"], "cleaned")
            self.assertTrue(td["app_cleanup"]["removed_session"])
            # exported evidence preserved through teardown
            self.assertTrue((run_dir / "frames" / "track-running.png").is_file())
            # second frame no longer aborts on our own override
            session2 = ex.prepare_frame(fake, "UDID-1", base, "insights", run_dir,
                                        pinned_totals=dict(PINNED),
                                        sleeper=ex.no_sleep)
            self.assertEqual(session2["state_verdict"], "ready")
            # restore used the snapshotted dark appearance, then terminated
            argv_lines = [" ".join(c) for c in fake.calls]
            self.assertTrue(any("ui UDID-1 appearance dark" in l for l in argv_lines))
            self.assertTrue(any(l.startswith("xcrun simctl terminate UDID-1")
                                for l in argv_lines))

    def test_capture_geometry_failure_restores(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, png_size=(100, 100))
            run_dir = Path(tmp) / "runs" / "r1"
            ex.prepare_frame(fake, "UDID-1", base_request(), "insights", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            n_calls = len(fake.calls)
            with self.assertRaises(ex.FrameError):
                ex.capture_app_frame(fake, "UDID-1", run_dir, "insights")
            later = [" ".join(c) for c in fake.calls[n_calls:]]
            self.assertTrue(any("appearance dark" in l for l in later))
            # no frame record on failed export
            self.assertFalse((run_dir / "frames" / "insights.json").is_file())

    def test_no_keyboard_device_preconditions_emitted(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "r1"
            base = base_request()
            ex.prepare_frame(fake, "UDID-1", base, "add-entry", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            ex.capture_app_frame(fake, "UDID-1", run_dir, "add-entry")
            ex.teardown_frame(fake, "UDID-1", run_dir, "add-entry")
            for line in (" ".join(c) for c in fake.calls):
                for banned in self.BANNED:
                    self.assertNotIn(banned, line, f"banned token in: {line}")


class CaptureRevalidationTests(unittest.TestCase):
    """Defect 3: capture must bind UDID + live state, not a stale session file."""

    def test_cross_device_capture_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "r1"
            ex.prepare_frame(fake, "UDID-A", base_request(), "track-running",
                             run_dir, pinned_totals=dict(PINNED),
                             sleeper=ex.no_sleep)
            with self.assertRaises(ex.FrameError) as ctx:
                ex.capture_app_frame(fake, "UDID-B", run_dir, "track-running")
            self.assertIn("UDID", str(ctx.exception))

    def test_view_switched_state_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "r1"
            base = base_request()
            ex.prepare_frame(fake, "UDID-1", base, "track-running", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            # app moved on: docs now hold another frame's ready state
            ex.prepare_frame(fake, "UDID-1", base, "insights", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            with self.assertRaises(ex.FrameError):
                ex.capture_app_frame(fake, "UDID-1", run_dir, "track-running")

    def test_stale_preparing_state_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "r1"
            ex.prepare_frame(fake, "UDID-1", base_request(), "history", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            docs = container / "Documents"
            docs.joinpath("capture-state.json").write_text(
                json.dumps({"status": "preparing"}), encoding="utf-8")
            with self.assertRaises(ex.FrameError):
                ex.capture_app_frame(fake, "UDID-1", run_dir, "history")


class FinalizeReverifyTests(unittest.TestCase):
    """Defect 4: finalize must rehash every PNG; missing/tampered is fatal."""

    def _run_with_teardown(self, tmp: str):
        container = Path(tmp) / "container"
        container.mkdir()
        fake = FakeSimctl(container, la_block=dict(LA_BLOCK),
                          ended_activity_ids=["act-1"])
        run_dir = Path(tmp) / "runs" / "r1"
        base = base_request()
        for frame in ("track-running", "insights", "history", "add-entry"):
            ex.prepare_frame(fake, "UDID-1", base, frame, run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            ex.capture_app_frame(fake, "UDID-1", run_dir, frame)
            ex.teardown_frame(fake, "UDID-1", run_dir, frame)
        for la_frame in ("la-lock", "la-compact", "la-expanded"):
            request = rs.build_frame_request(base, la_frame)
            raw = rs.canonical_bytes(request)
            digest = rs.request_sha256_of_bytes(raw)
            ex.prepare_frame(fake, "UDID-1", base, la_frame, run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            state = {"status": "ready", "request_sha256": digest,
                     "deck_version": "en-austin-1", "frame": la_frame,
                     "counts": {"entries": 55}, "expected_totals": dict(PINNED),
                     "build": {"configuration": "Screenshot",
                              "bundle_id": rs.SCREENSHOT_BID},
                     "live_activity": dict(LA_BLOCK)}
            lock_png = Path(tmp) / f"{la_frame}.png"
            write_png(lock_png)
            obs = {"observed_elapsed_s": 754,
                   "screenshot_sha256": insp.sha256_file(str(lock_png))}
            op = Path(tmp) / f"obs-{la_frame}.json"
            op.write_text(json.dumps(obs), encoding="utf-8")
            ex.record_external_frame(
                run_dir=run_dir, frame=la_frame, png_src=str(lock_png),
                captured_at_iso="2026-10-30T10:12:34+00:00",
                observation_path=str(op), state=state, request=request,
                request_sha256=digest, pinned_totals=dict(PINNED),
                device_udid="UDID-1")
            ex.teardown_frame(fake, "UDID-1", run_dir, la_frame)
        return run_dir

    def test_deleted_png_is_fatal_not_pending(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._run_with_teardown(tmp)
            (run_dir / "frames" / "history.png").unlink()
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir)
            self.assertIn("history", str(ctx.exception))

    def test_tampered_png_is_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._run_with_teardown(tmp)
            p = run_dir / "frames" / "insights.png"
            p.write_bytes(p.read_bytes() + b"\x00")  # same geometry, new hash
            with self.assertRaises(ex.FrameError):
                ex.finalize_run(run_dir)

    def test_stale_la_observation_is_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._run_with_teardown(tmp)
            # swap an LA render after registration: same size, new bytes
            p = run_dir / "frames" / "la-lock.png"
            p.write_bytes(p.read_bytes() + b"\x00")
            with self.assertRaises(ex.FrameError):
                ex.finalize_run(run_dir)

    def test_record_frame_id_mismatch_is_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._run_with_teardown(tmp)
            rec_path = run_dir / "frames" / "history.json"
            rec = json.loads(rec_path.read_text(encoding="utf-8"))
            rec["frame"] = "insights"
            rec_path.write_text(json.dumps(rec), encoding="utf-8")
            with self.assertRaises(ex.FrameError):
                ex.finalize_run(run_dir)

    def test_missing_teardown_blocks_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._run_with_teardown(tmp)
            (run_dir / "sessions" / "history.teardown.json").unlink()
            manifest, pending = ex.finalize_run(run_dir)
            self.assertEqual(manifest["status"], "needs-inspection")
            self.assertTrue(any("history" in p and "teardown" in p for p in pending))


class CleanupAckTests(unittest.TestCase):
    """Cleanup-hook integration: ack matching, field validation, restore."""

    def _prepared(self, tmp: str, frame="track-running", run_id="r9", **fake_kw):
        container = Path(tmp) / "container"
        container.mkdir(exist_ok=True)
        fake = FakeSimctl(container, **fake_kw)
        run_dir = Path(tmp) / "runs" / run_id
        session = ex.prepare_frame(
            fake, "UDID-1", base_request(), frame, run_dir,
            pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
        return fake, run_dir, session

    def test_teardown_complete_happy_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, _session = self._prepared(tmp)
            ex.capture_app_frame(fake, "UDID-1", run_dir, "track-running")
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "track-running")
            self.assertEqual(td["status"], "complete")
            self.assertTrue(td["chrome_restored"])
            self.assertTrue(td["app_terminated"])
            self.assertTrue(td["app_cleanup"]["removed_session"])
            # cleanup launch carried exact tokens
            cleanup_calls = [c for c in fake.calls
                             if any(a.startswith("SCREENSHOT_CLEANUP=") for a in c)]
            self.assertEqual(len(cleanup_calls), 1)
            self.assertIn("SCREENSHOT_CLEANUP=r9", cleanup_calls[0])
            sha_arg = [a for a in cleanup_calls[0]
                       if a.startswith("SCREENSHOT_CLEANUP_SHA=")]
            self.assertEqual(len(sha_arg), 1)
            # exports preserved
            self.assertTrue((run_dir / "frames" / "track-running.png").is_file())

    def test_missing_ack_times_out_with_injected_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, _s = self._prepared(tmp, defer_cleanup_write=True)
            now = [2000.0]
            sleeps = []

            def tick(s):
                sleeps.append(s)
                now[0] += s

            with self.assertRaises(ex.FrameError) as ctx:
                ex.poll_cleanup_ack(
                    fake.container / "Documents", run_id="r9",
                    request_sha="f" * 64, timeout_s=5.0, interval_s=60.0,
                    sleeper=tick, clock=lambda: now[0])
            self.assertIn("cleanup ack", str(ctx.exception))
            self.assertEqual(sleeps, [60.0])

    def test_stale_ack_ignored_then_matching_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, session = self._prepared(tmp, defer_cleanup_write=True)
            docs = fake.container / "Documents"
            docs.joinpath("capture-cleanup.json").write_text(json.dumps({
                "status": "cleaned", "run_id": "r-OLD",
                "request_sha256": "0" * 64, "ended_activity_ids": [],
                "removed_session": True}), encoding="utf-8")
            script = iter([None])

            def staged_sleeper(_s):
                next(script)
                fake.write_cleanup_ack(status="cleaned")

            td = ex.teardown_frame(fake, "UDID-1", run_dir, "track-running",
                                   sleeper=staged_sleeper,
                                   clock=lambda: 3000.0)
            self.assertEqual(td["status"], "complete")

    def test_mismatched_ack_fails_promptly_but_restores(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, _s = self._prepared(tmp, cleanup_status="mismatch")
            n_calls = len(fake.calls)
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "track-running",
                                   sleeper=ex.no_sleep, clock=lambda: 4000.0)
            self.assertEqual(td["status"], "partial")
            self.assertIn("mismatch", json.dumps(td["app_cleanup"]))
            # chrome restore + terminate still ran, exports preserved
            later = [" ".join(c) for c in fake.calls[n_calls:]]
            self.assertTrue(any("appearance dark" in l for l in later))
            self.assertTrue(any("terminate UDID-1" in l for l in later))

    def test_failed_ack_keeps_partial(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, _s = self._prepared(tmp, cleanup_status="failure")
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "track-running",
                                   sleeper=ex.no_sleep, clock=lambda: 4000.0)
            self.assertEqual(td["status"], "partial")
            self.assertEqual(td["app_cleanup"]["status"], "failure")

    def test_real_activity_id_not_ended_is_not_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeSimctl(Path(tmp) / "container", la_block=dict(LA_BLOCK),
                              ended_activity_ids=[])
            (Path(tmp) / "container").mkdir(exist_ok=True)
            run_dir = Path(tmp) / "runs" / "rla"
            ex.prepare_frame(fake, "UDID-1", base_request(), "la-lock",
                             run_dir, pinned_totals=dict(PINNED),
                             sleeper=ex.no_sleep)
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "la-lock",
                                   sleeper=ex.no_sleep, clock=lambda: 4000.0)
            self.assertEqual(td["status"], "partial")
            self.assertIn("act-1", json.dumps(td))

    def test_activity_id_ended_completes_la_teardown(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeSimctl(Path(tmp) / "container", la_block=dict(LA_BLOCK),
                              ended_activity_ids=["act-1"])
            (Path(tmp) / "container").mkdir(exist_ok=True)
            run_dir = Path(tmp) / "runs" / "rla"
            ex.prepare_frame(fake, "UDID-1", base_request(), "la-compact",
                             run_dir, pinned_totals=dict(PINNED),
                             sleeper=ex.no_sleep)
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "la-compact",
                                   sleeper=ex.no_sleep, clock=lambda: 4000.0)
            self.assertEqual(td["status"], "complete")

    def test_removed_session_false_is_not_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, _s = self._prepared(tmp, removed_session=False)
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "track-running",
                                   sleeper=ex.no_sleep, clock=lambda: 4000.0)
            self.assertEqual(td["status"], "partial")
            self.assertIn("removed_session", json.dumps(td))

    def test_cleanup_launch_failure_restores(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, _s = self._prepared(tmp, fail_cleanup_launch=True)
            n_calls = len(fake.calls)
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "track-running",
                                   sleeper=ex.no_sleep, clock=lambda: 4000.0)
            self.assertEqual(td["status"], "partial")
            later = [" ".join(c) for c in fake.calls[n_calls:]]
            self.assertTrue(any("appearance dark" in l for l in later))
            self.assertTrue(any("terminate UDID-1" in l for l in later))


class CleanupContractTests(unittest.TestCase):
    """QA-observed contract: clean-bar format, run_id binding, ended rules."""

    CLEAN_HEADER = ("Current Status Bar Overrides:\n"
                    "=============================")

    def test_clean_bar_header_allowlisted(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, status_bar_list=self.CLEAN_HEADER)
            run_dir = Path(tmp) / "runs" / "r1"
            session = ex.prepare_frame(
                fake, "UDID-1", base_request(), "track-running", run_dir,
                pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            self.assertEqual(session["state_verdict"], "ready")

    def test_header_plus_entries_aborts(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(
                container,
                status_bar_list=self.CLEAN_HEADER + "\n--time 9:41 leftover")
            with self.assertRaises(ex.FrameError):
                ex.prepare_frame(fake, "UDID-1", base_request(), "insights",
                                 Path(tmp) / "runs" / "r1",
                                 pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            self.assertNotIn("launch", fake.verbs())

    def test_base_run_id_mismatch_dir_aborts(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container)
            base = base_request()
            base["run_id"] = "some-other-run"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.prepare_frame(fake, "UDID-1", base, "history",
                                 Path(tmp) / "runs" / "r1",
                                 pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            self.assertIn("run_id", str(ctx.exception))

    def test_pinned_frame_with_ended_activities_partial(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, ended_activity_ids=["stray-1"])
            run_dir = Path(tmp) / "runs" / "r1"
            ex.prepare_frame(fake, "UDID-1", base_request(), "history", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            td = ex.teardown_frame(fake, "UDID-1", run_dir, "history",
                                   sleeper=ex.no_sleep, clock=lambda: 5000.0)
            self.assertEqual(td["status"], "partial")
            self.assertIn("stray-1", json.dumps(td))

    def test_frame_records_carry_run_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = FakeSimctl(container, la_block=dict(LA_BLOCK),
                              ended_activity_ids=["act-1"])
            run_dir = Path(tmp) / "runs" / "r7"
            base = base_request()
            ex.prepare_frame(fake, "UDID-1", base, "track-running", run_dir,
                             pinned_totals=dict(PINNED), sleeper=ex.no_sleep)
            rec = ex.capture_app_frame(fake, "UDID-1", run_dir, "track-running")
            self.assertEqual(rec["run_id"], "r7")
            request = rs.build_frame_request(base, "la-expanded")
            request["run_id"] = "r7"
            raw = rs.canonical_bytes(request)
            digest = rs.request_sha256_of_bytes(raw)
            ex.prepare_frame(fake, "UDID-1", base_request(), "la-expanded",
                             run_dir, pinned_totals=dict(PINNED),
                             sleeper=ex.no_sleep)
            state = {"status": "ready", "request_sha256": digest,
                     "deck_version": "en-austin-1", "frame": "la-expanded",
                     "run_id": "r7", "counts": {"entries": 55},
                     "expected_totals": dict(PINNED),
                     "build": {"configuration": "Screenshot",
                              "bundle_id": rs.SCREENSHOT_BID},
                     "live_activity": dict(LA_BLOCK)}
            lock_png = Path(tmp) / "lock.png"
            write_png(lock_png)
            obs = {"observed_elapsed_s": 754,
                   "screenshot_sha256": insp.sha256_file(str(lock_png))}
            op = Path(tmp) / "obs.json"
            op.write_text(json.dumps(obs), encoding="utf-8")
            rec_la = ex.record_external_frame(
                run_dir=run_dir, frame="la-expanded", png_src=str(lock_png),
                captured_at_iso="2026-10-30T10:12:34+00:00",
                observation_path=str(op), state=state, request=request,
                request_sha256=digest, pinned_totals=dict(PINNED),
                device_udid="UDID-1")
            self.assertEqual(rec_la["run_id"], "r7")


if __name__ == "__main__":
    unittest.main(verbosity=2)
