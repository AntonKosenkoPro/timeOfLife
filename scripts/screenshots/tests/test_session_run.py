#!/usr/bin/env python3
"""Session orchestration tests (executor.run_session, tasks 4.1-4.4).

Session-aware fake simctl modeling the Swift watcher: atomic
claim-before-execute of queue commands, transcript-carrying v2 acks, one
real-time anchor per session, and extended cleanup tokens. No device, no
lease beyond the real tmpdir guard lock (unique UDID per test), tmp only.
"""

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
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import executor as ex
import inspection as insp
import output_guard as guard
import request_schema as rs
import session as sess
import session_evidence as sev
import capture as cap_mod

PINNED = {"all_seconds": 1000, "today_seconds": 100, "week_seconds": 500,
          "category_seconds": {"Work": 500}, "text_seconds": {"Gym": 100}}
LA_BLOCK = {"activity_id": "act-1", "started_at": "2026-10-30T10:00:00+00:00",
            "request_acknowledged_at": "2026-10-30T10:00:01+00:00"}
NONCE = "0123456789abcdef0123456789abcdef"


def write_png(path: Path, width: int = 1320, height: int = 2868) -> None:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                     + ihdr + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))


def base_request(run_id="sess-run-r1"):
    base = json.loads((HERE / "pilot_manifest.json").read_text(encoding="utf-8"))
    base = {k: v for k, v in base.items() if k not in ("frame", "mode")}
    base["run_id"] = run_id
    return base


class SessionFakeSimctl:
    """Fake app side speaking frozen v2 (claim-before-execute + transcript)."""

    def __init__(self, container: Path, totals=None, la_block=None,
                 status_bar_list="", fail_launch=False, png_size=(1320, 2868),
                 fail_frame_seq=None, second_anchor_at=None,
                 cleanup_status="cleaned", drift_chrome_at=None,
                 list_model=("com.apple.CoreSimulator.SimDeviceType."
                             "iPhone-18-Pro-Max"),
                 list_empty=False, list_malformed=False,
                 defer_ready=False, queue_flag="true", leave_queue=False,
                 app_status="ready", removed_session=True,
                 fail_cleanup_launch=False):
        self.container = container
        self.calls: list[list[str]] = []
        self.totals = PINNED if totals is None else totals
        self.la_block = la_block
        self.status_bar_list = status_bar_list
        self.fail_launch = fail_launch
        self.png_size = png_size
        self.fail_frame_seq = fail_frame_seq
        self.second_anchor_at = second_anchor_at
        self.cleanup_status = cleanup_status
        self.drift_chrome_at = drift_chrome_at
        self.list_model = list_model
        self.list_empty = list_empty
        self.list_malformed = list_malformed
        self.defer_ready = defer_ready
        # App terminal states for prompt-failure coverage ("ready" normal;
        # "invalid"/"failure"/unknown refuse the active command at once).
        self.app_status = app_status
        # Session-store removal proof; False keeps the ack partial.
        self.removed_session = removed_session
        self.fail_cleanup_launch = fail_cleanup_launch
        # Cleanup queue proof: "true" writes removed_session_queue:true and
        # removes the owned queue dir (mirrors Swift); "false" writes false;
        # "missing" omits the key (fixed old acks). leave_queue keeps the
        # dir despite the flag (lying-app model for the host-side check).
        self.queue_flag = queue_flag
        self.leave_queue = leave_queue
        self._seen_udids: set[str] = set()
        self.container = container
        self.calls: list[list[str]] = []
        self.totals = PINNED if totals is None else totals
        self.la_block = la_block
        self.status_bar_list = status_bar_list
        self.fail_launch = fail_launch
        self.png_size = png_size
        self.fail_frame_seq = fail_frame_seq
        self.second_anchor_at = second_anchor_at
        self.cleanup_status = cleanup_status
        self.drift_chrome_at = drift_chrome_at
        self.accepted: list[dict] = []
        self.active_nonce: str | None = None
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

    def docs(self):
        return self.container / "Documents"

    def queue_root(self):
        return self.docs() / sess.SESSIONS_DIRNAME

    def __call__(self, argv):
        self.calls.append(list(argv))
        verb = argv[2] if len(argv) > 2 else ""
        if verb != "list" and len(argv) > 3 and isinstance(argv[3], str) \
                and not argv[3].startswith("-"):
            self._seen_udids.add(argv[3])
        if verb == "list":
            if self.list_malformed:
                return SimpleNamespace(returncode=0, stdout="not json",
                                       stderr="")
            if self.list_empty:
                payload: dict = {"devices": {}}
            else:
                payload = {"devices": {
                    "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                        {"udid": u, "name": f"shot-{u[:8]}",
                         "deviceTypeIdentifier": self.list_model,
                         "state": "Booted"}
                        for u in sorted(self._seen_udids)]}}
            return SimpleNamespace(
                returncode=0, stdout=json.dumps(payload), stderr="")
        if verb == "get_app_container":
            if argv[-1] == "data":
                return SimpleNamespace(returncode=0,
                                       stdout=str(self.container) + "\n",
                                       stderr="")
            return SimpleNamespace(returncode=0,
                                   stdout=str(self.app_bundle) + "\n",
                                   stderr="")
        if verb == "status_bar":
            if argv[4] == "list":
                return SimpleNamespace(returncode=0,
                                       stdout=self.status_bar_list, stderr="")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if verb == "ui":
            if len(argv) == 5:
                # Chrome modes for session-scope tests:
                #  "snapshot-dark": first 2 reads (snapshot) see dark/medium,
                #    later reads see the applied light/large.
                #  "after-snapshot": snapshot sees light/large, later reads
                #    drift to dark/medium (per-frame check must fail).
                self._ui_reads = getattr(self, "_ui_reads", 0) + 1
                dark = ((self.drift_chrome_at == "snapshot-dark"
                         and self._ui_reads <= 2)
                        or (self.drift_chrome_at == "after-snapshot"
                            and self._ui_reads > 2))
                if dark:
                    val = {"appearance": "dark",
                           "content_size": "medium"}[argv[4]]
                else:
                    val = {"appearance": "light",
                           "content_size": "large"}[argv[4]]
                return SimpleNamespace(returncode=0, stdout=val, stderr="")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if verb == "launch":
            if self.fail_launch:
                return SimpleNamespace(returncode=1, stdout="",
                                       stderr="launch failed")
            cleanup = {a.split("=", 1)[0]: a.split("=", 1)[1]
                       for a in argv if "=" in a
                       and a.startswith("SCREENSHOT_CLEANUP")}
            # Exact token names (mirrors the Swift parser; no prefix
            # guessing: FINAL_SEQ does not share the SESSION prefix).
            session_tok = {}
            for a in argv:
                if "=" not in a:
                    continue
                k, v = a.split("=", 1)
                if k in ("SCREENSHOT_SESSION_NONCE",
                         "SCREENSHOT_SESSION_DOMAIN",
                         "SCREENSHOT_FINAL_SEQ"):
                    session_tok[k] = v
            if "SCREENSHOT_CLEANUP" in cleanup:
                if self.fail_cleanup_launch:
                    return SimpleNamespace(returncode=1, stdout="",
                                           stderr="cleanup launch failed")
                return self._cleanup_launch(cleanup, session_tok)
            raw = (self.docs() / "capture-request.json").read_bytes()
            try:
                env = json.loads(raw.decode("utf-8"))
            except ValueError:
                self._write_state({"status": "failure",
                                   "error": {"code": "invalid-json",
                                             "detail": "fake"}})
                return SimpleNamespace(returncode=0, stdout="pid: 1\n",
                                       stderr="")
            errs = sess.validate_envelope(env)
            if errs:
                self._write_state({"status": "invalid",
                                   "error": {"code": "bad-envelope",
                                             "detail": errs[0]}})
            else:
                # Fresh app process per session domain: the accepted-command
                # log starts empty at every launch (transcripts are scoped
                # by session nonce, never global across sessions).
                self.accepted = []
                self.active_nonce = env["session_nonce"]
                if not self.defer_ready:
                    self.accepted.append(sess.transcript_entry(env))
                    self._write_ready(env)
            return SimpleNamespace(returncode=0, stdout="pid: 123\n",
                                   stderr="")
        if verb == "io":
            write_png(Path(argv[-1]), *self.png_size)
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if verb == "terminate":
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        raise AssertionError(f"unexpected argv {argv}")

    def pump(self):
        """Model the Swift queue watcher: claim one command, ack it."""
        if self.active_nonce is None or self.defer_ready:
            return
        try:
            env = sess.claim_command(self.queue_root(), self.active_nonce)
        except sess.SessionError:
            return
        if env is None:
            return  # no-op re-observation of the retained record
        if self.fail_frame_seq is not None and env["seq"] == self.fail_frame_seq:
            self._write_state({
                "schema_version": 2,
                "status": "failure",
                "session_nonce": env["session_nonce"],
                "run_id": env["run_id"],
                "session_domain": env["session_domain"],
                "seq": env["seq"], "frame": env["frame"], "mode": env["mode"],
                "request_sha256": env["request_sha256"],
                "transcript": list(self.accepted),
                "error": {"code": "seed_failed", "detail": "injected"}})
            return
        self.accepted.append(sess.transcript_entry(env))
        self._write_ready(env)

    def _write_ready(self, env):
        if self.app_status != "ready":
            # Prompt terminal refusal for the active command (failure
            # carries error.code; unknown statuses surface verbatim).
            refused: dict = {
                "schema_version": 2, "status": self.app_status,
                "session_nonce": env["session_nonce"],
                "run_id": env["run_id"],
                "session_domain": env["session_domain"], "seq": env["seq"],
                "frame": env["frame"], "mode": env["mode"],
                "request_sha256": env["request_sha256"],
                "transcript": list(self.accepted),
            }
            if self.app_status == "failure":
                refused["error"] = {"code": "seed_failed",
                                    "detail": "injected"}
            self._write_state(refused)
            return
        inner = json.loads(env["request_json"])
        state = {
            "schema_version": 2, "status": "ready",
            "session_nonce": env["session_nonce"], "run_id": env["run_id"],
            "session_domain": env["session_domain"], "seq": env["seq"],
            "frame": env["frame"], "mode": env["mode"],
            "request_sha256": env["request_sha256"],
            "deck_version": inner.get("deck_version"),
            "counts": {"entries": 55},
            "expected_totals": self.totals,
            "build": {"configuration": "Screenshot",
                      "bundle_id": rs.SCREENSHOT_BID},
            "transcript": list(self.accepted),
        }
        if env["frame"] in rs.LA_FRAMES and self.la_block is not None:
            block = dict(self.la_block)
            if self.second_anchor_at == env["seq"]:
                block = dict(block, activity_id="act-2")
            state["live_activity"] = block
        self._write_state(state)

    def _write_state(self, state):
        self.docs().mkdir(parents=True, exist_ok=True)
        (self.docs() / "capture-state.json").write_text(
            json.dumps(state), encoding="utf-8")

    def _cleanup_launch(self, cleanup, session_tok):
        nonce = session_tok.get("SCREENSHOT_SESSION_NONCE")
        domain = session_tok.get("SCREENSHOT_SESSION_DOMAIN")
        try:
            final_seq = int(session_tok.get("SCREENSHOT_FINAL_SEQ", "-1"))
        except ValueError:
            final_seq = -1
        ok = (nonce == self.active_nonce
              and self.accepted
              and self.accepted[-1]["seq"] == final_seq
              and cleanup.get("SCREENSHOT_CLEANUP_SHA")
              == self.accepted[-1]["request_sha256"])
        status = self.cleanup_status if ok else "mismatch"
        # Only real-time sessions ever mint a system activity; pinned
        # cleanups must report no ended activities (the runner fails the
        # session otherwise — same rule as the real app).
        realtime = any(e.get("frame") in rs.LA_FRAMES
                       for e in self.accepted)
        ended = ([self.la_block["activity_id"]]
                 if (self.la_block and realtime) else [])
        ack: dict = {
            "schema_version": 2, "status": status,
            "run_id": cleanup.get("SCREENSHOT_CLEANUP"),
            "request_sha256": cleanup.get("SCREENSHOT_CLEANUP_SHA"),
            "session_nonce": nonce, "session_domain": domain,
            "final_seq": final_seq,
            "transcript": list(self.accepted),
            "ended_activity_ids": ended,
            "removed_session": self.removed_session,
        }
        if self.queue_flag == "true":
            ack["removed_session_queue"] = True
        elif self.queue_flag == "false":
            ack["removed_session_queue"] = False
        # "missing" omits the key: fixed old acks stay fixed.
        if status != "cleaned":
            ack["error"] = {"code": "cleanup-fake-" + status,
                            "detail": "fake " + status}
        (self.docs() / "capture-cleanup.json").write_text(
            json.dumps(ack), encoding="utf-8")
        if status == "cleaned" and not self.leave_queue:
            # Mirror Swift: identity-scoped removal of the owned queue dir
            # (consumed records, end marker) once acknowledged.
            shutil.rmtree(self.queue_root() / (nonce or ""),
                          ignore_errors=True)
        return SimpleNamespace(returncode=0, stdout="pid: 456\n", stderr="")

    def launches(self):
        return [c for c in self.calls if len(c) > 2 and c[2] == "launch"]


