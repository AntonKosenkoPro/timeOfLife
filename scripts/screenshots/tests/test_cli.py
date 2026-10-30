#!/usr/bin/env python3
"""CLI tests via subprocess (dry-run only; no device, no owner-dir writes)."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
CLI = str(HERE / "capture.py")

sys.path.insert(0, str(HERE))


def run(*argv: str, env_extra: dict | None = None):
    import os
    env = dict(os.environ)
    env.pop("LIFIO_CAPTURE_LEASE", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run([sys.executable, CLI, *argv],
                          capture_output=True, text=True, timeout=60, env=env)


PINNED_TOTALS = {"all_seconds": 1, "today_seconds": 1, "week_seconds": 1,
                 "category_seconds": {"A": 1}, "text_seconds": {"B": 1}}


def write_pin(tmp: str) -> str:
    p = str(Path(tmp) / "pin.json")
    Path(p).write_text(json.dumps(PINNED_TOTALS), encoding="utf-8")
    return p


def make_approval(retained: str) -> tuple[dict, str]:
    """Build a valid 5.4 approval bound to files under retained (outside repo)."""
    import hashlib
    sys.path.insert(0, str(HERE))
    import request_schema as rs
    root = Path(retained)
    (root / "frames").mkdir(exist_ok=True)
    manifest = {"schema_version": 1, "deck_version": "en-austin-1",
                "treatment": "light-v1", "frames": list(rs.PILOT_FRAMES)}
    (root / "pilot_manifest.json").write_bytes(
        json.dumps(manifest, sort_keys=True).encode() + b"\n")
    hashes = {}
    for frame in rs.PILOT_FRAMES:
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
        "retained_location": retained,
    }
    ap_path = str(Path(retained) / "approval.json")
    Path(ap_path).write_text(json.dumps(approval), encoding="utf-8")
    return approval, ap_path


def write_frame_request(tmp: str, frame: str = "track-running") -> str:
    sys.path.insert(0, str(HERE))
    import request_schema as rs
    base = json.loads((HERE / "pilot_manifest.json").read_text(encoding="utf-8"))
    base = {k: v for k, v in base.items() if k not in ("frame", "mode")}
    derived = rs.build_frame_request(base, frame)
    raw = rs.canonical_bytes(derived)
    p = str(Path(tmp) / f"{frame}.request.json")
    Path(p).write_bytes(raw)
    return p


class CliTests(unittest.TestCase):
    def test_validate_and_write_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            req = write_frame_request(tmp)
            proc = run("validate-request", "--request", req)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            out = str(Path(tmp) / "out.json")
            proc = run("write-request", "--request", str(HERE / "pilot_manifest.json"),
                       "--frame", "history", "--out", out)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertRegex(proc.stdout.strip(), r"^[0-9a-f]{64}$")

    def test_validate_rejects_unknown_frame_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            req = write_frame_request(tmp)
            obj = json.loads(Path(req).read_text(encoding="utf-8"))
            obj["locale"] = "xx"
            Path(req).write_text(json.dumps(obj), encoding="utf-8")
            proc = run("validate-request", "--request", req)
            self.assertEqual(proc.returncode, 2)

    def test_preflight_dry_run_no_device_touch(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run("preflight", "--device", "AAAA1111-2222-3333-4444-555566667777",
                       "--out", tmp)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            plan = json.loads(proc.stdout)
            self.assertIn("snapshot_commands", plan)
            self.assertIn("unsupported_note", plan)

    def test_preflight_rejects_booted_and_repo_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run("preflight", "--device", "booted", "--out", tmp)
            self.assertEqual(proc.returncode, 2)
            repo = str(HERE.parent.parent)
            proc = run("preflight", "--device", "AAAA1111-1", "--out", repo)
            self.assertEqual(proc.returncode, 2)

    def test_preflight_execute_refused_without_lease(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run("preflight", "--device", "AAAA1111-1", "--out", tmp,
                       "--execute")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("LIFIO_CAPTURE_LEASE", proc.stderr)

    def test_check_state_ready_and_preparing(self):
        import request_schema as rs
        with tempfile.TemporaryDirectory() as tmp:
            req = write_frame_request(tmp)
            pin = write_pin(tmp)
            digest = rs.request_sha256_of_bytes(Path(req).read_bytes())
            state = {
                "status": "ready", "request_sha256": digest,
                "deck_version": "en-austin-1", "frame": "track-running",
                "counts": {"entries": 55},
                "expected_totals": dict(PINNED_TOTALS),
                "build": {"configuration": "Screenshot",
                          "bundle_id": rs.SCREENSHOT_BID},
            }
            sp = str(Path(tmp) / "state.json")
            Path(sp).write_text(json.dumps(state), encoding="utf-8")
            proc = run("check-state", "--request", req, "--state", sp,
                       "--pinned-totals", pin)
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            # ready without a pin is refused (core dictionary pending)
            proc = run("check-state", "--request", req, "--state", sp)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("pin", proc.stderr + proc.stdout)
            Path(sp).write_text(json.dumps({"status": "preparing"}), encoding="utf-8")
            proc = run("check-state", "--request", req, "--state", sp,
                       "--pinned-totals", pin)
            self.assertEqual(proc.returncode, 3)

    def test_lease_verbs_refused_without_lease(self):
        with tempfile.TemporaryDirectory() as tmp:
            req = write_frame_request(tmp)
            proc = run("prepare-frame", "--device", "UDID-X", "--request", req,
                       "--frame", "track-running", "--out", tmp,
                       "--run-id", "r1")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("LIFIO_CAPTURE_LEASE", proc.stderr)
            proc = run("capture-app-frame", "--device", "UDID-X", "--out", tmp,
                       "--run-id", "r1", "--frame", "track-running")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("LIFIO_CAPTURE_LEASE", proc.stderr)
            proc = run("teardown-frame", "--device", "UDID-X", "--out", tmp,
                       "--run-id", "r1", "--frame", "track-running")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("LIFIO_CAPTURE_LEASE", proc.stderr)
            proc = run("run-frame", "--device", "UDID-X", "--request", req,
                       "--frame", "track-running", "--out", tmp,
                       "--run-id", "r1")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("LIFIO_CAPTURE_LEASE", proc.stderr)

    def test_verify_la_cli_binding(self):
        import struct
        import zlib
        with tempfile.TemporaryDirectory() as tmp:
            png = Path(tmp) / "la.png"
            ihdr = struct.pack(">IIBBBBB", 1320, 2868, 8, 2, 0, 0, 0)
            png.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13)
                            + b"IHDR" + ihdr
                            + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))
            import hashlib
            sha = hashlib.sha256(png.read_bytes()).hexdigest()
            state = {"status": "ready", "live_activity": {
                "activity_id": "a", "started_at": "2026-10-30T10:00:00+00:00",
                "request_acknowledged_at": "2026-10-30T10:00:01+00:00"}}
            sp = str(Path(tmp) / "state.json")
            Path(sp).write_text(json.dumps(state), encoding="utf-8")
            obs = {"observed_elapsed_s": 754, "screenshot_sha256": sha}
            op = str(Path(tmp) / "obs.json")
            Path(op).write_text(json.dumps(obs), encoding="utf-8")
            proc = run("verify-la", "--state", sp, "--screenshot", str(png),
                       "--captured-at", "2026-10-30T10:12:34+00:00",
                       "--observation", op)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            # missing observation stays pending, never a pass
            proc = run("verify-la", "--state", sp, "--screenshot", str(png),
                       "--captured-at", "2026-10-30T10:12:34+00:00")
            self.assertEqual(proc.returncode, 3)

    def test_verify_picker_cli_binding(self):
        import struct
        import zlib
        with tempfile.TemporaryDirectory() as tmp:
            req = write_frame_request(tmp, "add-entry")
            png = Path(tmp) / "picker.png"
            ihdr = struct.pack(">IIBBBBB", 1320, 2868, 8, 2, 0, 0, 0)
            png.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13)
                            + b"IHDR" + ihdr
                            + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))
            import hashlib
            sha = hashlib.sha256(png.read_bytes()).hexdigest()
            ev = Path(tmp) / "ax.txt"
            ev.write_text("keyboard dump en-US")
            rec = {"keyboard_visible": True,
                   "keyboard_language_observed": "en-US",
                   "presentation_observed": "docked",
                   "evidence_artifact": str(ev), "screenshot_sha256": sha}
            ip = str(Path(tmp) / "insp.json")
            Path(ip).write_text(json.dumps(rec), encoding="utf-8")
            proc = run("verify-picker", "--inspection", ip,
                       "--screenshot", str(png), "--request", req)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            evidence = json.loads(proc.stdout)
            self.assertEqual(evidence["screenshot_sha256"], sha)
            # wrong language fails
            rec["keyboard_language_observed"] = "fr-FR"
            Path(ip).write_text(json.dumps(rec), encoding="utf-8")
            proc = run("verify-picker", "--inspection", ip,
                       "--screenshot", str(png), "--request", req)
            self.assertNotEqual(proc.returncode, 0)

    def test_check_approval_gates(self):
        proc = run("check-approval", "--kind", "pilot")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        proc = run("check-approval", "--kind", "montage")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("5.4", proc.stderr)

    def test_plan_run_two_runs_en_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = run("plan-run", "--request", str(HERE / "pilot_manifest.json"),
                       "--device", "AAAA1111-2222-3333-4444-555566667777",
                       "--out", tmp, "--run-id", "pilot", "--runs", "2")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            plan = json.loads(proc.stdout)
            self.assertEqual(len(plan["runs"]), 2)
            self.assertEqual(len(plan["runs"][0]["steps"]), 7)
            proc = run("plan-run", "--request", str(HERE / "pilot_manifest.json"),
                       "--device", "AAAA1111-2222-3333-4444-555566667777",
                       "--out", tmp, "--run-id", "pilot", "--runs", "1")
            self.assertEqual(proc.returncode, 2)

    def test_plan_run_non_english_gated_by_approval(self):
        import hashlib
        sys.path.insert(0, str(HERE))
        import request_schema as rs
        with tempfile.TemporaryDirectory() as tmp:
            base = json.loads((HERE / "pilot_manifest.json").read_text(encoding="utf-8"))
            base = {k: v for k, v in base.items() if k not in ("frame", "mode")}
            base["locale"] = "ru"
            base["region"] = "RU"
            base["timezone"] = "Europe/Moscow"
            base["keyboard"] = {"language": "ru-RU", "software_visible": True,
                                "presentation": "docked"}
            probe = dict(base, frame="track-running", mode=rs.MODE_PINNED)
            self.assertEqual(rs.validate_request_dict(probe), [])
            bp = str(Path(tmp) / "base-ru.json")
            Path(bp).write_text(json.dumps(base), encoding="utf-8")
            # blocked without approval
            proc = run("plan-run", "--request", bp,
                       "--device", "AAAA1111-2222-3333-4444-555566667777",
                       "--out", tmp, "--run-id", "pilot-ru", "--runs", "2")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("blocked", proc.stderr)
            # allowed with a valid 5.4 approval file
            with tempfile.TemporaryDirectory() as retained:
                approval, ap_path = make_approval(retained)
                proc = run("plan-run", "--request", bp,
                           "--device", "AAAA1111-2222-3333-4444-555566667777",
                           "--out", tmp, "--run-id", "pilot-ru", "--runs", "2",
                           "--approval", ap_path, "--retained-dir", retained)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                plan = json.loads(proc.stdout)
                self.assertEqual(len(plan["runs"]), 2)

    def test_plan_run_ipad_geometry_gated_by_approval(self):
        with tempfile.TemporaryDirectory() as tmp:
            # non-pilot geometry blocked without approval
            proc = run("plan-run", "--request", str(HERE / "pilot_manifest.json"),
                       "--device", "AAAA1111-2222-3333-4444-555566667777",
                       "--out", tmp, "--run-id", "pilot", "--runs", "2",
                       "--geometry", "2064x2752")
            self.assertEqual(proc.returncode, 2)
            self.assertIn("blocked", proc.stderr)
            with tempfile.TemporaryDirectory() as retained:
                approval, ap_path = make_approval(retained)
                proc = run("plan-run", "--request", str(HERE / "pilot_manifest.json"),
                           "--device", "AAAA1111-2222-3333-4444-555566667777",
                           "--out", tmp, "--run-id", "pilot", "--runs", "2",
                           "--geometry", "2064x2752",
                           "--approval", ap_path, "--retained-dir", retained)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                plan = json.loads(proc.stdout)
                self.assertEqual(plan["runs"][0]["geometry"],
                                 {"width": 2064, "height": 2752})
            # unsupported geometry is invalid even with approval
            with tempfile.TemporaryDirectory() as retained:
                approval, ap_path = make_approval(retained)
                proc = run("plan-run", "--request", str(HERE / "pilot_manifest.json"),
                           "--device", "AAAA1111-2222-3333-4444-555566667777",
                           "--out", tmp, "--run-id", "pilot", "--runs", "2",
                           "--geometry", "100x100",
                           "--approval", ap_path, "--retained-dir", retained)
                self.assertEqual(proc.returncode, 2)

    def test_check_state_non_english_gated_by_approval(self):
        import request_schema as rs
        with tempfile.TemporaryDirectory() as tmp:
            ru_totals = rs.load_pinned_totals_for_locale("ru")
            pin = str(Path(tmp) / "pin-ru.json")
            Path(pin).write_text(json.dumps(ru_totals), encoding="utf-8")
            base = json.loads((HERE / "pilot_manifest.json").read_text(encoding="utf-8"))
            base = {k: v for k, v in base.items() if k not in ("frame", "mode")}
            base["locale"] = "ru"
            base["region"] = "RU"
            base["timezone"] = "Europe/Moscow"
            base["keyboard"] = {"language": "ru-RU", "software_visible": True,
                                "presentation": "docked"}
            derived = rs.build_frame_request(base, "track-running")
            req_path = str(Path(tmp) / "ru.request.json")
            Path(req_path).write_bytes(rs.canonical_bytes(derived))
            digest = rs.request_sha256_of_bytes(Path(req_path).read_bytes())
            state = {
                "status": "ready", "request_sha256": digest,
                "deck_version": "en-austin-1", "frame": "track-running",
                "counts": {"entries": 55},
                "expected_totals": dict(ru_totals),
                "build": {"configuration": "Screenshot",
                          "bundle_id": rs.SCREENSHOT_BID},
            }
            sp = str(Path(tmp) / "state.json")
            Path(sp).write_text(json.dumps(state), encoding="utf-8")
            # ru week pin differs from en: sanity on the fixture quirk
            self.assertEqual(ru_totals["week_seconds"], 12300)
            proc = run("check-state", "--request", req_path, "--state", sp,
                       "--pinned-totals", pin)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("blocked", proc.stderr)
            with tempfile.TemporaryDirectory() as retained:
                approval, ap_path = make_approval(retained)
                proc = run("check-state", "--request", req_path, "--state", sp,
                           "--pinned-totals", pin,
                           "--approval", ap_path, "--retained-dir", retained)
                self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            # wrong-locale pin (en totals against ru state) must fail even approved
            en_pin = str(Path(tmp) / "pin-en.json")
            Path(en_pin).write_text(
                json.dumps(rs.load_pinned_totals_for_locale("en")), encoding="utf-8")
            with tempfile.TemporaryDirectory() as retained:
                approval, ap_path = make_approval(retained)
                proc = run("check-state", "--request", req_path, "--state", sp,
                           "--pinned-totals", en_pin,
                           "--approval", ap_path, "--retained-dir", retained)
                self.assertEqual(proc.returncode, 2)

    def test_locale_totals_verb(self):
        import request_schema as rs
        with tempfile.TemporaryDirectory() as tmp:
            for locale, week in (("en", 23100), ("ru", 12300),
                                 ("zh-Hans", 23100), ("es-419", 23100),
                                 ("pt-BR", 23100)):
                proc = run("locale-totals", "--locale", locale)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                totals = json.loads(proc.stdout)
                self.assertEqual(totals["week_seconds"], week, locale)
                self.assertEqual(totals, rs.load_pinned_totals_for_locale(locale))
            proc = run("locale-totals", "--locale", "xx")
            self.assertEqual(proc.returncode, 2)

    def test_record_external_frame_and_finalize(self):
        import hashlib
        import struct
        import zlib
        with tempfile.TemporaryDirectory() as tmp:
            req = write_frame_request(tmp, "la-lock")
            pin = write_pin(tmp)
            digest = hashlib.sha256(Path(req).read_bytes()).hexdigest()
            state = {
                "status": "ready", "request_sha256": digest,
                "deck_version": "en-austin-1", "frame": "la-lock",
                "counts": {"entries": 55},
                "expected_totals": dict(PINNED_TOTALS),
                "build": {"configuration": "Screenshot",
                          "bundle_id": "com.antonkosenko.timeoflifeapp.screenshots"},
                "live_activity": {
                    "activity_id": "a",
                    "started_at": "2026-10-30T10:00:00+00:00",
                    "request_acknowledged_at": "2026-10-30T10:00:01+00:00"},
            }
            sp = str(Path(tmp) / "state.json")
            Path(sp).write_text(json.dumps(state), encoding="utf-8")
            png = Path(tmp) / "lock.png"
            ihdr = struct.pack(">IIBBBBB", 1320, 2868, 8, 2, 0, 0, 0)
            png.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13)
                            + b"IHDR" + ihdr
                            + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr) & 0xFFFFFFFF))
            sha = hashlib.sha256(png.read_bytes()).hexdigest()
            op = str(Path(tmp) / "obs.json")
            Path(op).write_text(json.dumps(
                {"observed_elapsed_s": 754, "screenshot_sha256": sha}),
                encoding="utf-8")
            proc = run("record-external-frame", "--out", tmp, "--run-id", "r1",
                       "--frame", "la-lock", "--png", str(png),
                       "--captured-at", "2026-10-30T10:12:34+00:00",
                       "--observation", op, "--state", sp, "--request", req,
                       "--pinned-totals", pin, "--device", "UDID-X")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            record = json.loads(proc.stdout)
            self.assertEqual(record["capture"], "external-lock-screen")
            # wrong frame refused
            proc = run("record-external-frame", "--out", tmp, "--run-id", "r1",
                       "--frame", "insights", "--png", str(png),
                       "--captured-at", "2026-10-30T10:12:34+00:00",
                       "--observation", op, "--state", sp, "--request", req,
                       "--pinned-totals", pin)
            self.assertEqual(proc.returncode, 2)

    def test_finalize_run_provenance_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = str(Path(tmp) / "prov.json")
            Path(bad).write_text(json.dumps({"commit_base": "", "dirty": "yes"}),
                                 encoding="utf-8")
            proc = run("finalize-run", "--out", tmp, "--run-id", "r1",
                       "--provenance", bad)
            # empty run dir -> fatal before provenance shape matters, or shape error;
            # either way never a silent pass
            self.assertNotEqual(proc.returncode, 0)

    def test_finalize_two_runs_cli(self):
        def manifest(frames, totals, run_id):
            return {"schema_version": 1, "run_id": run_id,
                    "device_udid": "U", "deck_version": "en-austin-1",
                    "treatment": "light-v1",
                    "geometry": {"width": 1320, "height": 2868},
                    "frames": frames, "status": "complete"}

        def recs(shot="p" * 64, totals=None):
            t = dict(PINNED_TOTALS) if totals is None else totals
            return [{"frame": f, "request_sha256": "a" * 64,
                     "request_semantic_sha256": "s" * 64,
                     "screenshot_sha256": shot, "expected_totals": t}
                    for f in ("track-running", "insights", "history",
                              "add-entry", "la-lock", "la-compact",
                              "la-expanded")]

        with tempfile.TemporaryDirectory() as tmp:
            for suffix in ("-r1", "-r2"):
                d = Path(tmp) / "runs" / ("pilot" + suffix)
                d.mkdir(parents=True)
                (d / "run-manifest.json").write_text(
                    json.dumps(manifest(recs(), dict(PINNED_TOTALS), "pilot" + suffix)),
                    encoding="utf-8")
            proc = run("finalize-two-runs", "--out", tmp, "--run-id-base", "pilot")
            self.assertEqual(proc.returncode, 0, proc.stderr)
            verdict = json.loads(proc.stdout)
            self.assertEqual(verdict["status"], "complete")
            # png drift -> pending with explicit variance, never silent pass
            d2 = Path(tmp) / "runs" / "pilot-r2" / "run-manifest.json"
            m2 = json.loads(d2.read_text(encoding="utf-8"))
            m2["frames"][0]["screenshot_sha256"] = "q" * 64
            d2.write_text(json.dumps(m2), encoding="utf-8")
            proc = run("finalize-two-runs", "--out", tmp, "--run-id-base", "pilot")
            self.assertEqual(proc.returncode, 3)
            verdict = json.loads(proc.stdout)
            self.assertEqual(verdict["unreviewed_variance"], ["track-running"])
            # totals drift -> hard failure
            m2["frames"][1]["expected_totals"] = dict(PINNED_TOTALS, week_seconds=2)
            d2.write_text(json.dumps(m2), encoding="utf-8")
            proc = run("finalize-two-runs", "--out", tmp, "--run-id-base", "pilot")
            self.assertEqual(proc.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
