#!/usr/bin/env python3
"""Device-worker outer-loop tests (thin loop only; fake subprocess).

Deterministic, no macOS work: a FakeRun scripts capture.py exit codes
and records argv/env. Covers per-locale out scoping matching the
panels harvest layout, argv shape incl. --device-key/--island
agreement, subset dispatch, failed-locale contamination (earlier
artifacts preserved, later pairs unattempted), rc3 needs-inspection vs
fatal, launch-exception containment, KeyboardInterrupt boundary,
summary-write visibility, pair-failure survival through the canonical
wa.worker_summary path, cancel, capacity honesty (no invented queue
proof), provenance forwarding, lease explicitness, and no sim
create/install ownership.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import run_device_worker as wdw


def ok_handler(argv, n, calls):
    return 0, "{}\n", ""


class FakeRun:
    def __init__(self, handler):
        self.calls = []
        self.handler = handler

    def __call__(self, argv, env):
        self.calls.append({"argv": list(argv), "env": dict(env)})
        rc, out, err = self.handler(argv, len(self.calls), self.calls)
        return SimpleNamespace(returncode=rc, stdout=out, stderr=err)

    def verbs(self):
        return [c["argv"][2] for c in self.calls]

    def argv_for(self, verb, domain=None):
        out = []
        for c in self.calls:
            if c["argv"][2] != verb:
                continue
            if domain is not None and "--domain" in c["argv"]:
                i = c["argv"].index("--domain")
                if c["argv"][i + 1] != domain:
                    continue
            out.append(c["argv"])
        return out


def base_env():
    env = dict(os.environ)
    env["LIFIO_CAPTURE_LEASE"] = "1"
    return env


def execute(tmp, fake, **over):
    kwargs = {"device_key": "iphone69", "device_udid": "UDID-1",
              "locales": ["en"], "out_dir": Path(tmp) / "shots",
              "capture_py": HERE / "capture.py",
              "provenance": None, "cancel_file": None,
              "run": fake, "env": base_env()}
    kwargs.update(over)
    return wdw.execute(**kwargs)


def status_path(tmp, dev="iphone69", loc="en", p="r1"):
    return Path(tmp) / "shots" / dev / loc / f"{dev}-{loc}-{p}.status.json"


def summary_path(tmp, dev="iphone69"):
    return Path(tmp) / "shots" / dev / "worker-summary.json"


def locale_of_rid(rid, dev="iphone69"):
    assert rid.startswith(dev + "-") and rid[-3] == "-"
    return rid[len(dev) + 1:-3]


class LayoutTests(unittest.TestCase):
    def test_per_locale_out_scoping_matches_harvest_layout(self):
        def handler(argv, n, calls):
            verb = argv[2]
            if verb in ("run-session", "finalize-run"):
                out = Path(argv[argv.index("--out") + 1])
                rid = argv[argv.index("--run-id") + 1]
                rundir = out / "runs" / rid
                rundir.mkdir(parents=True, exist_ok=True)
                (rundir / "run-manifest.json").write_text(
                    json.dumps({"run_id": rid}), encoding="utf-8")
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 0)
            shots = Path(tmp) / "shots"
            for argv in (fake.argv_for("run-session")
                         + fake.argv_for("finalize-run")
                         + fake.argv_for("finalize-two-runs")):
                verb = argv[2]
                out = Path(argv[argv.index("--out") + 1])
                if verb == "finalize-two-runs":
                    base = argv[argv.index("--run-id-base") + 1]
                    loc = locale_of_rid(base + "-r1")
                else:
                    loc = locale_of_rid(argv[argv.index("--run-id") + 1])
                self.assertEqual(out, shots / "iphone69" / loc, argv)
            # fake CLI output landed exactly where panels harvest reads it:
            # shots/<device>/<locale>/runs/<rid>/run-manifest.json
            for loc in ("en", "ru"):
                for p in ("r1", "r2"):
                    rid = f"iphone69-{loc}-{p}"
                    self.assertTrue(
                        (shots / "iphone69" / loc / "runs" / rid
                         / "run-manifest.json").is_file(), rid)
                    self.assertTrue(status_path(tmp, loc=loc, p=p).is_file())
            # device summary lives at the device root, not in one locale
            self.assertTrue(summary_path(tmp).is_file())
            self.assertFalse(
                (shots / "iphone69" / "en" / "worker-summary.json").exists())

    def test_pair_failure_survives_canonical_path(self):
        def handler(argv, n, calls):
            if argv[2] == "finalize-two-runs":
                return 2, "", "failed: semantic mismatch"
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, summary = execute(tmp, fake, locales=["en"])
            self.assertEqual(code, 1)
            import workflow_artifacts as wa
            recs = [wa.load_status(status_path(tmp, p=p)) for p in ("r1", "r2")]
            canonical = wa.worker_summary("iphone69", ["en"], recs)
            # canonical pass evidence still says complete (passes captured
            # fine); the worker must not let that hide the pair failure
            self.assertTrue(canonical["pairs"][0]["complete"])
            on_disk = json.loads(summary_path(tmp).read_text(
                encoding="utf-8"))
            self.assertTrue(on_disk["canonical_pairs"][0]["complete"])
            self.assertFalse(on_disk["effective_complete"])
            self.assertTrue(on_disk["pairs"]["en"]["pair_failed"])
            self.assertEqual(recs[0]["status"], "ok")
            self.assertEqual(recs[1]["status"], "ok")


class ArgvShapeTests(unittest.TestCase):
    def test_full_argv_sequence_subset(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 0)
            per_locale = ["make-request", "locale-totals",
                          "run-session", "run-session", "finalize-run",
                          "run-session", "run-session", "finalize-run",
                          "finalize-two-runs"]
            self.assertEqual(fake.verbs(), per_locale + per_locale)

    def test_run_session_flags_agree_with_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            execute(tmp, fake, locales=["en"])
            pinned = fake.argv_for("run-session", "pinned")
            self.assertEqual(len(pinned), 2)
            argv = pinned[0]
            get = lambda flag: argv[argv.index(flag) + 1]
            self.assertEqual(get("--device"), "UDID-1")
            self.assertEqual(get("--device-key"), "iphone69")
            self.assertEqual(get("--geometry"), "1320x2868")
            self.assertEqual(get("--island"), "1")
            self.assertEqual(get("--run-id"), "iphone69-en-r1")
            self.assertEqual(
                Path(get("--out")), Path(tmp) / "shots" / "iphone69" / "en")
            self.assertIn("--pinned-totals", argv)
            self.assertIn("--request", argv)
            realtime = fake.argv_for("run-session", "realtime")
            self.assertEqual(len(realtime), 2)
            self.assertEqual(
                realtime[0][realtime[0].index("--run-id") + 1],
                "iphone69-en-r1")

    def test_ipad_island_zero_and_geometry(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake, device_key="ipad13",
                              locales=["en"])
            self.assertEqual(code, 0)
            pinned = fake.argv_for("run-session", "pinned")
            argv = pinned[0]
            self.assertEqual(argv[argv.index("--island") + 1], "0")
            self.assertEqual(argv[argv.index("--geometry") + 1], "2064x2752")

    def test_lease_env_explicit_on_children(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            execute(tmp, fake, locales=["en"])
            self.assertTrue(fake.calls)
            for c in fake.calls:
                self.assertEqual(c["env"].get("LIFIO_CAPTURE_LEASE"), "1")

    def test_no_sim_create_install_ownership(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            execute(tmp, fake, locales=["en", "ru"])
            blob = json.dumps([c["argv"] for c in fake.calls])
            for token in ("simctl", "create", "boot", "install", "delete"):
                self.assertNotIn(token, blob)

    def test_invalid_device_key_calls_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake, device_key="iphone65")
            self.assertEqual(code, 2)
            self.assertEqual(fake.calls, [])

    def test_provenance_forwarded(self):
        with tempfile.TemporaryDirectory() as tmp:
            prov = Path(tmp) / "prov.json"
            prov.write_text(json.dumps({"commit_base": "a" * 40,
                                        "dirty": False}), encoding="utf-8")
            fake = FakeRun(ok_handler)
            execute(tmp, fake, locales=["en"], provenance=str(prov))
            finals = fake.argv_for("finalize-run")
            self.assertEqual(len(finals), 2)
            for argv in finals:
                self.assertEqual(argv[argv.index("--provenance") + 1],
                                 str(prov))
                self.assertEqual(
                    Path(argv[argv.index("--out") + 1]),
                    Path(tmp) / "shots" / "iphone69" / "en")
            fake2 = FakeRun(ok_handler)
            execute(tmp, fake2, locales=["en"])
            for argv in fake2.argv_for("finalize-run"):
                self.assertNotIn("--provenance", argv)


class ContaminationTests(unittest.TestCase):
    def test_failed_locale_stops_later_work_preserves_earlier(self):
        def handler(argv, n, calls):
            if argv[2] == "run-session" and "--domain" in argv:
                i = argv.index("--run-id")
                if argv[i + 1] == "iphone69-ru-r1":
                    return 2, "", "failed: pinned session refused"
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, summary = execute(tmp, fake, locales=["en", "ru", "pt-BR"])
            self.assertEqual(code, 1)
            for loc, p in (("en", "r1"), ("en", "r2"), ("ru", "r1"),
                           ("ru", "r2"), ("pt-BR", "r1"), ("pt-BR", "r2")):
                self.assertTrue(status_path(tmp, loc=loc, p=p).is_file(),
                                (loc, p))
            import workflow_artifacts as wa
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="ru", p="r1"))["status"],
                "failed")
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="ru", p="r2"))["status"],
                "unattempted")
            self.assertEqual(
                wa.load_status(
                    status_path(tmp, loc="pt-BR", p="r1"))["status"],
                "unattempted")
            rids = [c["argv"][c["argv"].index("--run-id") + 1]
                    for c in fake.calls if "--run-id" in c["argv"]]
            self.assertFalse(any("ru-r2" in r or "pt-BR" in r for r in rids))
            bases = [c["argv"][c["argv"].index("--run-id-base") + 1]
                     for c in fake.calls if "--run-id-base" in c["argv"]]
            self.assertEqual(bases, ["iphone69-en"])
            self.assertTrue(summary_path(tmp).is_file())

    def test_finalize_rc3_is_honest_not_fatal(self):
        def handler(argv, n, calls):
            if argv[2] == "finalize-run":
                return 3, "{}\n", "needs-inspection: la-lock pending"
            if argv[2] == "finalize-two-runs":
                return 3, "{}\n", "needs-inspection: variance"
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 0)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="en", p="r1"))
            self.assertEqual(rec["status"], "ok")
            self.assertIn("needs-inspection", rec["reason"])

    def test_finalize_two_runs_fatal_records_pair_continues(self):
        def handler(argv, n, calls):
            if argv[2] == "finalize-two-runs":
                i = argv.index("--run-id-base")
                if argv[i + 1] == "iphone69-en":
                    return 2, "", "failed: semantic mismatch"
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, summary = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 1)
            self.assertIn("finalize-two-runs",
                          [c["argv"][2] for c in fake.calls
                           if "--run-id-base" in c["argv"]
                           and "iphone69-ru" in c["argv"][
                               c["argv"].index("--run-id-base") + 1]])
            self.assertEqual(summary["pairs"]["en"]["two_runs_rc"], 2)
            self.assertEqual(summary["pairs"]["ru"]["two_runs_rc"], 0)


class LaunchFailureTests(unittest.TestCase):
    def test_oserror_mid_locale_contaminates(self):
        def handler(argv, n, calls):
            if argv[2] == "run-session" and "--domain" in argv:
                i = argv.index("--run-id")
                if argv[i + 1] == "iphone69-ru-r1":
                    raise FileNotFoundError("capture.py vanished")
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 1)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="ru", p="r1"))
            self.assertEqual(rec["status"], "failed")
            self.assertIn("launch failed", rec["reason"])
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="ru", p="r2"))["status"],
                "unattempted")
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="en", p="r1"))["status"],
                "ok")
            self.assertTrue(summary_path(tmp).is_file())

    def test_timeout_mid_locale_contaminates(self):
        def handler(argv, n, calls):
            if argv[2] == "finalize-run":
                i = argv.index("--run-id")
                if argv[i + 1] == "iphone69-en-r2":
                    raise subprocess.TimeoutExpired(argv, 60)
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 1)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="en", p="r2"))
            self.assertEqual(rec["status"], "failed")
            self.assertIn("launch failed", rec["reason"])
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="ru", p="r1"))["status"],
                "unattempted")

    def test_keyboard_interrupt_propagates_after_statuses(self):
        def handler(argv, n, calls):
            if argv[2] == "run-session" and "--domain" in argv:
                argv2 = argv
                i = argv2.index("--domain")
                j = argv2.index("--run-id")
                if argv2[j + 1] == "iphone69-ru-r1" and argv2[i + 1] == "realtime":
                    raise KeyboardInterrupt()
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            with self.assertRaises(KeyboardInterrupt):
                execute(tmp, fake, locales=["en", "ru"])
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="ru", p="r1"))
            self.assertEqual(rec["status"], "failed")
            self.assertIn("interrupted", rec["reason"])
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="ru", p="r2"))["status"],
                "unattempted")
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="en", p="r1"))["status"],
                "ok")
            self.assertTrue(summary_path(tmp).is_file())


class SummaryWriteTests(unittest.TestCase):
    def _block_summary(self, tmp):
        summary_path(tmp).parent.mkdir(parents=True, exist_ok=True)
        summary_path(tmp).mkdir(exist_ok=True)

    def test_unwritable_summary_demotes_success_visibly(self):
        with tempfile.TemporaryDirectory() as tmp:
            self._block_summary(tmp)
            fake = FakeRun(ok_handler)
            code, summary = execute(tmp, fake, locales=["en"])
            self.assertEqual(code, 1)
            self.assertTrue(summary["error"])
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="en", p="r1"))
            self.assertEqual(rec["status"], "ok")

    def test_unwritable_summary_preserves_failure(self):
        def handler(argv, n, calls):
            if argv[2] == "run-session":
                return 2, "", "failed: boom"
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            self._block_summary(tmp)
            fake = FakeRun(handler)
            code, summary = execute(tmp, fake, locales=["en"])
            self.assertEqual(code, 1)
            self.assertTrue(summary["error"])
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="en", p="r1"))
            self.assertEqual(rec["status"], "failed")


class CancelTests(unittest.TestCase):
    def test_pre_cancelled_marks_all_unattempted(self):
        with tempfile.TemporaryDirectory() as tmp:
            cancel = Path(tmp) / "cancel"
            cancel.write_text("stop", encoding="utf-8")
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"],
                              cancel_file=str(cancel))
            self.assertEqual(code, 4)
            self.assertEqual(fake.calls, [])
            import workflow_artifacts as wa
            for loc in ("en", "ru"):
                for p in ("r1", "r2"):
                    rec = wa.load_status(status_path(tmp, loc=loc, p=p))
                    self.assertEqual(rec["status"], "unattempted")
                    self.assertIn("cancel", rec["reason"])

    def test_mid_run_cancel_stops_cleanly(self):
        def handler(argv, n, calls):
            if argv[2] == "run-session" and len(calls) == 4:
                Path(cancel_path[0]).write_text("stop", encoding="utf-8")
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            cancel_path = [str(Path(tmp) / "cancel")]
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"],
                              cancel_file=cancel_path[0])
            self.assertEqual(code, 4)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="en", p="r1"))
            self.assertEqual(rec["status"], "ok")
            rec2 = wa.load_status(status_path(tmp, loc="ru", p="r1"))
            self.assertEqual(rec2["status"], "unattempted")


class SetupTests(unittest.TestCase):
    def test_lease_required_before_any_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            env = dict(os.environ)
            env.pop("LIFIO_CAPTURE_LEASE", None)
            code, _ = execute(tmp, fake, env=env)
            self.assertEqual(code, 2)
            self.assertEqual(fake.calls, [])

    def test_booted_and_repo_out_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake, device_udid="booted")
            self.assertEqual(code, 2)
            self.assertEqual(fake.calls, [])
            repo = str(HERE.parent.parent)
            code, _ = execute(tmp, fake, out_dir=Path(repo) / "shots-x")
            self.assertEqual(code, 2)

    def test_empty_and_duplicate_locales_rejected_before_side_effects(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, summary = execute(tmp, fake, locales=[])
            self.assertEqual(code, 2)
            self.assertTrue(summary["error"])
            code, _ = execute(tmp, fake, locales=["en", "en"])
            self.assertEqual(code, 2)
            self.assertEqual(fake.calls, [])
            self.assertFalse((Path(tmp) / "shots").exists())

    def test_capacity_note_is_honest(self):
        cap = wdw.describe_capacity(
            ["iphone69", "iphone63", "ipad13", "iphone65", "iphone66",
             "iphone67"])
        self.assertEqual(cap["worker_count"], 6)
        self.assertEqual(cap["max_parallel"], 5)
        self.assertEqual(cap["excess"], 1)
        self.assertIn("GitHub", cap["note"])
        self.assertIn("not proven here", cap["note"])

    def test_missing_provenance_is_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake,
                              provenance=str(Path(tmp) / "nope.json"))
            self.assertEqual(code, 2)
            self.assertEqual(fake.calls, [])


class ApprovalGateTests(unittest.TestCase):
    APPROVAL = "/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot/approval-pilot27-r2.json"
    RETAINED = "/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot/runs/pilot27-r2"

    def _gated_handler(self, argv, n, calls):
        # Mirrors capture.py gates: non-English/iPad runs need the
        # approval pair; nothing auto-opens them (no CI bypass here).
        if argv[2] == "make-request":
            locale = argv[argv.index("--locale") + 1]
            Path(argv[argv.index("--out") + 1]).write_text(
                json.dumps({"locale": locale}), encoding="utf-8")
            return 0, "{}\n", ""
        base = None
        for i, a in enumerate(argv):
            if a == "--request":
                base = argv[i + 1]
        needs = base is not None and (
            '"locale": "ru"' in Path(base).read_text(encoding="utf-8")
            or "2064x2752" in argv[argv.index("--geometry") + 1])
        has_pair = "--approval" in argv and "--retained-dir" in argv
        if needs and not has_pair:
            return 2, "", "blocked: 5.4 owner approval is the only key"
        return 0, "{}\n", ""

    def test_gated_child_receives_pair_and_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            # Synthetic pair: the worker only gates on pair presence +
            # existence (content is owned by capture.py), so never depend
            # on the real owner approval under Pictures/ here.
            approval = Path(tmp) / "approval.json"
            approval.write_text(json.dumps({"approved": True}),
                                encoding="utf-8")
            retained = Path(tmp) / "retained"
            retained.mkdir(parents=True, exist_ok=True)
            fake = FakeRun(self._gated_handler)
            code, _ = execute(tmp, fake, locales=["ru"],
                              approval=str(approval),
                              retained_dir=str(retained))
            self.assertEqual(code, 0)
            sessions = fake.argv_for("run-session")
            self.assertEqual(len(sessions), 4)
            for argv in sessions:
                self.assertEqual(
                    argv[argv.index("--approval") + 1], str(approval))
                self.assertEqual(
                    argv[argv.index("--retained-dir") + 1], str(retained))

    def test_absent_pair_still_blocks_gated_locale(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(self._gated_handler)
            code, _ = execute(tmp, fake, locales=["ru"])
            self.assertEqual(code, 1)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="ru", p="r1"))
            self.assertEqual(rec["status"], "failed")
            self.assertIn("blocked", rec["reason"])

    def test_unpaired_or_missing_inputs_invalid_before_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            for kw in ({"approval": self.APPROVAL},
                       {"retained_dir": self.RETAINED},
                       {"approval": str(Path(tmp) / "nope.json"),
                        "retained_dir": self.RETAINED},
                       {"approval": self.APPROVAL,
                        "retained_dir": str(Path(tmp) / "nodir")}):
                with self.subTest(kw=kw):
                    fake = FakeRun(self._gated_handler)
                    code, summary = execute(tmp, fake, locales=["en"], **kw)
                    self.assertEqual(code, 2)
                    self.assertTrue(summary["error"])
                    self.assertEqual(fake.calls, [])

    def test_no_ci_bypass_in_worker(self):
        import re
        src = Path(__file__).resolve().parent.parent / "run_device_worker.py"
        text = src.read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(r"getenv\(['\"]LIFIO_CAPTURE_CI|"
                      r"environ(?:\.get)?\[['\"]LIFIO_CAPTURE_CI|"
                      r"CI_BYPASS", text))
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(self._gated_handler)
            env = base_env()
            env["LIFIO_CAPTURE_CI"] = "1"
            code, _ = execute(tmp, fake, locales=["ru"], env=env)
            self.assertEqual(code, 1)
            for c in fake.calls:
                self.assertNotIn("--approval", c["argv"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
