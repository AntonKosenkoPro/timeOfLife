#!/usr/bin/env python3
"""State validation + approval gate tests (fake adapter: dicts + tmp files)."""

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import approval as approval_mod
import request_schema as rs
import state_check as sc


def framed_request(frame="track-running", run_id="t1"):
    base = {k: v for k, v in json.loads(
        (HERE / "pilot_manifest.json").read_text(encoding="utf-8")).items()
        if k not in ("frame", "mode")}
    base["run_id"] = run_id
    return rs.build_frame_request(base, frame)


PINNED = {
    "all_seconds": 1000,
    "today_seconds": 100,
    "week_seconds": 500,
    "category_seconds": {"Work": 500},
    "text_seconds": {"Gym": 100},
}


def ready_state(request, digest, frame="track-running", extra=None):
    st = {
        "status": "ready",
        "request_sha256": digest,
        "deck_version": "en-austin-1",
        "frame": frame,
        "counts": {"entries": 55},
        "expected_totals": dict(PINNED),
        "build": {"configuration": "Screenshot",
                  "bundle_id": rs.SCREENSHOT_BID, "version": "0.0-test"},
    }
    if extra:
        st.update(extra)
    return st


def check_ready(testcase, state, request, digest):
    return sc.validate_state_dict(state, request, digest, dict(PINNED))


class StateCheckTests(unittest.TestCase):
    def test_preparing_is_pending(self):
        verdict, _ = sc.validate_state_dict({"status": "preparing"}, {}, "x" * 64)
        self.assertEqual(verdict, sc.PENDING)

    def test_ready_passes(self):
        request = framed_request()
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        verdict, errs = check_ready(self, ready_state(request, digest), request, digest)
        self.assertEqual((verdict, errs), (sc.OK, []))

    def test_count_mismatch_fails(self):
        request = framed_request()
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        st = ready_state(request, digest)
        st["counts"] = {"entries": 12}
        verdict, errs = check_ready(self, st, request, digest)
        self.assertEqual(verdict, sc.FAILED)
        self.assertTrue(any("entries" in e for e in errs))

    def test_request_sha_wrong_fails(self):
        request = framed_request()
        st = ready_state(request, "0" * 64)
        verdict, _ = check_ready(self, st, request, "f" * 64)
        self.assertEqual(verdict, sc.FAILED)

    def test_failure_requires_error_code(self):
        verdict, errs = sc.validate_state_dict(
            {"status": "failure", "error": {}}, {}, "x" * 64)
        self.assertEqual(verdict, sc.FAILED)
        self.assertTrue(any("error.code" in e for e in errs))

    def test_invalid_status_not_capturable(self):
        verdict, _ = sc.validate_state_dict({"status": "invalid"}, {}, "x" * 64)
        self.assertEqual(verdict, sc.FAILED)

    def test_wrong_build_identity_fails(self):
        request = framed_request()
        digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
        st = ready_state(request, digest)
        st["build"] = {"configuration": "Release", "bundle_id": "com.example.app"}
        verdict, errs = check_ready(self, st, request, digest)
        self.assertEqual(verdict, sc.FAILED)
        self.assertTrue(any("configuration" in e for e in errs))

    def test_la_ready_requires_realtime_metadata(self):
        for la_frame in ("la-lock", "la-compact", "la-expanded"):
            request = framed_request(la_frame)
            digest = rs.request_sha256_of_bytes(rs.canonical_bytes(request))
            st = ready_state(request, digest, frame=la_frame)
            verdict, errs = check_ready(self, st, request, digest)
            self.assertEqual(verdict, sc.FAILED, la_frame)
            self.assertTrue(any("live_activity" in e for e in errs), la_frame)
            st["live_activity"] = {
                "activity_id": "act-1",
                "started_at": "2026-10-30T10:00:00+00:00",
                "request_acknowledged_at": "2026-10-30T10:00:01+00:00",
            }
            verdict, errs = check_ready(self, st, request, digest)
            self.assertEqual((verdict, errs), (sc.OK, []), la_frame)

    def test_malformed_state_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            fh.write("[1,2")
            path = fh.name
        with self.assertRaises(sc.StateError):
            sc.load_state_file(path)


