#!/usr/bin/env python3
"""Session evidence validator tests (scripts/screenshots/session_evidence.py).

Pure validator contract for finalizer/panels (tasks 4.4/4.6):
validate_run_evidence(run_dir, manifest, required_frames=None) -> list[str].
Full identity/transcript + combined host/app receipt, paths+symlinks+N/A
probe fail closed. Pending-vs-genuine and timer tolerance preserved via the
existing executor/inspection paths (not duplicated here). No device, tmp only.
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
import request_schema as rs
import session_evidence as sev

NONCE = "0123456789abcdef0123456789abcdef"
RUN_ID = "iphone69-en-r1"
GEO = (1320, 2868)


def write_png(path: Path, width: int = 1320, height: int = 2868) -> str:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                     + ihdr + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))
    return insp.sha256_file(str(path))


def frame_record(frame, sha_png, mode, seq, extra=None):
    rec = {
        "schema_version": 1,
        "frame": frame,
        "mode": mode,
        "device_udid": "UDID-1",
        "device_key": "iphone69",
        "run_id": RUN_ID,
        "deck_version": "en-austin-1",
        "treatment": "light-v1",
        "request_sha256": "a" * 64,
        "request_semantic_sha256": "b" * 64,
        "screenshot_sha256": sha_png,
        "geometry": {"width": GEO[0], "height": GEO[1]},
        "expected_totals": {"all_seconds": 1, "today_seconds": 1,
                            "week_seconds": 1,
                            "category_seconds": {"A": 1},
                            "text_seconds": {"B": 1}},
        "capture": "native-simctl",
        "session_nonce": NONCE,
        "session_domain": "pinned" if seq < 4 else "realtime",
        "seq": seq,
    }
    if extra:
        rec.update(extra)
    return rec


def receipt(nonce=NONCE, run_id=RUN_ID, domain="pinned", final_seq=3,
            status="complete", frames=None):
    frames = frames if frames is not None else ["track-running", "insights",
                                                "history", "add-entry"]
    return {
        "schema_version": 1,
        "session_nonce": nonce,
        "run_id": run_id,
        "session_domain": domain,
        "final_seq": final_seq,
        "status": status,
        "failures": [] if status == "complete" else ["cleanup failed"],
        "transcript": [
            {"seq": i, "frame": f, "request_sha256": "a" * 64,
             "request_semantic_sha256": "b" * 64}
            for i, f in enumerate(frames)
        ],
        "app_cleanup": {"status": "cleaned", "removed_session": True,
                        "removed_session_queue": True,
                        "ended_activity_ids": []},
        "runner_verified": {"chrome_restored": True,
                            "process_terminated": True,
                            "lease_released": True},
    }


def make_run(tmp: str, frames=None, la_mode="pending"):
    """Minimal valid session run_dir + manifest for the pinned session."""
    run_dir = Path(tmp) / "runs" / RUN_ID
    (run_dir / "frames").mkdir(parents=True)
    (run_dir / "sessions").mkdir(parents=True)
    frames = frames if frames is not None else ["track-running", "insights",
                                                "history", "add-entry"]
    records = []
    for i, frame in enumerate(frames):
        sha = write_png(run_dir / "frames" / f"{frame}.png")
        rec = frame_record(frame, sha, rs.MODE_PINNED, i)
        (run_dir / "frames" / f"{frame}.json").write_text(
            json.dumps(rec, sort_keys=True), encoding="utf-8")
        records.append(rec)
    (run_dir / "sessions" / f"{NONCE}.receipt.json").write_text(
        json.dumps(receipt(), sort_keys=True), encoding="utf-8")
    manifest = {
        "schema_version": 1, "run_id": RUN_ID, "device_udid": "UDID-1",
        "device_key": "iphone69", "deck_version": "en-austin-1",
        "treatment": "light-v1",
        "geometry": {"width": GEO[0], "height": GEO[1]},
        "frames": records, "status": "needs-inspection",
    }
    (run_dir / "run-manifest.json").write_text(
        json.dumps(manifest, sort_keys=True), encoding="utf-8")
    return run_dir, manifest


class EvidenceValidatorTests(unittest.TestCase):
    def test_happy_path_pinned_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            self.assertEqual(sev.validate_run_evidence(run_dir, manifest), [])

    def test_required_frames_subset(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            self.assertEqual(sev.validate_run_evidence(
                run_dir, manifest,
                required_frames=["track-running", "insights"]), [])
            errs = sev.validate_run_evidence(run_dir, manifest,
                                             required_frames=["splash"])
            self.assertTrue(any("splash" in e for e in errs))

    def test_arbitrary_inputs_never_raise(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            for bad_manifest in (None, [], "x", {}):
                self.assertIsInstance(
                    sev.validate_run_evidence(run_dir, bad_manifest), list)
            self.assertTrue(sev.validate_run_evidence(
                Path(tmp) / "missing", manifest))
            self.assertTrue(sev.validate_run_evidence(run_dir, manifest,
                                                      required_frames="nope"))

    def test_missing_receipt_blocks_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            (run_dir / "sessions" / f"{NONCE}.receipt.json").unlink()
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("receipt" in e for e in errs))

    def test_partial_receipt_blocks_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            (run_dir / "sessions" / f"{NONCE}.receipt.json").write_text(
                json.dumps(receipt(status="partial"), sort_keys=True),
                encoding="utf-8")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("partial" in e for e in errs))

    def test_transcript_must_cover_every_frame(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            rec = receipt()
            rec["transcript"] = rec["transcript"][:2]  # history/add-entry lost
            (run_dir / "sessions" / f"{NONCE}.receipt.json").write_text(
                json.dumps(rec, sort_keys=True), encoding="utf-8")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("transcript" in e for e in errs))

    def test_identity_drift_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            rec = receipt(nonce="f" * 32)
            (run_dir / "sessions" / f"{NONCE}.receipt.json").unlink()
            (run_dir / "sessions" / ("f" * 32 + ".receipt.json")).write_text(
                json.dumps(rec, sort_keys=True), encoding="utf-8")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("nonce" in e for e in errs))
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            rec_path = run_dir / "frames" / "history.json"
            rec = json.loads(rec_path.read_text(encoding="utf-8"))
            rec["request_sha256"] = "c" * 64  # no longer transcript-bound
            rec_path.write_text(json.dumps(rec, sort_keys=True),
                                encoding="utf-8")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(errs)

    def test_tampered_or_missing_png_fatal(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            p = run_dir / "frames" / "history.png"
            p.write_bytes(p.read_bytes() + b"\x00")
            self.assertTrue(sev.validate_run_evidence(run_dir, manifest))
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            (run_dir / "frames" / "history.png").unlink()
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("history" in e for e in errs))

    def test_symlink_and_traversal_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            (run_dir / "frames" / "history.png").unlink()
            (run_dir / "frames" / "history.png").symlink_to("/etc/hostname")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(errs)
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            rec_path = run_dir / "frames" / "history.json"
            rec = json.loads(rec_path.read_text(encoding="utf-8"))
            rec["screenshot_path"] = "../escape.png"
            rec_path.write_text(json.dumps(rec, sort_keys=True),
                                encoding="utf-8")
            self.assertTrue(sev.validate_run_evidence(run_dir, manifest))


PROBE_MODEL = ("com.apple.CoreSimulator.SimDeviceType."
               "iPad-Pro-13-inch-M4-8GB")
PROBE_MODEL_NAME = "shot-ci-ipad13"


def _attested_probe(nonce=NONCE, run_id="ipad13-en-r1"):
    """Fully bound N/A probe: owned-device model attestation included."""
    return {"device_key": "ipad13",
            "island_available": False,
            "reason": "capability probe: no Dynamic Island",
            "run_id": run_id,
            "session_nonce": nonce,
            "geometry": {"width": 2064, "height": 2752},
            "model": {"deviceTypeIdentifier": PROBE_MODEL,
                      "name": PROBE_MODEL_NAME,
                      "udid": "UDID-9"},
            "source": "simctl-list"}


class IslandNATests(unittest.TestCase):
    def _ipad_run(self, tmp: str, with_probe=True, lock_only=True):
        run_dir = Path(tmp) / "runs" / "ipad13-en-r1"
        (run_dir / "frames").mkdir(parents=True)
        (run_dir / "sessions").mkdir(parents=True)
        sha = write_png(run_dir / "frames" / "la-lock.png", 2064, 2752)
        rec = {
            "schema_version": 1, "frame": "la-lock",
            "mode": rs.MODE_REALTIME, "device_udid": "UDID-9",
            "device_key": "ipad13", "run_id": "ipad13-en-r1",
            "deck_version": "en-austin-1", "treatment": "light-v1",
            "request_sha256": "a" * 64,
            "request_semantic_sha256": "b" * 64,
            "screenshot_sha256": sha,
            "geometry": {"width": 2064, "height": 2752},
            "expected_totals": {"all_seconds": 1, "today_seconds": 1,
                                "week_seconds": 1,
                                "category_seconds": {"A": 1},
                                "text_seconds": {"B": 1}},
            "capture": "external-lock-screen-pending",
            "pending_reason": "CI simctl pixels; human handoff",
            "session_nonce": NONCE, "session_domain": "realtime", "seq": 0,
        }
        (run_dir / "frames" / "la-lock.json").write_text(
            json.dumps(rec, sort_keys=True), encoding="utf-8")
        rcp = receipt(nonce=NONCE, run_id="ipad13-en-r1", domain="realtime",
                      final_seq=0, frames=["la-lock"])
        (run_dir / "sessions" / f"{NONCE}.receipt.json").write_text(
            json.dumps(rcp, sort_keys=True), encoding="utf-8")
        if with_probe:
            (run_dir / "sessions" / "island-probe.json").write_text(
                json.dumps(_attested_probe(), sort_keys=True),
                encoding="utf-8")
        manifest = {
            "schema_version": 1, "run_id": "ipad13-en-r1",
            "device_udid": "UDID-9", "device_key": "ipad13",
            "deck_version": "en-austin-1", "treatment": "light-v1",
            "geometry": {"width": 2064, "height": 2752},
            "frames": [rec], "status": "needs-inspection",
        }
        return run_dir, manifest

    def test_ipad_lock_plus_na_probe_valid(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._ipad_run(tmp)
            self.assertEqual(sev.validate_run_evidence(
                run_dir, manifest, required_frames=["la-lock"]), [])

    def test_ipad_island_missing_without_probe_is_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._ipad_run(tmp, with_probe=False)
            errs = sev.validate_run_evidence(
                run_dir, manifest,
                required_frames=["la-lock", "la-compact", "la-expanded"])
            self.assertTrue(errs)

    def test_ipad_lock_always_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._ipad_run(tmp)
            (run_dir / "frames" / "la-lock.png").unlink()
            errs = sev.validate_run_evidence(run_dir, manifest,
                                             required_frames=["la-lock"])
            self.assertTrue(any("la-lock" in e for e in errs))

    def test_fabricated_na_png_rejected(self):
        # A placeholder PNG filed under an N/A island frame is fabrication,
        # never evidence: N/A frames must have NO png, WITH a probe.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._ipad_run(tmp)
            write_png(run_dir / "frames" / "la-compact.png", 2064, 2752)
            (run_dir / "frames" / "la-compact.json").write_text(
                json.dumps({"frame": "la-compact", "status": "not-applicable"},
                           sort_keys=True), encoding="utf-8")
            errs = sev.validate_run_evidence(
                run_dir, manifest,
                required_frames=["la-lock", "la-compact"])
            self.assertTrue(errs)

    def _probe_case(self, tmp, mutate):
        run_dir, manifest = self._ipad_run(tmp)
        probe_path = run_dir / "sessions" / "island-probe.json"
        probe = json.loads(probe_path.read_text(encoding="utf-8"))
        mutate(probe)
        probe_path.write_text(json.dumps(probe, sort_keys=True),
                              encoding="utf-8")
        return sev.validate_run_evidence(run_dir, manifest,
                                         required_frames=["la-lock"])

    def test_probe_without_model_attestation_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            errs = self._probe_case(
                tmp, lambda p: p.pop("model"))
            self.assertTrue(any("attestation" in e for e in errs), errs)

    def test_probe_unknown_model_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            def mutate(p):
                p["model"]["deviceTypeIdentifier"] = (
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-99")
            self.assertTrue(self._probe_case(tmp, mutate))

    def test_probe_island_model_contradicts_na(self):
        with tempfile.TemporaryDirectory() as tmp:
            def mutate(p):
                p["model"]["deviceTypeIdentifier"] = (
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max")
            errs = self._probe_case(tmp, mutate)
            self.assertTrue(any("island" in e for e in errs), errs)

    def test_probe_wrong_source_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            errs = self._probe_case(
                tmp, lambda p: p.update(source="cli-flag"))
            self.assertTrue(any("source" in e for e in errs), errs)

    def test_probe_run_id_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            errs = self._probe_case(
                tmp, lambda p: p.update(run_id="other-run"))
            self.assertTrue(any("run_id" in e for e in errs), errs)

    def test_probe_nonce_must_join_realtime_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            errs = self._probe_case(
                tmp, lambda p: p.update(session_nonce="f" * 32))
            self.assertTrue(any("nonce" in e for e in errs), errs)

    def test_probe_geometry_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            errs = self._probe_case(
                tmp, lambda p: p.update(
                    geometry={"width": 1320, "height": 2868}))
            self.assertTrue(any("geometry" in e for e in errs), errs)

    def test_probe_wrong_ipad_model_rejected(self):
        # A different iPad model (real identifier, same geometry, matching
        # UDID) cannot attest catalog ipad13: exact catalog proof required.
        with tempfile.TemporaryDirectory() as tmp:
            def mutate(p):
                p["model"]["deviceTypeIdentifier"] = (
                    "com.apple.CoreSimulator.SimDeviceType."
                    "iPad-Air-11-inch-M4")
            errs = self._probe_case(tmp, mutate)
            self.assertTrue(any("catalog" in e for e in errs), errs)

    def test_probe_phantom_model_rejected(self):
        # The invented M3 identifier from the old panels fixture: iPad
        # prefix alone never suffices without catalog membership.
        with tempfile.TemporaryDirectory() as tmp:
            def mutate(p):
                p["model"]["deviceTypeIdentifier"] = "iPad-13-inch-M3"
            self.assertTrue(self._probe_case(tmp, mutate))

    def test_probe_wrong_udid_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            errs = self._probe_case(
                tmp, lambda p: p["model"].update(udid="UDID-OTHER"))
            self.assertTrue(any("UDID" in e for e in errs), errs)

    def test_probe_missing_udid_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            def mutate(p):
                del p["model"]["udid"]
            self.assertTrue(self._probe_case(tmp, mutate))

    def test_subset_still_requires_probe(self):
        # Partial required_frames must NOT waive capability attestation:
        # an iPad run validated for la-lock alone (or app frames + lock)
        # without a probe fails.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._ipad_run(tmp, with_probe=False)
            errs = sev.validate_run_evidence(run_dir, manifest,
                                             required_frames=["la-lock"])
            self.assertTrue(any("probe" in e for e in errs), errs)

    def test_probe_missing_metadata_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._ipad_run(tmp)
            probe_path = run_dir / "sessions" / "island-probe.json"
            for drop in ("run_id", "session_nonce", "geometry",
                         "device_key", "reason"):
                probe = json.loads(probe_path.read_text(encoding="utf-8"))
                del probe[drop]
                probe_path.write_text(json.dumps(probe, sort_keys=True),
                                      encoding="utf-8")
                errs = sev.validate_run_evidence(
                    run_dir, manifest, required_frames=["la-lock"])
                self.assertTrue(errs, drop)

    def test_false_manifest_na_claim_rejected(self):
        # An island-capable device must not claim N/A…
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            manifest = dict(manifest, na_frames=["la-compact"])
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("N/A" in e or "false" in e.lower()
                                for e in errs), errs)
        # …and la-lock can never be N/A on any device.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._ipad_run(tmp)
            manifest = dict(manifest, na_frames=["la-lock"])
            errs = sev.validate_run_evidence(run_dir, manifest,
                                             required_frames=["la-lock"])
            self.assertTrue(errs, errs)

    def test_unknown_device_key_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            for name in ("track-running", "insights", "history",
                         "add-entry"):
                p = run_dir / "frames" / f"{name}.json"
                r = json.loads(p.read_text(encoding="utf-8"))
                r["device_key"] = "gameboy"
                p.write_text(json.dumps(r, sort_keys=True), encoding="utf-8")
            frames = [dict(r, device_key="gameboy")
                      for r in manifest["frames"]]
            manifest = dict(manifest, frames=frames)
            self.assertTrue(sev.validate_run_evidence(run_dir, manifest))

    def test_iphone_needs_no_probe(self):
        # Sanity against over-tightening: island-capable runs validate
        # without any probe, full set or subset.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            self.assertEqual(sev.validate_run_evidence(run_dir, manifest), [])
            self.assertEqual(sev.validate_run_evidence(
                run_dir, manifest,
                required_frames=["track-running", "insights"]), [])

    def test_missing_queue_flag_rejected(self):
        # Fixed old receipts omit removed_session_queue: the session
        # cannot prove owned-queue removal.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            rp = run_dir / "sessions" / f"{NONCE}.receipt.json"
            rec = json.loads(rp.read_text(encoding="utf-8"))
            del rec["app_cleanup"]["removed_session_queue"]
            rp.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("removed_session_queue" in e for e in errs),
                            errs)

    def test_false_queue_flag_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            rp = run_dir / "sessions" / f"{NONCE}.receipt.json"
            rec = json.loads(rp.read_text(encoding="utf-8"))
            rec["app_cleanup"]["removed_session_queue"] = False
            rp.write_text(json.dumps(rec, sort_keys=True), encoding="utf-8")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("removed_session_queue" in e for e in errs),
                            errs)


class PendingVsGenuineTests(unittest.TestCase):
    def test_pending_handoff_is_not_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            sha = write_png(run_dir / "frames" / "la-lock.png")
            rec = frame_record("la-lock", sha, rs.MODE_REALTIME, 4,
                               extra={"capture": "external-lock-screen-pending",
                                      "pending_reason": "CI handoff",
                                      "session_domain": "realtime"})
            (run_dir / "frames" / "la-lock.json").write_text(
                json.dumps(rec, sort_keys=True), encoding="utf-8")
            manifest["frames"].append(rec)
            # Structural validity holds; genuine-vs-pending status stays in
            # the manifest/finalizer (existing inspection path), not an error.
            errs = sev.validate_run_evidence(
                run_dir, manifest,
                required_frames=["track-running", "insights", "history",
                                 "add-entry"])
            self.assertEqual(errs, [])

    def test_genuine_claim_without_binding_is_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = make_run(tmp)
            sha = write_png(run_dir / "frames" / "la-lock.png")
            rec = frame_record("la-lock", sha, rs.MODE_REALTIME, 4,
                               extra={"capture": "external-lock-screen",
                                      "session_domain": "realtime"})
            # No capture_window / observation_sha256: cannot be genuine.
            (run_dir / "frames" / "la-lock.json").write_text(
                json.dumps(rec, sort_keys=True), encoding="utf-8")
            manifest["frames"].append(rec)
            errs = sev.validate_run_evidence(
                run_dir, manifest,
                required_frames=["track-running", "insights", "history",
                                 "add-entry", "la-lock"])
            self.assertTrue(any("la-lock" in e for e in errs))


class ForgedManifestTests(unittest.TestCase):
    """Manifest-only invention must fail against untouched disk (audit R1).

    A1: status flip only. A2: invented capture/window/observation coherent
    in the manifest alone. Both must error; disk records/PNGs/receipts are
    never modified by these tests.
    """

    def _full_run(self, tmp):
        import os
        from test_session_run import two_domain_run

        udid = f"UDID-forge-{os.getpid()}"
        _fake, run_dir, pinned, realtime = two_domain_run(tmp, udid)
        frames = list(pinned["frames"]) + list(realtime["frames"])
        manifest = {
            "schema_version": 1, "run_id": "sess-e2e-r1",
            "device_udid": udid, "device_key": "iphone69",
            "deck_version": "en-austin-1", "treatment": "light-v1",
            "geometry": {"width": 1320, "height": 2868},
            "frames": frames, "status": "needs-inspection",
        }
        return run_dir, manifest

    def test_status_flip_only_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._full_run(tmp)
            manifest = dict(manifest, status="complete")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("pending" in e for e in errs), errs)

    def test_invented_genuine_in_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._full_run(tmp)
            frames = [dict(r) for r in manifest["frames"]]
            for rec in frames:
                if rec["frame"] == "la-lock":
                    rec["capture"] = "external-lock-screen"
                    rec["capture_window"] = {
                        "started_at": "2026-10-30T10:00:00+00:00",
                        "captured_at_iso": "2026-10-30T10:12:34+00:00",
                        "observed_elapsed_s": 754}
                    rec["observation_sha256"] = "0" * 64
                    rec.pop("pending_reason", None)
            manifest = dict(manifest, frames=frames, status="complete")
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(errs, "manifest-only invention accepted")
            # Disk is untouched: still the honest pending stub.
            disk = json.loads((run_dir / "frames" / "la-lock.json")
                              .read_text(encoding="utf-8"))
            self.assertEqual(disk["capture"],
                             "external-lock-screen-pending")

    def test_invented_window_duration_rejected(self):
        # Self-consistent manifest invention with a mismatched duration:
        # exact disk agreement fails first, and the numeric window check
        # would fail it independently.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._full_run(tmp)
            frames = [dict(r) for r in manifest["frames"]]
            for rec in frames:
                if rec["frame"] == "la-lock":
                    rec["capture"] = "external-lock-screen"
                    rec["capture_window"] = {
                        "started_at": "2026-10-30T10:00:00+00:00",
                        "captured_at_iso": "2026-10-30T10:12:34+00:00",
                        "observed_elapsed_s": 100}
                    rec["observation_sha256"] = "0" * 64
                    rec.pop("pending_reason", None)
            manifest = dict(manifest, frames=frames, status="complete")
            self.assertTrue(sev.validate_run_evidence(run_dir, manifest))

    def test_narrow_subset_complete_still_checks_disk(self):
        # `complete` is a whole-manifest claim: a narrowed app-frames-only
        # check with complete status and pending LA on disk fails, even
        # though the subset itself is clean.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._full_run(tmp)
            manifest = dict(manifest, status="complete")
            errs = sev.validate_run_evidence(
                run_dir, manifest,
                required_frames=["track-running", "insights", "history",
                                 "add-entry"])
            self.assertTrue(any("pending" in e for e in errs), errs)

    def test_anchor_split_rejected(self):
        # Two genuine states with different start anchors: each window is
        # numerically valid alone, but the session anchor must be one.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir, manifest = self._full_run(tmp)
            frames = [dict(r) for r in manifest["frames"]]
            for rec in frames:
                if rec["frame"] in ("la-lock", "la-compact"):
                    png_sha = rec["screenshot_sha256"]
                    start = ("2026-10-30T10:00:00+00:00"
                             if rec["frame"] == "la-lock"
                             else "2026-10-30T11:00:00+00:00")
                    rec["capture"] = "external-lock-screen"
                    rec["capture_window"] = {
                        "started_at": start,
                        "captured_at_iso": ("2026-10-30T10:12:34+00:00"
                                            if rec["frame"] == "la-lock"
                                            else "2026-10-30T11:12:34+00:00"),
                        "observed_elapsed_s": 754}
                    rec["observation_sha256"] = "0" * 64
                    rec.pop("pending_reason", None)
                    path = run_dir / "frames" / f"{rec['frame']}.json"
                    path.write_text(json.dumps(rec, sort_keys=True),
                                    encoding="utf-8")
                    self.assertEqual(png_sha, rec["screenshot_sha256"])
            manifest = dict(manifest, frames=frames)
            errs = sev.validate_run_evidence(run_dir, manifest)
            self.assertTrue(any("anchor" in e for e in errs), errs)


if __name__ == "__main__":
    unittest.main(verbosity=2)