class _HangAppearanceFake(SessionFakeSimctl):
    """Fail one `simctl ui <udid> appearance` query with a spawn error.

    hang_at_query=1 drops the chrome-snapshot query; =2 drops the first
    export's per-frame check (the cold-run iphone63/ru-r1 mirror:
    snapshot succeeds, the seq-0 ack arrives, then the appearance query
    hangs past the runner timeout). error_kind selects the injected
    exception ("timeout" or "oserror").
    """

    def __init__(self, *args, hang_at_query=2, error_kind="timeout",
                 **kwargs):
        super().__init__(*args, **kwargs)
        self._hang_at_query = hang_at_query
        self._error_kind = error_kind
        self._appearance_queries = 0

    def __call__(self, argv):
        if len(argv) == 5 and argv[1] == "simctl" and argv[2] == "ui" \
                and argv[4] == "appearance":
            self._appearance_queries += 1
            if self._appearance_queries == self._hang_at_query:
                if self._error_kind == "timeout":
                    raise subprocess.TimeoutExpired(argv, 60)
                raise OSError("injected missing simctl")
        return super().__call__(argv)


class _HangCleanupLaunchFake(SessionFakeSimctl):
    """Hang the session-cleanup `simctl launch` spawn (run 41817895686
    ipad13-en-r2 shape): frames ack/export normally, then the cleanup
    launch exceeds the runner timeout. Extra SessionFakeSimctl kwargs
    (e.g. fail_frame_seq) pass through for combined failure coverage."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._launches_seen = 0

    def __call__(self, argv):
        if len(argv) > 2 and argv[2] == "launch":
            self._launches_seen += 1
            if self._launches_seen == 2 and any(
                    str(a).startswith("SCREENSHOT_CLEANUP=")
                    for a in argv):
                raise subprocess.TimeoutExpired(argv, 60)
        return super().__call__(argv)


class PinnedSessionTests(unittest.TestCase):
    def _run(self, tmp, **kw):
        udid = f"UDID-pin-{os.getpid()}-{len(os.listdir(tmp))}"
        container = Path(tmp) / "container"
        container.mkdir()
        fake = SessionFakeSimctl(container, **kw)
        run_dir = Path(tmp) / "runs" / "sess-run-r1"
        summary = ex.run_session(
            fake, udid, base_request(), "pinned", run_dir,
            device_key="iphone69", pinned_totals=dict(PINNED),
            geometry=(1320, 2868), session_nonce=NONCE,
            sleeper=ex.no_sleep, on_poll=fake.pump)
        return fake, run_dir, summary, udid

    def test_pinned_happy_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake, run_dir, summary, udid = self._run(tmp)
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([f["frame"] for f in summary["frames"]],
                             ["track-running", "insights", "history",
                              "add-entry"])
            # One capture launch + one cleanup launch (was: 4+4 per frame).
            self.assertEqual(len(fake.launches()), 2)
            cleanup_argv = fake.launches()[1]
            self.assertIn("SCREENSHOT_SESSION_NONCE=" + NONCE,
                          " ".join(cleanup_argv))
            self.assertIn("SCREENSHOT_FINAL_SEQ=3", " ".join(cleanup_argv))
            # Receipt gates every frame.
            receipt = json.loads(
                (run_dir / "sessions" / f"{NONCE}.receipt.json")
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "complete")
            self.assertEqual([r["seq"] for r in receipt["transcript"]],
                             [0, 1, 2, 3])
            self.assertTrue(receipt["runner_verified"]["chrome_restored"])
            self.assertTrue(receipt["runner_verified"]["process_terminated"])
            self.assertTrue(receipt["runner_verified"]["lease_released"])
            # Pinned cleanup ends no activities; queue removal is proven.
            self.assertEqual(
                receipt["app_cleanup"]["ended_activity_ids"], [])
            self.assertTrue(receipt["app_cleanup"]["removed_session"])
            self.assertTrue(
                receipt["app_cleanup"]["removed_session_queue"])
            # Provenance resolved once, recorded per frame.
            for rec in summary["frames"]:
                self.assertEqual(rec["app_provenance"]["bundle_id"],
                                 rs.SCREENSHOT_BID)
                self.assertTrue(rec["app_provenance"]["macho_sha256"])
            # Timings present, counters sane, clocks separated.
            stats = summary["stats"]
            for phase in ("resolve", "chrome", "stage", "launch", "poll",
                          "export", "cleanup"):
                self.assertIn(phase, stats["phases_ms"], phase)
            self.assertGreaterEqual(stats["counters"]["simctl_spawn"], 10)
            self.assertEqual(stats["counters"]["launch"], 1)
            blob = json.dumps(stats)
            self.assertNotIn("request_json", blob)

    def test_session_evidence_accepts_run_session_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            _fake, run_dir, summary, _udid = self._run(tmp)
            manifest = {
                "schema_version": 1, "run_id": "sess-run-r1",
                "device_udid": summary["device_udid"],
                "device_key": "iphone69", "deck_version": "en-austin-1",
                "treatment": "light-v1",
                "geometry": {"width": 1320, "height": 2868},
                "frames": summary["frames"], "status": "needs-inspection",
            }
            self.assertEqual(sev.validate_run_evidence(run_dir, manifest), [])

    def test_cancel_timeout_still_cleans_up(self):
        # Cancelled mid-poll (deadline, silent app): no export happens,
        # cleanup is still attempted, and the receipt stays partial —
        # later locales must stop on it.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-cancel-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, defer_ready=True)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="cccccccccccccccccccccccccccccccc",
                    timeout_s=0.0, interval_s=0.0, sleeper=ex.no_sleep,
                    on_poll=fake.pump)
            self.assertIn("never arrived", str(ctx.exception))
            self.assertFalse(list((run_dir / "frames").glob("*.png")))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")

    def test_contamination_on_frame_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-fail-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, fail_frame_seq=2,
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="abcdef0123456789abcdef0123456789",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("contaminated", str(ctx.exception))
            # Earlier exports preserved; receipt partial, never complete.
            self.assertTrue((run_dir / "frames" / "track-running.png")
                            .is_file())
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertTrue(receipt["failures"])

    def test_simctl_timeout_at_export_verify_is_fail_closed(self):
        # Cold-run iphone63/ru-r1 mirror: snapshot succeeds, the seq-0 ack
        # arrives, then the first export's appearance query hangs past the
        # runner timeout. Must raise FrameError (never a bare
        # TimeoutExpired) with a partial receipt naming the spawn failure;
        # cleanup/restore/lease still run, nothing is staged, and the
        # receipt never claims complete for its truncated transcript.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-hang-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = _HangAppearanceFake(container, hang_at_query=2,
                                       list_model=IPHONE63_MODEL)
            run_dir = Path(tmp) / "runs" / "iphone63-ru-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("iphone63-ru-r1"), "pinned",
                    run_dir, device_key="iphone63",
                    pinned_totals=dict(PINNED), geometry=(1206, 2622),
                    session_nonce="a6b6b9af2a38bacfb2bb70334df09eb1",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("simctl spawn failed", str(ctx.exception))
            self.assertIn("appearance", str(ctx.exception))
            self.assertIn("contaminated", str(ctx.exception))
            frames_dir = run_dir / "frames"
            self.assertFalse(frames_dir.is_dir()
                             and list(frames_dir.glob("*.png")))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertTrue(receipt["failures"])
            self.assertIn("simctl spawn failed", receipt["failures"][0])
            self.assertEqual(len(receipt["transcript"]), 1)
            self.assertTrue(receipt["runner_verified"]["chrome_restored"])
            self.assertTrue(
                receipt["runner_verified"]["process_terminated"])
            self.assertTrue(receipt["runner_verified"]["lease_released"])

    def test_simctl_oserror_at_snapshot_is_fail_closed(self):
        # Spawn failure during chrome snapshot (missing binary shape):
        # nothing is captured and the receipt stays partial with the
        # failure named and an empty transcript.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-snap-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = _HangAppearanceFake(container, hang_at_query=1,
                                       error_kind="oserror",
                                       list_model=IPHONE63_MODEL)
            run_dir = Path(tmp) / "runs" / "iphone63-ru-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("iphone63-ru-r1"), "pinned",
                    run_dir, device_key="iphone63",
                    pinned_totals=dict(PINNED), geometry=(1206, 2622),
                    session_nonce="b7c7c9ab3b49cbdbc3cc81445ea10fc2",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("simctl spawn failed", str(ctx.exception))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertTrue(receipt["failures"])
            self.assertIn("simctl spawn failed", receipt["failures"][0])
            self.assertEqual(receipt["transcript"], [])

    def test_device_key_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError):
                ex.run_session(
                    fake, "UDID-x", base_request(), "pinned", run_dir,
                    device_key="gameboy", pinned_totals=dict(PINNED),
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            with self.assertRaises(ex.FrameError):
                ex.run_session(
                    fake, "UDID-x", base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(2064, 2752),
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            with self.assertRaises(ex.FrameError):
                ex.run_session(
                    fake, "UDID-x", base_request(), "pinned", run_dir,
                    device_key="ipad13", pinned_totals=dict(PINNED),
                    geometry=(2064, 2752), island_available=True,
                    sleeper=ex.no_sleep, on_poll=fake.pump)


class RealtimeSessionTests(unittest.TestCase):
    def test_realtime_groups_one_anchor(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-rt-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, la_block=dict(LA_BLOCK))
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            summary = ex.run_session(
                fake, udid, base_request(), "realtime", run_dir,
                device_key="iphone69", pinned_totals=dict(PINNED),
                geometry=(1320, 2868),
                session_nonce="11111111111111111111111111111111",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([f["frame"] for f in summary["frames"]],
                             ["la-lock", "la-compact", "la-expanded"])
            for rec in summary["frames"]:
                self.assertEqual(rec["capture"],
                                 "external-lock-screen-pending")
                self.assertTrue(rec["pending_reason"])
                self.assertEqual(rec["session_domain"], "realtime")
            # One capture launch + one cleanup launch for all three states.
            self.assertEqual(len(fake.launches()), 2)

    def test_anchor_drift_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-adrift-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, la_block=dict(LA_BLOCK),
                                     second_anchor_at=1)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "realtime", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="22222222222222222222222222222222",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("anchor", str(ctx.exception))

    def test_ipad_realtime_lock_only_plus_probe(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-ipad-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, la_block=dict(LA_BLOCK),
                                     png_size=(2064, 2752),
                                     list_model=IPAD_MODEL)
            run_dir = Path(tmp) / "runs" / "ipad13-en-r1"
            base = base_request("ipad13-en-r1")
            summary = ex.run_session(
                fake, udid, base, "realtime", run_dir,
                device_key="ipad13", pinned_totals=dict(PINNED),
                geometry=(2064, 2752),
                session_nonce="33333333333333333333333333333333",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertEqual([f["frame"] for f in summary["frames"]],
                             ["la-lock"])
            probe = json.loads(
                (run_dir / "sessions" / "island-probe.json")
                .read_text(encoding="utf-8"))
            self.assertFalse(probe["island_available"])
            self.assertFalse((run_dir / "frames" / "la-compact.png").exists())
            manifest = {
                "schema_version": 1, "run_id": "ipad13-en-r1",
                "device_udid": udid, "device_key": "ipad13",
                "deck_version": "en-austin-1", "treatment": "light-v1",
                "geometry": {"width": 2064, "height": 2752},
                "frames": summary["frames"], "status": "needs-inspection",
            }
            self.assertEqual(sev.validate_run_evidence(
                run_dir, manifest, required_frames=["la-lock"]), [])


NONCE_P = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
NONCE_RT = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
PROV = {"commit_base": "c3e5911-test", "dirty": True}
IPAD_MODEL = ("com.apple.CoreSimulator.SimDeviceType."
              "iPad-Pro-13-inch-M5-12GB")
IPHONE_MODEL = ("com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max")
IPHONE69_MODEL = ("com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max")
IPHONE63_MODEL = ("com.apple.CoreSimulator.SimDeviceType.iPhone-17")
LIST_MODEL_FOR_KEY = {"iphone69": IPHONE69_MODEL,
                      "iphone63": IPHONE63_MODEL, "ipad13": IPAD_MODEL}


def two_domain_run(tmp: str, udid: str, run_id="sess-e2e-r1",
                   device_key="iphone69", geometry=(1320, 2868),
                   nonce_p=NONCE_P, nonce_rt=NONCE_RT, **fake_kw):
    """Pinned + realtime sessions sharing one run_dir (one device/pass)."""
    container = Path(tmp) / "container"
    container.mkdir(exist_ok=True)
    fake_kw.setdefault("list_model", LIST_MODEL_FOR_KEY[device_key])
    fake = SessionFakeSimctl(container, la_block=dict(LA_BLOCK), **fake_kw)
    run_dir = Path(tmp) / "runs" / run_id
    base = base_request(run_id)
    pinned = ex.run_session(
        fake, udid, base, "pinned", run_dir, device_key=device_key,
        pinned_totals=dict(PINNED), geometry=geometry,
        session_nonce=nonce_p, sleeper=ex.no_sleep, on_poll=fake.pump)
    realtime = ex.run_session(
        fake, udid, base, "realtime", run_dir, device_key=device_key,
        pinned_totals=dict(PINNED), geometry=geometry,
        session_nonce=nonce_rt, sleeper=ex.no_sleep, on_poll=fake.pump)
    return fake, run_dir, pinned, realtime


class SessionCleanupSpawnTests(unittest.TestCase):
    def test_cleanup_launch_timeout_keeps_receipt_and_releases_lease(self):
        # Run 41817895686 ipad13-en-r2 shape: the single no-island
        # realtime frame completes, then the cleanup `simctl launch`
        # hangs past the runner timeout. The spawn failure must be
        # recorded (never escape bare), the partial receipt and session
        # record must exist with the completed transcript, and the
        # device lease must be released so a later session can acquire
        # it. Fail-closed is preserved (fail + stop, no retry).
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-cleanup-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = _HangCleanupLaunchFake(
                container, la_block=dict(LA_BLOCK), png_size=(2064, 2752),
                list_model=IPAD_MODEL)
            run_dir = Path(tmp) / "runs" / "ipad13-en-r2"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("ipad13-en-r2"), "realtime",
                    run_dir, device_key="ipad13",
                    pinned_totals=dict(PINNED), geometry=(2064, 2752),
                    session_nonce="58486dbd8377ef462054b6cc7b50413b",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("contaminated", str(ctx.exception))
            self.assertIn("simctl spawn failed", str(ctx.exception))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertTrue(receipt["failures"])
            self.assertIn("simctl spawn failed", receipt["failures"][0])
            self.assertEqual([r["seq"] for r in receipt["transcript"]],
                             [0])
            self.assertTrue(receipt["runner_verified"]["chrome_restored"])
            self.assertTrue(
                receipt["runner_verified"]["process_terminated"])
            self.assertTrue(receipt["runner_verified"]["lease_released"])
            session_records = list((run_dir / "sessions").glob(
                "58486dbd8377ef462054b6cc7b50413b.json"))
            self.assertEqual(len(session_records), 1)
            self.assertEqual(
                json.loads(session_records[0].read_text(
                    encoding="utf-8"))["status"], "partial")
            # The completed frame evidence is preserved, not rolled back.
            self.assertTrue((run_dir / "frames" / "la-lock.json").is_file())
            # Lease released: a later session for the same device can
            # acquire it (previously leaked on this path).
            lock_path = guard.acquire_lock(udid, "ipad13-en-r2-next")
            guard.release_lock(lock_path, "ipad13-en-r2-next")

    def test_cleanup_launch_timeout_preserves_prior_failure(self):
        # Combined failure: seq-2 refuses, then the cleanup launch hangs.
        # The original frame failure stays first (it names the pair's
        # cause); the spawn failure is appended, never replacing it;
        # earlier exports are preserved with a partial receipt.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-cleanup-prior-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = _HangCleanupLaunchFake(
                container, fail_frame_seq=2, png_size=(1206, 2622),
                list_model=IPHONE63_MODEL)
            run_dir = Path(tmp) / "runs" / "iphone63-ru-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("iphone63-ru-r1"), "pinned",
                    run_dir, device_key="iphone63",
                    pinned_totals=dict(PINNED), geometry=(1206, 2622),
                    session_nonce="c9d9e0f1a2b3c4d5e6f708192a3b4c5d",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("contaminated", str(ctx.exception))
            self.assertIn("seed_failed", str(ctx.exception))
            self.assertTrue((run_dir / "frames" / "track-running.png")
                            .is_file())
            self.assertTrue((run_dir / "frames" / "insights.png").is_file())
            self.assertFalse((run_dir / "frames" / "history.png").exists())
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertEqual([r["seq"] for r in receipt["transcript"]],
                             [0, 1, 2])
            self.assertIn("seed_failed", receipt["failures"][0])
            self.assertIn("simctl spawn failed", receipt["failures"][1])
            self.assertTrue(receipt["runner_verified"]["lease_released"])


class SpawnTrailSessionTests(unittest.TestCase):
    """Per-spawn trail through run_session (diagnostics only).

    Every simctl spawn appends one bounded entry (semantic category,
    active phase, monotonic start-relative-ms/duration-ms, outcome,
    rc) including timeout/OSError events; raw argv, paths, nonces,
    launch args, and stderr never enter persisted stats. Timeouts,
    deadlines, retries, counters, and receipt failure ordering are
    unchanged — asserted alongside the trail below.
    """

    def _record_stats(self, run_dir, nonce):
        rec = json.loads(
            (run_dir / "sessions" / f"{nonce}.json")
            .read_text(encoding="utf-8"))
        return rec["stats"]

    def test_appearance_timeout_leaves_classified_trail(self):
        # iphone63/ru-r1 mirror: export verify hangs past the timeout.
        nonce = "a6b6b9af2a38bacfb2bb70334df09eb1"
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-hang-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = _HangAppearanceFake(container, hang_at_query=2,
                                       list_model=IPHONE63_MODEL)
            run_dir = Path(tmp) / "runs" / "iphone63-ru-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("iphone63-ru-r1"), "pinned",
                    run_dir, device_key="iphone63",
                    pinned_totals=dict(PINNED), geometry=(1206, 2622),
                    session_nonce=nonce,
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("simctl spawn failed", str(ctx.exception))
            self.assertIn("ui-appearance-query", str(ctx.exception))
            # Redacted failure message: no raw argv echo (paths, UDID,
            # tokens) — TimeoutExpired reprs would leak argv, so the
            # message names the category only.
            for banned in (udid, nonce, "xcrun", "SCREENSHOT"):
                self.assertNotIn(banned, str(ctx.exception))
            stats = self._record_stats(run_dir, nonce)
            trail = stats["spawn_trail"]
            hits = [e for e in trail
                    if e["category"] == "ui-appearance-query"
                    and e["outcome"] == "timeout"]
            self.assertEqual(len(hits), 1)
            hit = hits[0]
            self.assertEqual(hit["phase"], "export")
            self.assertIsNone(hit["rc"])
            self.assertGreaterEqual(hit["start_rel_ms"], 0)
            self.assertGreaterEqual(hit["duration_ms"], 0)
            self.assertEqual(
                set(hit), {"category", "phase", "start_rel_ms",
                           "duration_ms", "outcome", "rc"})
            blob = json.dumps(stats)
            for banned in ("xcrun", "SCREENSHOT", udid, nonce, "stderr"):
                self.assertNotIn(banned, blob, banned)
            # Fail-closed accounting unchanged: partial receipt naming
            # the spawn failure, truncated transcript, lease released.
            receipt = json.loads(
                list((run_dir / "sessions").glob("*.receipt.json"))[0]
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertIn("simctl spawn failed", receipt["failures"][0])
            self.assertEqual(len(receipt["transcript"]), 1)
            self.assertTrue(receipt["runner_verified"]["lease_released"])

    def test_appearance_oserror_at_snapshot_leaves_trail(self):
        nonce = "b7c7c9ab3b49cbdbc3cc81445ea10fc2"
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-snap-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = _HangAppearanceFake(container, hang_at_query=1,
                                       error_kind="oserror",
                                       list_model=IPHONE63_MODEL)
            run_dir = Path(tmp) / "runs" / "iphone63-ru-r1"
            with self.assertRaises(ex.FrameError):
                ex.run_session(
                    fake, udid, base_request("iphone63-ru-r1"), "pinned",
                    run_dir, device_key="iphone63",
                    pinned_totals=dict(PINNED), geometry=(1206, 2622),
                    session_nonce=nonce,
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            stats = self._record_stats(run_dir, nonce)
            hits = [e for e in stats["spawn_trail"]
                    if e["category"] == "ui-appearance-query"
                    and e["outcome"] == "oserror"]
            self.assertEqual(len(hits), 1)
            self.assertEqual(hits[0]["phase"], "chrome")
            receipt = json.loads(
                list((run_dir / "sessions").glob("*.receipt.json"))[0]
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["transcript"], [])

    def test_cleanup_timeout_trail_preserves_prior_failure(self):
        # Combined failure: seq-2 refuses, then cleanup launch hangs.
        # The frame failure stays first; the spawn failure is appended;
        # both are classified in the trail.
        nonce = "c9d9e0f1a2b3c4d5e6f708192a3b4c5d"
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-cleanup-prior-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = _HangCleanupLaunchFake(
                container, fail_frame_seq=2, png_size=(1206, 2622),
                list_model=IPHONE63_MODEL)
            run_dir = Path(tmp) / "runs" / "iphone63-ru-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("iphone63-ru-r1"), "pinned",
                    run_dir, device_key="iphone63",
                    pinned_totals=dict(PINNED), geometry=(1206, 2622),
                    session_nonce=nonce,
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("seed_failed", str(ctx.exception))
            stats = self._record_stats(run_dir, nonce)
            hits = [e for e in stats["spawn_trail"]
                    if e["category"] == "launch-cleanup"]
            self.assertEqual(len(hits), 1)
            self.assertEqual(hits[0]["outcome"], "timeout")
            self.assertEqual(hits[0]["phase"], "cleanup")
            self.assertIsNone(hits[0]["rc"])
            receipt = json.loads(
                list((run_dir / "sessions").glob("*.receipt.json"))[0]
                .read_text(encoding="utf-8"))
            self.assertIn("seed_failed", receipt["failures"][0])
            self.assertIn("simctl spawn failed", receipt["failures"][1])
            self.assertTrue(receipt["runner_verified"]["lease_released"])

    def test_happy_path_trail_bounded_redacted_and_consistent(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-pin-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            summary = ex.run_session(
                fake, udid, base_request(), "pinned", run_dir,
                device_key="iphone69", pinned_totals=dict(PINNED),
                geometry=(1320, 2868), session_nonce=NONCE,
                sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertEqual(summary["status"], "complete")
            stats = summary["stats"]
            trail = stats["spawn_trail"]
            # Bound honored; every spawn accounted exactly once.
            self.assertLessEqual(len(trail), sess.SPAWN_TRAIL_CAP)
            self.assertEqual(len(trail) + stats["spawn_dropped"],
                             stats["counters"]["simctl_spawn"])
            # Counter meaning unchanged.
            self.assertEqual(stats["counters"]["launch"], 1)
            # Cleanup launch classified on the happy path too.
            self.assertTrue(any(e["category"] == "launch-cleanup"
                                and e["outcome"] == "ok" for e in trail))
            for entry in trail:
                self.assertEqual(
                    set(entry), {"category", "phase", "start_rel_ms",
                                 "duration_ms", "outcome", "rc"})
                self.assertGreaterEqual(entry["duration_ms"], 0)
                self.assertGreaterEqual(entry["start_rel_ms"], 0)
            blob = json.dumps(stats)
            for banned in ("xcrun", "SCREENSHOT", udid, NONCE,
                           "request_json"):
                self.assertNotIn(banned, blob, banned)

    def test_classify_spawn_covers_known_shapes(self):
        c = ex._classify_spawn
        u = "UDID-1"
        self.assertEqual(
            c(["xcrun", "simctl", "list", "-j", "devices"]), "device-list")
        self.assertEqual(
            c(["xcrun", "simctl", "get_app_container", u, "b", "data"]),
            "get-app-container")
        self.assertEqual(
            c(["xcrun", "simctl", "status_bar", u, "list"]),
            "status-bar-list")
        self.assertEqual(
            c(["xcrun", "simctl", "ui", u, "appearance"]),
            "ui-appearance-query")
        self.assertEqual(
            c(["xcrun", "simctl", "ui", u, "content_size"]),
            "ui-content-size-query")
        self.assertEqual(
            c(["xcrun", "simctl", "ui", u, "appearance", "light"]),
            "ui-appearance-set")
        self.assertEqual(
            c(["xcrun", "simctl", "launch", "--terminate-running-process",
               u, "b"]), "launch-capture")
        self.assertEqual(
            c(["xcrun", "simctl", "launch", "--terminate-running-process",
               u, "b", "SCREENSHOT_CLEANUP=r",
               "SCREENSHOT_SESSION_NONCE=n"]), "launch-cleanup")
        self.assertEqual(
            c(["xcrun", "simctl", "io", u, "screenshot", "--type=png",
               "/tmp/a.png"]), "screenshot-export")
        self.assertEqual(
            c(["xcrun", "simctl", "terminate", u, "b"]), "terminate-app")
        self.assertEqual(c(["xcrun", "simctl", "bogus"]), "simctl-unknown")
        self.assertEqual(c([]), "simctl-unknown")

    def test_attestation_single_event_per_spawn(self):
        # Inner contract: raw run + stats records exactly one trail
        # event and one counter per simctl list spawn.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-attest-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container)
            fake(["xcrun", "simctl", "ui", udid, "appearance"])
            stats = sess.PhaseStats()
            stats.start("resolve")
            proof = ex.verify_owned_device(
                fake, udid, device_key="iphone69",
                geometry=(1320, 2868), stats=stats)
            stats.stop("resolve")
            self.assertEqual(
                proof["deviceTypeIdentifier"], IPHONE69_MODEL)
            listed = [e for e in stats.spawn_trail
                      if e["category"] == "device-list"]
            self.assertEqual(len(listed), 1)
            self.assertEqual(listed[0]["phase"], "resolve")
            self.assertEqual(listed[0]["outcome"], "ok")
            self.assertEqual(stats.counters["simctl_spawn"], 1)

    def test_session_preflight_lists_once(self):
        # Runner finding: run_session passed the counted lambda into
        # verify_owned_device while _read_device_entry counted again
        # with stats — one simctl list spawn produced 2 trail events
        # and 2 counter increments. Exactly one must remain. (The cap
        # is lifted here so the resolve-phase entry cannot roll off;
        # cap behavior itself is pinned in test_session.)
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-preflight-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with mock.patch.object(sess, "SPAWN_TRAIL_CAP", 500):
                summary = ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertEqual(summary["status"], "complete")
            trail = summary["stats"]["spawn_trail"]
            listed = [e for e in trail
                      if e["category"] == "device-list"]
            self.assertEqual(len(listed), 1)
            self.assertEqual(listed[0]["phase"], "resolve")


class _SimulatedCrash(Exception):
    """Deterministic crash-window fault (kill after a write completes)."""


class ReceiptWriterWindowTests(unittest.TestCase):
    """The interim receipt must never read complete before the writer
    finishes (probe, session record, lease release, final rewrite).

    A weak reader checks status==complete + transcript only, so an
    on-disk "complete" with lease_released:false (left by a kill in
    the window) would register as genuine completion. The interim
    write stays explicitly partial; only the final rewrite may claim
    complete. Earlier PNGs keep their receipt dependency honest, and
    the interim file keeps transcript/stats for debug on kill.
    """

    def _crash_after_first_receipt_write(self, tmp, udid, run_dir,
                                         run_id, nonce):
        from unittest import mock
        real_write = Path.write_text
        state = {"receipt_writes": 0}

        def _faulting_write(self, *args, **kwargs):
            out = real_write(self, *args, **kwargs)
            if self.name.endswith(".receipt.json"):
                state["receipt_writes"] += 1
                if state["receipt_writes"] == 1:
                    raise _SimulatedCrash(
                        "kill after interim receipt write")
            return out

        container = Path(tmp) / "container"
        container.mkdir()
        fake = SessionFakeSimctl(container)
        with mock.patch.object(Path, "write_text", _faulting_write):
            with self.assertRaises(_SimulatedCrash):
                ex.run_session(
                    fake, udid, base_request(run_id), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868), session_nonce=nonce,
                    sleeper=ex.no_sleep, on_poll=fake.pump)
        on_disk = json.loads(
            (run_dir / "sessions" / f"{nonce}.receipt.json")
            .read_text(encoding="utf-8"))
        return on_disk

    def test_crash_window_never_leaves_complete(self):
        nonce = "e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5"
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-crashwin-{os.getpid()}"
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            try:
                on_disk = self._crash_after_first_receipt_write(
                    tmp, udid, run_dir, "sess-run-r1", nonce)
            finally:
                lock = Path(tempfile.gettempdir()) / \
                    f"lifio-capture-{udid}.lock"
                try:
                    lock.unlink(missing_ok=True)
                except OSError:
                    pass
            # The killed writer left diagnostics but claimed nothing:
            # explicitly partial, lease unreleased, transcript kept.
            self.assertEqual(on_disk["status"], "partial")
            self.assertFalse(
                on_disk["runner_verified"]["lease_released"])
            self.assertEqual([r["seq"] for r in on_disk["transcript"]],
                             [0, 1, 2, 3])
            self.assertTrue(any("interim" in f for f in on_disk["failures"]),
                            on_disk["failures"])
            # A status+transcript-only reader cannot mistake this for
            # genuine completion.
            self.assertNotEqual(on_disk["status"], "complete")

    def test_clean_run_still_completes_without_interim_note(self):
        # The interim note never leaks into the final receipt, and a
        # clean run still claims complete exactly once, at the end.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-cleanfin-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            summary = ex.run_session(
                fake, udid, base_request(), "pinned", run_dir,
                device_key="iphone69", pinned_totals=dict(PINNED),
                geometry=(1320, 2868),
                session_nonce="f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertEqual(summary["status"], "complete")
            receipt = summary["receipt"]
            self.assertEqual(receipt["status"], "complete")
            self.assertEqual(receipt["failures"], [])
            self.assertTrue(receipt["runner_verified"]["lease_released"])


class SessionFinalizeGateTests(unittest.TestCase):
    def test_pending_honest_needs_inspection_not_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            manifest, pending = ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertEqual(manifest["status"], "needs-inspection")
            for la_frame in ("la-lock", "la-compact", "la-expanded"):
                self.assertTrue(any(la_frame in p for p in pending), pending)
            self.assertIn("session receipts", manifest["cleanup"])

    def test_missing_receipt_fatal_blocks_every_frame(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-m-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            (run_dir / "sessions" / f"{NONCE_P}.receipt.json").unlink()
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("blocked", str(ctx.exception))

    def test_partial_receipt_fatal_even_when_la_honest(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-p-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            rp = run_dir / "sessions" / f"{NONCE_RT}.receipt.json"
            rec = json.loads(rp.read_text(encoding="utf-8"))
            rec["status"] = "partial"
            rec["failures"] = ["injected cleanup failure"]
            rp.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
            with self.assertRaises(ex.FrameError):
                ex.finalize_run(run_dir, provenance=dict(PROV))

    def test_tampered_transcript_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-t-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            rp = run_dir / "sessions" / f"{NONCE_P}.receipt.json"
            rec = json.loads(rp.read_text(encoding="utf-8"))
            rec["transcript"] = rec["transcript"][:2]
            rp.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("transcript", str(ctx.exception))

    def test_mixed_v1_session_fatal_no_downgrade(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-x-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            # Strip session binding from one record: a v1-shaped record
            # among session outputs must fail, never finalize via v1 path.
            rec_path = run_dir / "frames" / "history.json"
            rec = json.loads(rec_path.read_text(encoding="utf-8"))
            del rec["session_nonce"]
            del rec["session_domain"]
            del rec["seq"]
            rec_path.write_text(json.dumps(rec, sort_keys=True),
                                encoding="utf-8")
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("mixed", str(ctx.exception))

    def test_forged_manifest_file_ignored_by_finalizer(self):
        # Consumer proof for the R1 bypass: a forged run-manifest.json on
        # disk (complete + invented genuine la-lock) must not influence
        # finalize_run, which rebuilds honesty from disk records.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-f-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            forged = {
                "schema_version": 1, "run_id": run_dir.name,
                "device_udid": udid, "deck_version": "en-austin-1",
                "treatment": "light-v1",
                "geometry": {"width": 1320, "height": 2868},
                "frames": [], "status": "complete", "pending_evidence": [],
            }
            (run_dir / "run-manifest.json").write_text(
                json.dumps(forged, sort_keys=True), encoding="utf-8")
            manifest, pending = ex.finalize_run(run_dir,
                                                provenance=dict(PROV))
            self.assertEqual(manifest["status"], "needs-inspection")
            self.assertTrue(any("la-lock" in p for p in pending), pending)
            self.assertEqual(
                manifest["frames"][4]["capture"],
                "external-lock-screen-pending")

    def test_tampered_receipt_queue_flag_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-q-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            rp = run_dir / "sessions" / f"{NONCE_P}.receipt.json"
            rec = json.loads(rp.read_text(encoding="utf-8"))
            del rec["app_cleanup"]["removed_session_queue"]
            rp.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
            with self.assertRaises(ex.FrameError):
                ex.finalize_run(run_dir, provenance=dict(PROV))
            rec["app_cleanup"]["removed_session_queue"] = False
            rp.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
            with self.assertRaises(ex.FrameError):
                ex.finalize_run(run_dir, provenance=dict(PROV))

    def test_v1_runs_rejected(self):
        # Task 8.5: the temporary comparison path is removed. Historical
        # per-frame runs (keyless records, per-frame teardowns, no session
        # receipts) are explicitly rejected — never finalized, never
        # downgraded. Rerun via run-session for session evidence.
        from test_legacy_removal import write_v1_run

        with tempfile.TemporaryDirectory() as tmp:
            run_dir = write_v1_run(tmp)
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("legacy", str(ctx.exception).lower())

    def test_missing_provenance_pends_needs_inspection(self):
        # Provenance is a pending gate, never fatal: finalize without it
        # still reports needs-inspection with the declared-False block.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-gate-noprov-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            manifest, pending = ex.finalize_run(run_dir)
            self.assertEqual(manifest["status"], "needs-inspection")
            self.assertTrue(
                any("provenance not declared" in p for p in pending),
                pending)
            self.assertEqual(manifest["provenance"]["declared"], False)
            self.assertTrue((run_dir / "run-manifest.json").is_file())


class PendingToGenuineE2ETests(unittest.TestCase):
    def _genuine_inputs(self, tmp: str, base: dict, frame: str, seq: int):
        request = rs.build_frame_request(dict(base), frame)
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        state = {"status": "ready", "request_sha256": digest,
                 "deck_version": "en-austin-1", "frame": frame,
                 "counts": {"entries": 55}, "expected_totals": dict(PINNED),
                 "build": {"configuration": "Screenshot",
                           "bundle_id": rs.SCREENSHOT_BID},
                 "live_activity": dict(LA_BLOCK)}
        # A new render: same native geometry, different bytes (stand-in
        # for new device pixels).
        png = Path(tmp) / f"genuine-{frame}.png"
        write_png(png)
        png.write_bytes(png.read_bytes() + b"\x00")
        sha = insp.sha256_file(str(png))
        return request, digest, state, png, sha

    def test_pending_to_genuine_full_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-e2e-{os.getpid()}"
            run_id = "sess-e2e-r1"
            fake, run_dir, pinned, realtime = two_domain_run(tmp, udid,
                                                             run_id)
            stub_shas = {r["frame"]: r["screenshot_sha256"]
                         for r in realtime["frames"]}
            receipts_before = {
                p.name: p.read_bytes()
                for p in sorted((run_dir / "sessions").glob("*.receipt.json"))
            }
            base = base_request(run_id)
            for seq, frame in enumerate(("la-lock", "la-compact",
                                         "la-expanded")):
                request, digest, state, png, sha = \
                    self._genuine_inputs(tmp, base, frame, seq)
                # Same command the session executed: no stale request.
                pending_rec = next(r for r in realtime["frames"]
                                   if r["frame"] == frame)
                self.assertEqual(digest, pending_rec["request_sha256"])
                record = ex.record_external_frame(
                    run_dir=run_dir, frame=frame, png_src=str(png),
                    captured_at_iso="2026-10-30T10:12:34+00:00",
                    state=state, request=request,
                    request_sha256=digest, pinned_totals=dict(PINNED),
                    device_udid=udid,
                    session_binding={"session_nonce": NONCE_RT,
                                     "session_domain": "realtime",
                                     "seq": seq})
                # New PNG hash, full tuple, window-only record.
                self.assertNotEqual(sha, stub_shas[frame])
                self.assertEqual(record["screenshot_sha256"], sha)
                self.assertEqual(record["capture"], "external-lock-screen")
                self.assertEqual(record["capture_window"],
                                 {"started_at": LA_BLOCK["started_at"],
                                  "captured_at_iso":
                                      "2026-10-30T10:12:34+00:00"})
                self.assertEqual(record["session_nonce"], NONCE_RT)
                self.assertEqual(record["seq"], seq)
            # Shared anchor across all three genuine states.
            for frame in ("la-lock", "la-compact", "la-expanded"):
                rec = json.loads((run_dir / "frames" / f"{frame}.json")
                                 .read_text(encoding="utf-8"))
                self.assertEqual(
                    rec["capture_window"]["started_at"],
                    LA_BLOCK["started_at"])
            # No stale receipt or record reuse: receipts byte-identical
            # (no re-cleanup needed), each record file holds the genuine
            # record alone (overwritten, never a second file).
            receipts_after = {
                p.name: p.read_bytes()
                for p in sorted((run_dir / "sessions").glob("*.receipt.json"))
            }
            self.assertEqual(receipts_before, receipts_after)
            # Full evidence now validates and finalizes complete.
            records = [json.loads(
                (run_dir / "frames" / f"{f}.json").read_text(encoding="utf-8"))
                for f in rs.PILOT_FRAMES]
            manifest_skel = {"frames": records}
            self.assertEqual(
                sev.validate_run_evidence(run_dir, manifest_skel), [])
            manifest, pending = ex.finalize_run(run_dir,
                                                provenance=dict(PROV))
            self.assertEqual(pending, [])
            self.assertEqual(manifest["status"], "complete")


def ext_args(tmp, run_id, frame, png, captured_at, state,
             geometry="1320x2868", device=None, **overrides):
    """argparse-like namespace for capture.cmd_record_external_frame."""
    import argparse

    ns = argparse.Namespace(
        out=tmp, run_id=run_id, frame=frame, png=png,
        captured_at=captured_at, state=state,
        request=None, pinned_totals=None, geometry=geometry,
        device=device, mask=None, approval=None, retained_dir=None,
        session_nonce=None, session_domain=None, seq=None, device_key=None)
    pin_path = Path(tmp) / "pin-cli.json"
    if not pin_path.is_file():
        pin_path.write_text(json.dumps(PINNED), encoding="utf-8")
    ns.pinned_totals = str(pin_path)
    for key, value in overrides.items():
        setattr(ns, key, value)
    return ns


def genuine_kit(tmp, run_dir, run_id, frame, seq, anchor=None):
    """Genuine PNG + full v2 live state for one LA frame.

    The state mirrors a real session ack: integer schema 2, full session
    identity bound to the trusted stub, and a transcript covering the
    active command. Tests mutate the written files to prove each missing
    or mismatched piece fails closed.
    """
    stub = json.loads((run_dir / "frames" / f"{frame}.json")
                      .read_text(encoding="utf-8"))
    png = Path(tmp) / f"cli-{frame}.png"
    write_png(png)
    png.write_bytes(png.read_bytes() + b"\x00")
    sha = insp.sha256_file(str(png))
    live = dict(LA_BLOCK if anchor is None else dict(LA_BLOCK,
                                                      activity_id=anchor))
    live.setdefault("request_acknowledged_at",
                    "2026-10-30T10:00:01+00:00")
    state = {"schema_version": 2, "status": "ready",
             "session_nonce": stub["session_nonce"], "run_id": run_id,
             "session_domain": stub["session_domain"], "seq": stub["seq"],
             "frame": frame, "mode": stub["mode"],
             "request_sha256": stub["request_sha256"],
             "deck_version": "en-austin-1",
             "counts": {"entries": 55}, "expected_totals": dict(PINNED),
             "build": {"configuration": "Screenshot",
                       "bundle_id": rs.SCREENSHOT_BID},
             "transcript": [{"seq": stub["seq"], "frame": frame,
                             "request_sha256": stub["request_sha256"],
                             "request_semantic_sha256":
                                 stub["request_semantic_sha256"]}],
             "live_activity": live}
    sp = Path(tmp) / f"cli-state-{frame}.json"
    sp.write_text(json.dumps(state), encoding="utf-8")
    return stub, str(png), str(sp), sha


class CliSessionGenuineTests(unittest.TestCase):
    """record-external-frame CLI wired to trusted stub bindings (no sim).

    The CLI derives nonce/domain/seq/device_key from the on-disk pending
    stub and the payload from its staged envelope; explicit session args
    must match the stub exactly. Stale/missing/foreign stubs and states
    fail closed with exit code 2.
    """

    def test_cli_derives_bindings_from_stub(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-clic-{os.getpid()}"
            run_id = "sess-cli-r1"
            _fake, run_dir, _p, realtime = two_domain_run(tmp, udid, run_id)
            anchors = set()
            for seq, frame in enumerate(("la-lock", "la-compact",
                                         "la-expanded")):
                stub, png, sp, sha = genuine_kit(
                    tmp, run_dir, run_id, frame, seq)
                rc = cap_mod.cmd_record_external_frame(
                    ext_args(tmp, run_id, frame, png,
                             "2026-10-30T10:12:34+00:00", sp,
                             device=udid))
                self.assertEqual(rc, 0)
                rec = json.loads((run_dir / "frames" / f"{frame}.json")
                                 .read_text(encoding="utf-8"))
                self.assertEqual(rec["capture"], "external-lock-screen")
                self.assertEqual(rec["screenshot_sha256"], sha)
                self.assertEqual(rec["session_nonce"], NONCE_RT)
                self.assertEqual(rec["session_domain"], "realtime")
                self.assertEqual(rec["seq"], seq)
                self.assertEqual(rec["device_key"], "iphone69")
                self.assertEqual(rec["device_udid"], udid)
                self.assertTrue(rec["state_archive"].endswith(
                    f"states/{frame}.capture-state.json"))
                anchors.add(rec["capture_window"]["started_at"])
            # All three share one anchor; receipts still cover everything.
            self.assertEqual(anchors, {LA_BLOCK["started_at"]})
            # Island frames render with --mask=black, the lock banner with
            # the simctl default (per-frame policy, recorded for audit).
            records = [json.loads(
                (run_dir / "frames" / f"{f}.json").read_text(encoding="utf-8"))
                for f in rs.PILOT_FRAMES]
            by_frame = {r["frame"]: r for r in records}
            self.assertEqual(by_frame["la-lock"]["screenshot_mask"],
                             "default")
            self.assertEqual(by_frame["la-compact"]["screenshot_mask"],
                             "black")
            self.assertEqual(by_frame["la-expanded"]["screenshot_mask"],
                             "black")
            self.assertEqual(sev.validate_run_evidence(
                run_dir, {"frames": records,
                          "geometry": {"width": 1320, "height": 2868}}), [])

    def test_cli_matching_explicit_args_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-clim-{os.getpid()}"
            run_id = "sess-cli-r2"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid, run_id)
            stub, png, sp, _sha = genuine_kit(
                tmp, run_dir, run_id, "la-lock", 0)
            rc = cap_mod.cmd_record_external_frame(ext_args(
                tmp, run_id, "la-lock", png, "2026-10-30T10:12:34+00:00",
                sp, device=udid, session_nonce=NONCE_RT,
                session_domain="realtime", seq=0, device_key="iphone69"))
            self.assertEqual(rc, 0)

    def _snapshot_run(self, run_dir, frame="la-lock"):
        paths = {"stub": run_dir / "frames" / f"{frame}.json",
                 "png": run_dir / "frames" / f"{frame}.png"}
        paths.update(
            {p.name: p for p in (run_dir / "sessions").glob("*.receipt.json")})
        return {k: p.read_bytes() for k, p in paths.items()}

    def _assert_untouched(self, run_dir, before, frame="la-lock"):
        for key, raw in before.items():
            if key == "stub":
                path = run_dir / "frames" / f"{frame}.json"
            elif key == "png":
                path = run_dir / "frames" / f"{frame}.png"
            else:
                path = run_dir / "sessions" / key
            self.assertEqual(path.read_bytes(), raw, key)

    def test_cli_mismatched_explicit_args_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-clix-{os.getpid()}"
            run_id = "sess-cli-r3"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid, run_id)
            stub, png, sp, _sha = genuine_kit(
                tmp, run_dir, run_id, "la-lock", 0)
            before = self._snapshot_run(run_dir)
            for bad in ({"session_nonce": "f" * 32},
                        {"session_domain": "pinned"},
                        {"seq": 2},
                        {"device_key": "ipad13"},
                        {"device": "UDID-OTHER"},
                        {"geometry": "1206x2622"}):
                kw = dict(device=udid)
                kw.update(bad)
                rc = cap_mod.cmd_record_external_frame(ext_args(
                    tmp, run_id, "la-lock", png,
                    "2026-10-30T10:12:34+00:00", sp, **kw))
                self.assertEqual(rc, 2, bad)
                # Stub, PNGs, and receipts untouched by rejected attempts.
                self._assert_untouched(run_dir, before)

    def test_cli_state_identity_drops_rejected(self):
        # Dropping schema or any session identity key from an otherwise
        # valid state fails closed — sha/frame alone never suffice.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-clid-{os.getpid()}"
            run_id = "sess-cli-r6"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid, run_id)
            stub, png, sp, _sha = genuine_kit(
                tmp, run_dir, run_id, "la-lock", 0)
            before = self._snapshot_run(run_dir)
            for drop in ("schema_version", "session_nonce",
                         "session_domain", "seq", "mode", "transcript"):
                state = json.loads(Path(sp).read_text(encoding="utf-8"))
                del state[drop]
                variant = Path(tmp) / f"drop-{drop}.json"
                variant.write_text(json.dumps(state), encoding="utf-8")
                rc = cap_mod.cmd_record_external_frame(ext_args(
                    tmp, run_id, "la-lock", png,
                    "2026-10-30T10:12:34+00:00", str(variant),
                    device=udid))
                self.assertEqual(rc, 2, drop)
            self._assert_untouched(run_dir, before)

    def test_cli_v1_state_with_valid_sha_frame_rejected(self):
        # The reviewer's core case: a raw v1 state whose sha AND frame
        # match the stub must still fail — the cross-session nonce is
        # excluded from the payload hash, so sha/frame prove nothing alone.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-cliv-{os.getpid()}"
            run_id = "sess-cli-r7"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid, run_id)
            stub, png, sp, _sha = genuine_kit(
                tmp, run_dir, run_id, "la-lock", 0)
            state = json.loads(Path(sp).read_text(encoding="utf-8"))
            v1 = {k: v for k, v in state.items()
                  if k not in ("schema_version", "session_nonce",
                               "session_domain", "seq", "mode", "transcript",
                               "run_id")}
            v1_path = Path(tmp) / "v1.json"
            v1_path.write_text(json.dumps(v1), encoding="utf-8")
            self.assertEqual(v1["request_sha256"], stub["request_sha256"])
            self.assertEqual(v1["frame"], "la-lock")
            rc = cap_mod.cmd_record_external_frame(ext_args(
                tmp, run_id, "la-lock", png, "2026-10-30T10:12:34+00:00",
                str(v1_path), device=udid))
            self.assertEqual(rc, 2)
            self._assert_untouched(run_dir, self._snapshot_run(run_dir))

    def test_cli_run_mode_transcript_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            # Production sessions always mint fresh nonces, so give the
            # second run its own pair: reusing a nonce+seq across runs in
            # one container is a replay by definition (tested elsewhere).
            udid = f"UDID-clirm-{os.getpid()}"
            _fake_a, run_a, _p, _r = two_domain_run(tmp, udid, "run-swap-a")
            _fake_b, run_b, _p2, _r2 = two_domain_run(
                tmp, udid, "run-swap-b", nonce_p="c" * 32, nonce_rt="d" * 32)
            env_a = (run_a / "requests" /
                     f"session-{NONCE_RT}-0-la-lock.envelope.json")
            env_b = (run_b / "requests" /
                     f"session-{'d' * 32}-0-la-lock.envelope.json")
            # Run mismatch: another run's envelope over this stub.
            saved = env_a.read_bytes()
            try:
                env_a.write_bytes(env_b.read_bytes())
                stub, png, sp, _sha = genuine_kit(
                    tmp, run_a, "run-swap-a", "la-lock", 0)
                rc = cap_mod.cmd_record_external_frame(ext_args(
                    tmp, "run-swap-a", "la-lock", png,
                    "2026-10-30T10:12:34+00:00", sp, device=udid))
                self.assertEqual(rc, 2)
                # Mode mismatch: flipped outer mode breaks envelope binding.
                env = json.loads(saved.decode("utf-8"))
                env["mode"] = "app-clock-pinned"
                env_a.write_bytes(
                    json.dumps(env, sort_keys=True).encode("utf-8") + b"\n")
                rc = cap_mod.cmd_record_external_frame(ext_args(
                    tmp, "run-swap-a", "la-lock", png,
                    "2026-10-30T10:12:34+00:00", sp, device=udid))
                self.assertEqual(rc, 2)
            finally:
                env_a.write_bytes(saved)
            # Transcript mismatch: a state whose transcript covers nothing.
            stub, png, sp, _sha = genuine_kit(
                tmp, run_a, "run-swap-a", "la-lock", 0)
            state = json.loads(Path(sp).read_text(encoding="utf-8"))
            state["transcript"] = []
            sp_bad = Path(tmp) / "bad-transcript.json"
            sp_bad.write_text(json.dumps(state), encoding="utf-8")
            rc = cap_mod.cmd_record_external_frame(ext_args(
                tmp, "run-swap-a", "la-lock", png,
                "2026-10-30T10:12:34+00:00", str(sp_bad), device=udid))
            self.assertEqual(rc, 2)

    def test_cli_explicit_args_without_stub_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            out.mkdir()
            (out / "runs" / "r9" / "frames").mkdir(parents=True)
            rc = cap_mod.cmd_record_external_frame(ext_args(
                str(out), "r9", "la-lock", "/nonexistent.png",
                "2026-10-30T10:12:34+00:00",
                "/nonexistent.json", session_nonce=NONCE_RT))
            self.assertEqual(rc, 2)

    def test_cli_foreign_state_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-clif-{os.getpid()}"
            run_id = "sess-cli-r4"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid, run_id)
            stub, png, sp, _sha = genuine_kit(
                tmp, run_dir, run_id, "la-lock", 0)
            # State copied for ANOTHER frame: foreign, rejected.
            _s2, _p2, sp_other, _h2 = genuine_kit(
                tmp, run_dir, run_id, "la-compact", 1)
            rc = cap_mod.cmd_record_external_frame(ext_args(
                tmp, run_id, "la-lock", png, "2026-10-30T10:12:34+00:00",
                sp_other, device=udid))
            self.assertEqual(rc, 2)

    def test_cli_missing_envelope_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-clie-{os.getpid()}"
            run_id = "sess-cli-r5"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid, run_id)
            stub, png, sp, _sha = genuine_kit(
                tmp, run_dir, run_id, "la-lock", 0)
            env_path = (run_dir / "requests" /
                        f"session-{NONCE_RT}-0-la-lock.envelope.json")
            env_path.unlink()
            rc = cap_mod.cmd_record_external_frame(ext_args(
                tmp, run_id, "la-lock", png, "2026-10-30T10:12:34+00:00",
                sp, device=udid))
            self.assertEqual(rc, 2)


class QueueRemovalTests(unittest.TestCase):
    """v2 cleanup must prove owned-queue removal (fail closed).

    Every v2 `cleaned` ack carries removed_session_queue:true from the
    app's identity-scoped removal; the runner copies it through, requires
    it, and additionally verifies the owned dir is actually gone. Fixed
    old acks (key missing) or false flags stay partial and block
    finalization.
    """

    def test_cleanup_flag_missing_partial(self):
        # Fixed old acks omit removed_session_queue: the session cannot
        # prove owned-queue removal, so the receipt stays partial.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-qm-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, queue_flag="missing",
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="abcdabcdabcdabcdabcdabcdabcdabcd",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("removed_session_queue", str(ctx.exception))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            receipt = json.loads(receipts[0].read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            # Copied through as null (ack lacked it) — never silently
            # upgraded, never omitted to fake presence.
            self.assertIsNot(
                receipt.get("app_cleanup", {}).get("removed_session_queue"),
                True)

    def test_cleanup_flag_false_partial(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-qf-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, queue_flag="false",
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("removed_session_queue", str(ctx.exception))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")

    def test_cleanup_dir_left_behind_partial(self):
        # The ack claims removal but the owned dir remains: the host-side
        # check catches the lie and the receipt stays partial.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-ql-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, leave_queue=True,
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="ffffffffffffffffffffffffffffffff",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("queue", str(ctx.exception).lower())
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")


class SessionMigratedFailureTests(unittest.TestCase):
    """Failure behaviors migrated from the removed v1 suite (strict v2).

    Each preserves a distinct refusal proof: prompt terminal states,
    totals drift, geometry restore, device-global silence, record
    mismatch, session-removal proof, and cleanup-launch failure. Mapped
    1:1 in the handoff report; nothing asserted here passed silently.
    """

    def test_app_terminal_status_fails_promptly(self):
        for status in ("failure", "bogus"):
            with self.subTest(status=status), \
                    tempfile.TemporaryDirectory() as tmp:
                udid = f"UDID-prompt-{os.getpid()}"
                container = Path(tmp) / "container"
                container.mkdir()
                fake = SessionFakeSimctl(container, app_status=status,
                                         list_model=IPHONE69_MODEL)
                run_dir = Path(tmp) / "runs" / "sess-run-r1"
                sleeps: list = []
                with self.assertRaises(ex.FrameError) as ctx:
                    ex.run_session(
                        fake, udid, base_request(), "pinned", run_dir,
                        device_key="iphone69", pinned_totals=dict(PINNED),
                        geometry=(1320, 2868),
                        session_nonce="b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0",
                        timeout_s=120.0, interval_s=60.0,
                        sleeper=sleeps.append, on_poll=fake.pump)
                self.assertIn(status, str(ctx.exception))
                self.assertEqual(sleeps, [])

    def test_session_totals_drift_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-drift-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            drifted = dict(PINNED, week_seconds=1)
            fake = SessionFakeSimctl(container, totals=drifted,
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("week_seconds", str(ctx.exception))

    def test_frame_record_mismatch_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-mismatch-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            hist = run_dir / "frames" / "history.json"
            ins = run_dir / "frames" / "insights.json"
            hist_bytes, ins_bytes = hist.read_bytes(), ins.read_bytes()
            hist.write_bytes(ins_bytes)
            ins.write_bytes(hist_bytes)
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("mismatch", str(ctx.exception).lower())

    def test_removed_session_false_partial(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-rmfalse-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, removed_session=False,
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("removed_session", str(ctx.exception))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")

    def test_cleanup_launch_failure_restores(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-clfail-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, fail_cleanup_launch=True,
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError):
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="e3e3e3e3e3e3e3e3e3e3e3e3e3e3e3e3",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            lines = [" ".join(c) for c in fake.calls]
            self.assertTrue(any("appearance" in l and "terminate" not in l
                                for l in lines))
            self.assertTrue(any("terminate" in l for l in lines))
            # Exports preserved through the failed cleanup.
            self.assertTrue(
                (run_dir / "frames" / "track-running.png").is_file())
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")

    def test_no_device_global_commands(self):
        banned = ("locale", "keyboard", "global", "prefs", "AppleLocale",
                  "AppleLanguages", "timezone", "defaults")
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-banned-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, la_block=dict(LA_BLOCK),
                                     list_model=IPHONE69_MODEL)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            ex.run_session(
                fake, udid, base_request(), "pinned", run_dir,
                device_key="iphone69", pinned_totals=dict(PINNED),
                geometry=(1320, 2868),
                session_nonce="f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            for line in (" ".join(c) for c in fake.calls):
                for token in banned:
                    self.assertNotIn(token, line, f"banned token in: {line}")


class ProbeAttestationTests(unittest.TestCase):
    def test_probe_queries_owned_device(self):
        import session as sess

        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-probe-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, list_model=IPAD_MODEL)
            # Prior read-only contact: the device exists and is known.
            fake(["xcrun", "simctl", "ui", udid, "appearance"])
            stats = sess.PhaseStats()
            probe = ex.probe_island_capability(
                fake, udid, device_key="ipad13", run_id="ipad13-en-r1",
                session_nonce=NONCE, geometry=(2064, 2752), stats=stats)
            self.assertFalse(probe["island_available"])
            self.assertEqual(probe["session_nonce"], NONCE)
            self.assertEqual(probe["source"], "simctl-list")
            self.assertEqual(
                probe["model"]["deviceTypeIdentifier"], IPAD_MODEL)
            argv = next(c for c in fake.calls if c[2] == "list")
            self.assertEqual(argv[:4],
                             ["xcrun", "simctl", "list", "-j"])

    def test_wrong_phone_matching_geometry_rejected(self):
        # A real but non-cataloged phone (16 Pro Max) at the cataloged
        # geometry: the model — not the geometry — decides. Never call a
        # different model "equivalent" and approved.
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-model-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(
                container,
                list_model=("com.apple.CoreSimulator.SimDeviceType."
                            "iPhone-16-Pro-Max"))
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="10101010101010101010101010101010",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("cataloged", str(ctx.exception))
            # Rejected in preflight: no capture launch happened.
            self.assertNotIn("launch", [c[2] for c in fake.calls])

    def test_unknown_phone_model_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-modelu-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(
                container,
                list_model=("com.apple.CoreSimulator.SimDeviceType."
                            "iPhone-11-Pro-Max"))
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError):
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="20202020202020202020202020202020",
                    sleeper=ex.no_sleep, on_poll=fake.pump)

    def test_iphone63_session_proves_all_keys(self):
        # All three dispatch keys verify the owned model pre-capture
        # (iphone63 shown here; iphone69/ipad13 throughout the suite).
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-63-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(
                container, png_size=(1206, 2622),
                list_model=("com.apple.CoreSimulator.SimDeviceType."
                            "iPhone-17"))
            run_dir = Path(tmp) / "runs" / "sess-63-r1"
            base = base_request("sess-63-r1")
            summary = ex.run_session(
                fake, udid, base, "pinned", run_dir,
                device_key="iphone63", pinned_totals=dict(PINNED),
                geometry=(1206, 2622),
                session_nonce="30303030303030303030303030303030",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertEqual(summary["status"], "complete")
            self.assertEqual(
                summary["frames"][0]["geometry"],
                {"width": 1206, "height": 2622})

    def test_probe_contradiction_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-probex-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            # Actual model is an iPhone but the key claims iPad: the exact
            # catalog check rejects before any island comparison.
            fake = SessionFakeSimctl(container, list_model=IPHONE_MODEL)
            fake(["xcrun", "simctl", "ui", udid, "appearance"])
            with self.assertRaises(ex.FrameError) as ctx:
                ex.probe_island_capability(
                    fake, udid, device_key="ipad13", run_id="x",
                    session_nonce=NONCE, geometry=(2064, 2752))
            self.assertIn("cataloged", str(ctx.exception))

    def test_probe_catalog_table_drift_fails_closed(self):
        # Defense in depth: if the catalog ever claims island=True for a
        # model the table attests as island-less, probing fails closed
        # rather than trusting either side alone.
        import session as sess

        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-probed-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, list_model=IPAD_MODEL)
            fake(["xcrun", "simctl", "ui", udid, "appearance"])
            real_entry = sess.DEVICE_CATALOG["ipad13"]
            patched = dict(real_entry, island=True)
            sess.DEVICE_CATALOG["ipad13"] = patched
            try:
                with self.assertRaises(ex.FrameError) as ctx:
                    ex.probe_island_capability(
                        fake, udid, device_key="ipad13", run_id="x",
                        session_nonce=NONCE, geometry=(2064, 2752))
            finally:
                sess.DEVICE_CATALOG["ipad13"] = real_entry
            self.assertIn("contradicts", str(ctx.exception))

    def test_probe_missing_device_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-probem-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, list_empty=True)
            with self.assertRaises(ex.FrameError) as ctx:
                ex.probe_island_capability(
                    fake, udid, device_key="ipad13", run_id="x",
                    session_nonce=NONCE, geometry=(2064, 2752))
            self.assertIn("absent", str(ctx.exception))

    def test_probe_malformed_listing_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-probej-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, list_malformed=True)
            with self.assertRaises(ex.FrameError):
                ex.probe_island_capability(
                    fake, udid, device_key="ipad13", run_id="x",
                    session_nonce=NONCE, geometry=(2064, 2752))

    def test_unattested_probe_contaminates_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-probeu-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, la_block=dict(LA_BLOCK),
                                     png_size=(2064, 2752),
                                     list_empty=True)
            run_dir = Path(tmp) / "runs" / "ipad13-en-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("ipad13-en-r1"), "realtime",
                    run_dir, device_key="ipad13",
                    pinned_totals=dict(PINNED), geometry=(2064, 2752),
                    session_nonce="abcdabcdabcdabcdabcdabcdabcdabcd",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("unattested", str(ctx.exception))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")
            # No silent catalog-claim probe file left behind.
            self.assertFalse(
                (run_dir / "sessions" / "island-probe.json").exists())

    def test_ipad_full_run_finalizes_with_na(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-ipadf-{os.getpid()}"
            run_id = "ipad13-en-r1"
            _fake, run_dir, _p, _r = two_domain_run(
                tmp, udid, run_id, device_key="ipad13",
                geometry=(2064, 2752), list_model=IPAD_MODEL,
                png_size=(2064, 2752))
            manifest, pending = ex.finalize_run(run_dir,
                                                provenance=dict(PROV))
            self.assertEqual(manifest["status"], "needs-inspection")
            # Only la-lock can pend; island frames are N/A, not pending.
            self.assertEqual(len(pending), 1)
            self.assertIn("la-lock", pending[0])
            self.assertEqual(manifest["na_frames"],
                             ["la-compact", "la-expanded"])
            self.assertFalse(
                manifest["island_probe"]["island_available"])
            self.assertEqual(
                manifest["island_probe"]["session_nonce"], NONCE_RT)

    def test_ipad_finalize_without_probe_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-ipadn-{os.getpid()}"
            run_id = "ipad13-en-r1"
            _fake, run_dir, _p, _r = two_domain_run(
                tmp, udid, run_id, device_key="ipad13",
                geometry=(2064, 2752), list_model=IPAD_MODEL,
                png_size=(2064, 2752))
            (run_dir / "sessions" / "island-probe.json").unlink()
            with self.assertRaises(ex.FrameError):
                ex.finalize_run(run_dir, provenance=dict(PROV))

    def test_ipad_finalize_fabricated_island_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-ipadf2-{os.getpid()}"
            run_id = "ipad13-en-r1"
            _fake, run_dir, _p, _r = two_domain_run(
                tmp, udid, run_id, device_key="ipad13",
                geometry=(2064, 2752), list_model=IPAD_MODEL,
                png_size=(2064, 2752))
            # Fabricate an island PNG beside the N/A probe.
            src = run_dir / "frames" / "la-lock.png"
            dst = run_dir / "frames" / "la-compact.png"
            dst.write_bytes(src.read_bytes())
            (run_dir / "frames" / "la-compact.json").write_text(
                json.dumps({"frame": "la-compact"}, sort_keys=True),
                encoding="utf-8")
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("fabricat", str(ctx.exception).lower())


class SessionPollAndChromeTests(unittest.TestCase):
    def test_stale_session_ack_ignored_then_matching_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container)
            docs = container / "Documents"
            docs.mkdir(parents=True, exist_ok=True)
            # Foreign ack from another session sits in Documents.
            docs.joinpath("capture-state.json").write_text(json.dumps({
                "status": "ready", "session_nonce": "f" * 32,
                "session_domain": "pinned", "seq": 9,
                "request_sha256": "0" * 64, "frame": "insights"}),
                encoding="utf-8")
            base = base_request()
            payload = rs.build_frame_request(dict(base), "track-running")
            import session as sess

            env = sess.build_envelope(
                payload, run_id="sess-run-r1", session_nonce=NONCE,
                session_domain="pinned", seq=0)
            script = iter([None])

            def staged_poll():
                next(script)
                ack = {
                    "schema_version": 2, "status": "ready",
                    "session_nonce": NONCE, "run_id": "sess-run-r1",
                    "session_domain": "pinned", "seq": 0,
                    "frame": "track-running", "mode": "app-clock-pinned",
                    "request_sha256": env["request_sha256"],
                    "transcript": [sess.transcript_entry(env)],
                }
                (docs / "capture-state.json").write_text(
                    json.dumps(ack), encoding="utf-8")

            _ = fake
            # on_poll runs before every read: stage the match only on the
            # second poll so the first iteration observably ignores the
            # foreign ack.
            calls = iter([False, True])

            def gated_poll():
                if next(calls):
                    staged_poll()

            ack, attempts = ex.poll_session_ack(
                docs, want_nonce=NONCE, want_domain="pinned", want_seq=0,
                want_sha=env["request_sha256"], want_frame="track-running",
                timeout_s=30.0, interval_s=0.0, sleeper=ex.no_sleep,
                clock=lambda: 1000.0, on_poll=gated_poll)
            self.assertEqual(ack["seq"], 0)
            self.assertEqual(attempts, 2)

    def test_session_ack_timeout_bounded_with_injected_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            docs = Path(tmp) / "docs"
            docs.mkdir()
            now = [1000.0]
            sleeps = []

            def tick(s):
                sleeps.append(s)
                now[0] += s

            with self.assertRaises(ex.FrameError) as ctx:
                ex.poll_session_ack(
                    docs, want_nonce=NONCE, want_domain="pinned", want_seq=0,
                    want_sha="a" * 64, want_frame="track-running",
                    timeout_s=5.0, interval_s=60.0, sleeper=tick,
                    clock=lambda: now[0])
            self.assertIn("never arrived", str(ctx.exception))
            self.assertEqual(sleeps, [60.0])

    def test_session_cleanup_stale_then_matching(self):
        with tempfile.TemporaryDirectory() as tmp:
            docs = Path(tmp) / "docs"
            docs.mkdir()
            docs.joinpath("capture-cleanup.json").write_text(json.dumps({
                "status": "cleaned", "run_id": "old",
                "request_sha256": "0" * 64, "session_nonce": "f" * 32,
                "session_domain": "pinned", "final_seq": 0,
                "transcript": []}), encoding="utf-8")
            script = iter([None])

            def staged_sleeper(_s):
                next(script)
                docs.joinpath("capture-cleanup.json").write_text(
                    json.dumps({
                        "status": "cleaned", "run_id": "sess-run-r1",
                        "request_sha256": "a" * 64, "session_nonce": NONCE,
                        "session_domain": "pinned", "final_seq": 3,
                        "transcript": [{"seq": i} for i in range(4)],
                        "ended_activity_ids": [],
                        "removed_session": True}), encoding="utf-8")

            ack, attempts = ex.poll_session_cleanup_ack(
                docs, run_id="sess-run-r1", request_sha="a" * 64,
                want_nonce=NONCE, want_domain="pinned", want_final_seq=3,
                timeout_s=30.0, interval_s=0.0, sleeper=staged_sleeper,
                clock=lambda: 2000.0)
            self.assertEqual(ack["final_seq"], 3)
            self.assertEqual(attempts, 2)

    def test_session_cleanup_mismatch_fails_promptly(self):
        with tempfile.TemporaryDirectory() as tmp:
            docs = Path(tmp) / "docs"
            docs.mkdir()
            docs.joinpath("capture-cleanup.json").write_text(json.dumps({
                "status": "mismatch", "run_id": "sess-run-r1",
                "request_sha256": "a" * 64, "session_nonce": NONCE,
                "session_domain": "pinned", "final_seq": 3,
                "transcript": [],
                "error": {"code": "cleanup-mismatch", "detail": "x"}}),
                encoding="utf-8")
            with self.assertRaises(ex.CleanupRefused):
                ex.poll_session_cleanup_ack(
                    docs, run_id="sess-run-r1", request_sha="a" * 64,
                    want_nonce=NONCE, want_domain="pinned", want_final_seq=3,
                    timeout_s=30.0, interval_s=0.0, sleeper=ex.no_sleep,
                    clock=lambda: 2000.0)

    def test_clean_chrome_refusal_before_launch(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-chrome-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(
                container,
                status_bar_list="time 9:41 leftover")
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="44444444444444444444444444444444",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("dirty", str(ctx.exception).lower())
            self.assertNotIn("launch", [c[2] for c in fake.calls])

    def test_chrome_restore_exact_and_drift(self):
        import session as sess

        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-restore-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, drift_chrome_at="snapshot-dark")
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            summary = ex.run_session(
                fake, udid, base_request(), "pinned", run_dir,
                device_key="iphone69", pinned_totals=dict(PINNED),
                geometry=(1320, 2868),
                session_nonce="55555555555555555555555555555555",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertEqual(summary["status"], "complete")
            lines = [" ".join(c) for c in fake.calls]
            self.assertTrue(any("ui UDID-restore" in l and
                                "appearance dark" in l for l in lines),
                            lines)
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-drift-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container,
                                     drift_chrome_at="after-snapshot")
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="66666666666666666666666666666666",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("drift", str(ctx.exception))
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(len(receipts), 1)
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")

    def test_provenance_resolved_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-prov-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            ex.run_session(
                fake, udid, base_request(), "pinned", run_dir,
                device_key="iphone69", pinned_totals=dict(PINNED),
                geometry=(1320, 2868),
                session_nonce="77777777777777777777777777777777",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            bundle_calls = [c for c in fake.calls
                            if c[2] == "get_app_container" and c[-1] != "data"]
            data_calls = [c for c in fake.calls
                          if c[2] == "get_app_container" and c[-1] == "data"]
            self.assertEqual(len(bundle_calls), 1)
            self.assertEqual(len(data_calls), 1)

    def test_geometry_mismatch_fails_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-geo-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, png_size=(100, 100))
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request(), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868),
                    session_nonce="88888888888888888888888888888888",
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("geometry", str(ctx.exception))
            # Failed export still restores chrome and terminates, and no
            # frame record is filed for the failed first export.
            lines = [" ".join(c) for c in fake.calls]
            self.assertTrue(any("appearance" in l for l in lines))
            self.assertTrue(any("terminate" in l for l in lines))
            self.assertFalse(
                (run_dir / "frames" / "track-running.json").exists())
            receipts = list((run_dir / "sessions").glob("*.receipt.json"))
            self.assertEqual(
                json.loads(receipts[0].read_text(encoding="utf-8"))["status"],
                "partial")

    def test_realtime_masks_and_ended_anchor(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-mask-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = SessionFakeSimctl(container, la_block=dict(LA_BLOCK))
            run_dir = Path(tmp) / "runs" / "sess-run-r1"
            summary = ex.run_session(
                fake, udid, base_request(), "realtime", run_dir,
                device_key="iphone69", pinned_totals=dict(PINNED),
                geometry=(1320, 2868),
                session_nonce="99999999999999999999999999999999",
                sleeper=ex.no_sleep, on_poll=fake.pump)
            masks = {r["frame"]: r["screenshot_mask"]
                     for r in summary["frames"]}
            self.assertEqual(masks, {"la-lock": "default",
                                     "la-compact": "black",
                                     "la-expanded": "black"})
            receipt = json.loads(
                (run_dir / "sessions" /
                 "99999999999999999999999999999999.receipt.json")
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["app_cleanup"]["ended_activity_ids"],
                             ["act-1"])
            self.assertTrue(receipt["app_cleanup"]["removed_session"])


class AckTranscriptTests(unittest.TestCase):
    """Cleanup acks must archive every accepted command (pure unit tests).

    The app persists its accepted transcript before queue leftovers are
    removed; the runner corroborates the ack transcript against its own
    published envelopes. Missing/empty/dropped/sha-divergent transcripts
    fail; the full transcript passes.
    """

    def _envelopes(self):
        base = base_request("ack-cov-r1")
        return [sess.build_envelope(
            rs.build_frame_request(dict(base), frame), run_id="ack-cov-r1",
            session_nonce=NONCE, session_domain="pinned", seq=i)
            for i, frame in enumerate(sess.PINNED_SESSION_FRAMES)]

    def _ack_for(self, envelopes, drop=(), sha_flip=None):
        rows = [sess.transcript_entry(e) for e in envelopes]
        rows = [r for r in rows if r["seq"] not in drop]
        if sha_flip is not None:
            rows = [dict(r, request_sha256="0" * 64)
                    if r["seq"] == sha_flip else r for r in rows]
        return {"status": "cleaned", "transcript": rows}

    def test_full_transcript_covers(self):
        envs = self._envelopes()
        self.assertEqual(ex._ack_transcript_covers(
            self._ack_for(envs), envs), [])

    def test_missing_or_empty_transcript_rejected(self):
        envs = self._envelopes()
        for ack in ({"status": "cleaned"},
                    {"status": "cleaned", "transcript": []},
                    {"status": "cleaned", "transcript": "nope"}):
            self.assertTrue(ex._ack_transcript_covers(ack, envs), ack)

    def test_dropped_row_rejected(self):
        envs = self._envelopes()
        errs = ex._ack_transcript_covers(self._ack_for(envs, drop=(2,)), envs)
        self.assertTrue(any("seq 2" in e for e in errs), errs)

    def test_divergent_sha_rejected(self):
        envs = self._envelopes()
        errs = ex._ack_transcript_covers(
            self._ack_for(envs, sha_flip=1), envs)
        self.assertTrue(any("seq 1" in e for e in errs), errs)


class CrossLocaleCellBindingTests(unittest.TestCase):
    """Producer locale binding (stdlib-only; no panels imports here).

    The consumer half of the audit finding — a complete EN run forged
    under the ru cell refused through the full matrix renderer — lives
    in the Pillow lane (panels/tests/test_matrix.py), since the CI
    tooling-tests lane is stdlib-only and importing panels pulls
    Pillow. These tests pin the producer side: envelope-derived
    unanimous manifest locale plus fail-closed finalize rejection of
    missing/tampered/divergent locale provenance.
    """

    def _complete_en_run(self, tmp: str):
        udid = f"UDID-xloc-{os.getpid()}"
        run_id = "sess-en-r1"
        fake, run_dir, pinned, realtime = two_domain_run(tmp, udid, run_id)
        gen = PendingToGenuineE2ETests()
        base = base_request(run_id)
        for seq, frame in enumerate(("la-lock", "la-compact",
                                     "la-expanded")):
            request, digest, state, png, sha = gen._genuine_inputs(
                tmp, base, frame, seq)
            pending_rec = next(r for r in realtime["frames"]
                               if r["frame"] == frame)
            self.assertEqual(digest, pending_rec["request_sha256"])
            ex.record_external_frame(
                run_dir=run_dir, frame=frame, png_src=str(png),
                captured_at_iso="2026-10-30T10:12:34+00:00",
                state=state, request=request,
                request_sha256=digest, pinned_totals=dict(PINNED),
                device_udid=udid,
                session_binding={"session_nonce": NONCE_RT,
                                 "session_domain": "realtime",
                                 "seq": seq})
        manifest, pending = ex.finalize_run(run_dir, provenance=dict(PROV))
        self.assertEqual(pending, [])
        self.assertEqual(manifest["status"], "complete")
        return run_dir

    def test_producer_binds_run_locale(self):
        # Producer integration proof: the manifest `locale` (exact
        # coordinated key) equals the unanimous locale of the
        # validated archived session envelopes — envelope-derived,
        # never a free claim. The consumer requires it to equal the
        # cell language.
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = self._complete_en_run(tmp)
            manifest = json.loads(
                (run_dir / "run-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest.get("locale"), "en")
            env_paths = sorted(
                (run_dir / "requests").glob("session-*.envelope.json"))
            self.assertTrue(env_paths)
            for path in env_paths:
                env = json.loads(path.read_text(encoding="utf-8"))
                raw = env["request_json"]
                self.assertEqual(
                    hashlib.sha256(raw.encode("utf-8")).hexdigest(),
                    env["request_sha256"])
                inner = json.loads(raw)
                self.assertEqual(inner.get("locale"), "en")
                self.assertEqual(inner.get("locale"),
                                 manifest.get("locale"))

    def test_finalize_rejects_missing_request_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-noarch-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            shutil.rmtree(run_dir / "requests")
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("locale", str(ctx.exception).lower())

    def test_finalize_rejects_tampered_envelope_bytes(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-tampenv-{os.getpid()}"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid)
            env_path = sorted(
                (run_dir / "requests").glob("session-*.envelope.json"))[0]
            env = json.loads(env_path.read_text(encoding="utf-8"))
            raw = env["request_json"]
            # Well-formed but different bytes (padding inside a string
            # value): the exact-bytes hash must reject the tamper.
            tampered = raw.replace('"Gym"', '"Gym "', 1)
            self.assertNotEqual(tampered, raw)
            self.assertNotEqual(
                hashlib.sha256(tampered.encode("utf-8")).hexdigest(),
                env["request_sha256"])
            env["request_json"] = tampered
            env_path.write_text(json.dumps(env, sort_keys=True) + "\n",
                                encoding="utf-8")
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("mismatch", str(ctx.exception).lower())

    def test_finalize_rejects_spanning_envelope_locale(self):
        # A consistent-looking transplant: one envelope's inner locale
        # plus its hash rebound to a matching record/transcript still
        # spans locales against the unanimous run locale.
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-spanloc-{os.getpid()}"
            run_id = "sess-span-r1"
            _fake, run_dir, _p, _r = two_domain_run(tmp, udid, run_id)
            env_path = sorted(
                (run_dir / "requests").glob("session-*.envelope.json"))[0]
            env = json.loads(env_path.read_text(encoding="utf-8"))
            inner = json.loads(env["request_json"])
            inner["locale"] = "ru"
            raw = json.dumps(inner, sort_keys=True, separators=(",", ":"),
                             ensure_ascii=False) + "\n"
            digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()
            env["request_json"] = raw
            env["request_sha256"] = digest
            env_path.write_text(json.dumps(env, sort_keys=True) + "\n",
                                encoding="utf-8")
            frame = env["frame"]
            rec_path = run_dir / "frames" / f"{frame}.json"
            rec = json.loads(rec_path.read_text(encoding="utf-8"))
            rec["request_sha256"] = digest
            rec_path.write_text(json.dumps(rec, sort_keys=True) + "\n",
                                encoding="utf-8")
            rp = run_dir / "sessions" / f"{NONCE_P}.receipt.json"
            receipt = json.loads(rp.read_text(encoding="utf-8"))
            for row in receipt["transcript"]:
                if row.get("frame") == frame:
                    row["request_sha256"] = digest
            rp.write_text(json.dumps(receipt, sort_keys=True) + "\n",
                          encoding="utf-8")
            with self.assertRaises(ex.FrameError) as ctx:
                ex.finalize_run(run_dir, provenance=dict(PROV))
            self.assertIn("locale", str(ctx.exception).lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