class ApprovalGateTests(unittest.TestCase):
    def _retained(self, tmp: str, n_frames: int = 7):
        root = Path(tmp)
        (root / "frames").mkdir()
        manifest = {"schema_version": 1, "deck_version": "en-austin-1",
                    "treatment": "light-v1",
                    "frames": list(rs.PILOT_FRAMES)}
        (root / "pilot_manifest.json").write_bytes(
            json.dumps(manifest, sort_keys=True).encode() + b"\n")
        hashes = {}
        for frame in list(rs.PILOT_FRAMES)[:n_frames]:
            data = f"png-bytes-{frame}".encode()
            (root / "frames" / f"{frame}.png").write_bytes(data)
            hashes[frame] = hashlib.sha256(data).hexdigest()
        approval = {
            "schema_version": 1,
            "decision": "approved",
            "pilot_manifest_sha256": hashlib.sha256(
                (root / "pilot_manifest.json").read_bytes()).hexdigest(),
            "deck_version": "en-austin-1",
            "treatment": "light-v1",
            "frame_hashes": hashes,
            "retained_location": tmp,
        }
        return approval

    def test_pilot_needs_no_approval(self):
        self.assertEqual(approval_mod.gate_kind("pilot", None, None), [])

    def test_ipad_blocked_without_approval(self):
        errs = approval_mod.gate_kind("ipad", None, None)
        self.assertTrue(errs and "5.4" in errs[0])

    def test_non_approved_decision_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap = self._retained(tmp)
            ap["decision"] = "pending-review"
            errs = approval_mod.verify_approval(ap, tmp)
            self.assertTrue(any("not 'approved'" in e for e in errs))

    def test_missing_frame_file_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap = self._retained(tmp, n_frames=4)
            errs = approval_mod.verify_approval(ap, tmp)
            self.assertTrue(any("la-" in e for e in errs))

    def test_tampered_frame_invalidates(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap = self._retained(tmp)
            (Path(tmp) / "frames" / "history.png").write_bytes(b"changed")
            errs = approval_mod.verify_approval(ap, tmp)
            self.assertTrue(any("history" in e for e in errs))

    def test_valid_approval_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap = self._retained(tmp)
            self.assertEqual(approval_mod.verify_approval(ap, tmp), [])

    def test_tests_do_not_imply_approval(self):
        # gate_kind with no approval file must block even for valid kinds
        for kind in ("non-english", "montage", "ipad"):
            self.assertTrue(approval_mod.gate_kind(kind, None, None))

    def _approval_file(self, tmp: str) -> str:
        ap = self._retained(tmp)
        ap_path = str(Path(tmp) / "approval.json")
        Path(ap_path).write_text(json.dumps(ap), encoding="utf-8")
        return ap_path

    def test_request_gates_pilot_open(self):
        self.assertEqual(
            approval_mod.gates_for_request("en", (1320, 2868), None, None), [])

    def test_request_gates_non_english_blocked_without_approval(self):
        errs = approval_mod.gates_for_request("ru", (1320, 2868), None, None)
        self.assertTrue(errs and any("non-english" in e for e in errs))

    def test_request_gates_non_english_allowed_with_approval(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap_path = self._approval_file(tmp)
            self.assertEqual(
                approval_mod.gates_for_request("ru", (1320, 2868),
                                               ap_path, tmp), [])

    def test_request_gates_ipad_blocked_without_approval(self):
        errs = approval_mod.gates_for_request("en", (2064, 2752), None, None)
        self.assertTrue(errs and any("ipad" in e for e in errs))

    def test_request_gates_ipad_allowed_with_approval(self):
        with tempfile.TemporaryDirectory() as tmp:
            ap_path = self._approval_file(tmp)
            self.assertEqual(
                approval_mod.gates_for_request("en", (2064, 2752),
                                               ap_path, tmp), [])

    def test_request_gates_both_apply_at_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            # ru + iPad without approval reports both gates
            errs = approval_mod.gates_for_request("ru", (2064, 2752), None, None)
            self.assertEqual(len(errs), 2)
            ap_path = self._approval_file(tmp)
            self.assertEqual(
                approval_mod.gates_for_request("ru", (2064, 2752),
                                               ap_path, tmp), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
