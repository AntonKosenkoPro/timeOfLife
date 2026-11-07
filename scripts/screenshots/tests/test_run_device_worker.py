#!/usr/bin/env python3
"""Device-worker outer-loop tests (thin loop only; fake subprocess).

Deterministic, no macOS work: a FakeRun scripts capture.py exit codes
and records argv/env. Covers single automated pass per locale with
per-locale out scoping matching the panels harvest layout, argv shape
incl. --device-key/--island agreement, fresh invocation run identity
per call (manual reruns never share run ids), exact run_id carriage
in status records plus exactly one manifest per clean pair, reused-
output refusal (no silent overwrite/merge), subset dispatch,
failed-locale contamination (earlier artifacts preserved, later pairs
unattempted), rc3 needs-inspection vs fatal, launch-exception
containment, KeyboardInterrupt boundary, summary-write visibility,
cancel, capacity honesty (no invented queue proof), provenance
forwarding, lease explicitness, and no sim create/install ownership.
No automatic second pass and no automatic comparison are invoked.
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
              "invocation_id": "fixedtest01",
              "run": fake, "env": base_env()}
    kwargs.update(over)
    return wdw.execute(**kwargs)


def rid_for(dev="iphone69", loc="en", p="r1", inv="fixedtest01"):
    return f"{dev}-{loc}-{p}-{inv}"


def status_path(tmp, dev="iphone69", loc="en", p="r1"):
    return Path(tmp) / "shots" / dev / loc / f"{dev}-{loc}-{p}.status.json"


def summary_path(tmp, dev="iphone69"):
    return Path(tmp) / "shots" / dev / "worker-summary.json"


def locale_of_rid(rid, dev="iphone69"):
    # run ids are <dev>-<locale>-r1-<invocation>; locales may contain
    # hyphens (es-419), so split from both anchored ends.
    assert rid.startswith(dev + "-")
    head, inv = rid.rsplit("-", 1)
    assert inv, rid
    head, p = head.rsplit("-", 1)
    assert p == "r1", rid
    return head[len(dev) + 1:]


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
                          + fake.argv_for("finalize-run")):
                verb = argv[2]
                out = Path(argv[argv.index("--out") + 1])
                loc = locale_of_rid(argv[argv.index("--run-id") + 1])
                self.assertEqual(out, shots / "iphone69" / loc, argv)
            # no automatic second pass and no automatic comparison run
            self.assertEqual(fake.argv_for("finalize-two-runs"), [])
            # fake CLI output landed exactly where panels harvest reads it:
            # shots/<device>/<locale>/runs/<rid>/run-manifest.json, with
            # exactly one manifest per clean pair (discovery, never a
            # hardcoded run id).
            for loc in ("en", "ru"):
                rid = rid_for(loc=loc)
                self.assertTrue(
                    (shots / "iphone69" / loc / "runs" / rid
                     / "run-manifest.json").is_file(), rid)
                manifests = list(
                    (shots / "iphone69" / loc / "runs").glob(
                        "*/run-manifest.json"))
                self.assertEqual(len(manifests), 1, loc)
                self.assertTrue(status_path(tmp, loc=loc).is_file())
                # the status record carries the exact actual run id
                import workflow_artifacts as wa
                rec = wa.load_status(status_path(tmp, loc=loc))
                self.assertEqual(rec["run_id"], rid)
            # device summary lives at the device root, not in one locale
            self.assertTrue(summary_path(tmp).is_file())
            self.assertFalse(
                (shots / "iphone69" / "en" / "worker-summary.json").exists())

class ArgvShapeTests(unittest.TestCase):
    def test_full_argv_sequence_subset(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 0)
            per_locale = ["make-request", "locale-totals",
                          "run-session", "run-session", "finalize-run"]
            self.assertEqual(fake.verbs(), per_locale + per_locale)

    def test_run_session_flags_agree_with_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            execute(tmp, fake, locales=["en"])
            pinned = fake.argv_for("run-session", "pinned")
            self.assertEqual(len(pinned), 1)
            argv = pinned[0]
            get = lambda flag: argv[argv.index(flag) + 1]
            self.assertEqual(get("--device"), "UDID-1")
            self.assertEqual(get("--device-key"), "iphone69")
            self.assertEqual(get("--geometry"), "1320x2868")
            self.assertEqual(get("--island"), "1")
            self.assertEqual(get("--run-id"), rid_for(loc="en"))
            self.assertEqual(
                Path(get("--out")), Path(tmp) / "shots" / "iphone69" / "en")
            self.assertIn("--pinned-totals", argv)
            self.assertIn("--request", argv)
            realtime = fake.argv_for("run-session", "realtime")
            self.assertEqual(len(realtime), 1)
            self.assertEqual(
                realtime[0][realtime[0].index("--run-id") + 1],
                rid_for(loc="en"))
            self.assertIn("--hold-open", realtime[0])
            self.assertNotIn("--hold-open", argv)

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
            self.assertEqual(len(finals), 1)
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
                if argv[i + 1] == rid_for(loc="ru"):
                    return 2, "", "failed: pinned session refused"
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, summary = execute(tmp, fake, locales=["en", "ru", "pt-BR"])
            self.assertEqual(code, 1)
            for loc in ("en", "ru", "pt-BR"):
                self.assertTrue(status_path(tmp, loc=loc).is_file(), loc)
            import workflow_artifacts as wa
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="ru"))["status"],
                "failed")
            self.assertEqual(
                wa.load_status(
                    status_path(tmp, loc="pt-BR"))["status"],
                "unattempted")
            rids = [c["argv"][c["argv"].index("--run-id") + 1]
                    for c in fake.calls if "--run-id" in c["argv"]]
            self.assertFalse(any("pt-BR" in r for r in rids))
            # no automatic comparison is ever invoked
            self.assertFalse(any("--run-id-base" in c["argv"]
                                 for c in fake.calls))
            self.assertTrue(summary_path(tmp).is_file())

    def test_finalize_rc3_is_honest_not_fatal(self):
        def handler(argv, n, calls):
            if argv[2] == "finalize-run":
                return 3, "{}\n", "needs-inspection: la-lock pending"
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 0)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="en"))
            self.assertEqual(rec["status"], "ok")
            self.assertIn("needs-inspection", rec["reason"])

class LaunchFailureTests(unittest.TestCase):
    def test_oserror_mid_locale_contaminates(self):
        def handler(argv, n, calls):
            if argv[2] == "run-session" and "--domain" in argv:
                i = argv.index("--run-id")
                if argv[i + 1] == rid_for(loc="ru"):
                    raise FileNotFoundError("capture.py vanished")
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 1)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="ru"))
            self.assertEqual(rec["status"], "failed")
            self.assertIn("launch failed", rec["reason"])
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="en"))["status"],
                "ok")
            self.assertTrue(summary_path(tmp).is_file())

    def test_timeout_mid_locale_contaminates(self):
        def handler(argv, n, calls):
            if argv[2] == "finalize-run":
                i = argv.index("--run-id")
                if argv[i + 1] == rid_for(loc="en"):
                    raise subprocess.TimeoutExpired(argv, 60)
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 1)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="en"))
            self.assertEqual(rec["status"], "failed")
            self.assertIn("launch failed", rec["reason"])
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="ru"))["status"],
                "unattempted")

    def test_keyboard_interrupt_propagates_after_statuses(self):
        def handler(argv, n, calls):
            if argv[2] == "run-session" and "--domain" in argv:
                argv2 = argv
                i = argv2.index("--domain")
                j = argv2.index("--run-id")
                if argv2[j + 1] == rid_for(loc="ru") and argv2[i + 1] == "realtime":
                    raise KeyboardInterrupt()
            return 0, "{}\n", ""

        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(handler)
            with self.assertRaises(KeyboardInterrupt):
                execute(tmp, fake, locales=["en", "ru"])
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp, loc="ru"))
            self.assertEqual(rec["status"], "failed")
            self.assertIn("interrupted", rec["reason"])
            self.assertEqual(
                wa.load_status(status_path(tmp, loc="en"))["status"],
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
                rec = wa.load_status(status_path(tmp, loc=loc))
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


class InvocationIdentityTests(unittest.TestCase):
    def test_fresh_identity_minted_per_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake1 = FakeRun(ok_handler)
            code1, summary1 = execute(
                tmp, fake1, locales=["en"],
                out_dir=Path(tmp) / "shots-a", invocation_id=None)
            fake2 = FakeRun(ok_handler)
            code2, summary2 = execute(
                tmp, fake2, locales=["en"],
                out_dir=Path(tmp) / "shots-b", invocation_id=None)
            self.assertEqual((code1, code2), (0, 0))
            inv1, inv2 = (summary1["invocation_id"],
                          summary2["invocation_id"])
            self.assertTrue(inv1 and inv2)
            self.assertNotEqual(inv1, inv2)
            # both run ids are namespaced, distinct, exact in statuses
            import workflow_artifacts as wa
            for inv, out in ((inv1, "shots-a"), (inv2, "shots-b")):
                rid = f"iphone69-en-r1-{inv}"
                rec = wa.load_status(
                    Path(tmp) / out / "iphone69" / "en"
                    / "iphone69-en-r1.status.json")
                self.assertEqual(rec["run_id"], rid)

    def test_explicit_invocation_id_used_and_validated(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, summary = execute(tmp, fake, locales=["en"],
                                    invocation_id="rerun-20261104")
            self.assertEqual(code, 0)
            self.assertEqual(summary["invocation_id"], "rerun-20261104")
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp))
            self.assertEqual(rec["run_id"],
                             "iphone69-en-r1-rerun-20261104")
            # hostile ids fail closed before any child runs
            for bad in ("../escape", "", "has space", "x" * 65, None.__class__):
                fake2 = FakeRun(ok_handler)
                code, summary = execute(
                    tmp, fake2, locales=["en"],
                    out_dir=Path(tmp) / "shots-bad",
                    invocation_id=bad)
                self.assertEqual(code, 2, bad)
                self.assertTrue(summary["error"], bad)
                self.assertEqual(fake2.calls, [], bad)

    def test_all_five_locales_emit_valid_fresh_run_ids(self):
        # Panels-consumer alignment (§9): every locale's canonical r1
        # status carries a fresh run id in the strict max-64
        # [A-Za-z0-9_-] shape — including hyphenated locales — so
        # find_matrix_run selects exactly one distinct actual run_id
        # per pair and manifest.run_id == dirname validates.
        import re
        import workflow_artifacts as wa
        import workflow_inputs as wi
        locales = list(wi.SUPPORTED_LOCALES)
        self.assertEqual(len(locales), 5)
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, summary = execute(tmp, fake, locales=locales)
            self.assertEqual(code, 0)
            seen = set()
            for loc in locales:
                rec = wa.load_status(status_path(tmp, loc=loc))
                self.assertEqual(
                    (rec["device"], rec["locale"], rec["pass"]),
                    ("iphone69", loc, "r1"))
                rid = rec["run_id"]
                self.assertRegex(rid, r"^[A-Za-z0-9_-]{1,64}$")
                self.assertEqual(
                    rid, f"iphone69-{loc}-r1-{summary['invocation_id']}")
                seen.add(rid)
            # one distinct run id per pair, all under one invocation
            self.assertEqual(len(seen), 5)

    def test_long_invocation_rejected_before_any_child_or_file(self):
        # Audit hole 1 (proven): the invocation piece alone fits
        # [A-Za-z0-9_-]{1,64}, but the composite run id
        # <device>-<locale>-r1-<invocation> can exceed 64 — e.g.
        # iphone69-zh-Hans-r1- (20 chars) + 64 chars = 84. The old
        # code only failed late in status_record, AFTER children ran.
        # Every selected actual run id must pre-validate before ANY
        # mkdir/spawn/mutation: reject 2 with zero children/files.
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "shots-fresh"
            fake = FakeRun(ok_handler)
            code, summary = execute(
                tmp, fake, locales=["zh-Hans"], out_dir=out,
                invocation_id="e" * 64)
            self.assertEqual(code, 2)
            self.assertTrue(summary["error"])
            self.assertEqual(fake.calls, [])
            self.assertFalse(out.exists())

    def test_boundary_length_invocation_accepted(self):
        # Composite of exactly 64 chars stays valid:
        # len("iphone69-en-r1-") == 15, so a 49-char invocation fits.
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, summary = execute(
                tmp, fake, locales=["en"], invocation_id="f" * 49)
            self.assertEqual(code, 0, summary.get("error"))
            self.assertEqual(summary["invocation_id"], "f" * 49)
            import workflow_artifacts as wa
            rec = wa.load_status(status_path(tmp))
            self.assertEqual(len(rec["run_id"]), 64)

    def test_requests_only_orphan_refused_byte_identical(self):
        # Audit hole 2 (proven): the old refusal saw only statuses and
        # runs/, so a requests-only orphan slipped through and
        # make-request overwrote the non-namespaced base request file.
        # ANY nonempty selected pair cell refuses before mutation, and
        # prior bytes are preserved exactly (never deleted/overwritten).
        with tempfile.TemporaryDirectory() as tmp:
            cell = Path(tmp) / "shots" / "iphone69" / "en" / "requests"
            cell.mkdir(parents=True)
            orphan = cell / "iphone69-en-base-request.json"
            orphan.write_bytes(b'{"locale": "en"}')
            before = orphan.read_bytes()
            fake = FakeRun(ok_handler)
            code, summary = execute(tmp, fake, locales=["en"])
            self.assertEqual(code, 2)
            self.assertIn("previous invocation", summary["error"])
            self.assertEqual(fake.calls, [])
            self.assertEqual(orphan.read_bytes(), before)

    def test_foreign_file_and_symlink_refused_untouched(self):
        # Diagnostics, foreign files, and symlinks (even dangling ones
        # that stat poorly) are prior output too: refuse, never mix.
        with tempfile.TemporaryDirectory() as tmp:
            cell = Path(tmp) / "shots" / "iphone69" / "en"
            cell.mkdir(parents=True)
            foreign = cell / "notes.txt"
            foreign.write_bytes(b"operator notes")
            link = cell / "dangling.link"
            link.symlink_to(Path(tmp) / "no-such-target")
            fake = FakeRun(ok_handler)
            code, summary = execute(tmp, fake, locales=["en"])
            self.assertEqual(code, 2)
            self.assertIn("previous invocation", summary["error"])
            self.assertEqual(fake.calls, [])
            self.assertEqual(foreign.read_bytes(), b"operator notes")
            self.assertTrue(link.is_symlink())

    def test_rerun_into_same_out_refused_without_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake1 = FakeRun(ok_handler)
            code, _ = execute(tmp, fake1, locales=["en", "ru"])
            self.assertEqual(code, 0)
            before = status_path(tmp).read_bytes()
            # same output root, fresh identity: must refuse, never merge
            fake2 = FakeRun(ok_handler)
            code, summary = execute(tmp, fake2, locales=["en", "ru"],
                                    invocation_id="fresh-rerun-02")
            self.assertEqual(code, 2)
            self.assertIn("previous invocation", summary["error"])
            self.assertEqual(fake2.calls, [])
            self.assertEqual(status_path(tmp).read_bytes(), before)
            # a genuinely fresh output root accepts the rerun
            fake3 = FakeRun(ok_handler)
            code, summary = execute(
                tmp, fake3, locales=["en", "ru"],
                out_dir=Path(tmp) / "shots-rerun",
                invocation_id="fresh-rerun-02")
            self.assertEqual(code, 0)
            self.assertEqual(summary["invocation_id"], "fresh-rerun-02")

    def test_no_automatic_comparison_in_source_or_calls(self):
        import re
        src = Path(__file__).resolve().parent.parent / "run_device_worker.py"
        text = src.read_text(encoding="utf-8")
        self.assertNotIn("finalize-two-runs", text)
        self.assertNotIn("two_runs", text)
        with tempfile.TemporaryDirectory() as tmp:
            fake = FakeRun(ok_handler)
            code, _ = execute(tmp, fake, locales=["en", "ru"])
            self.assertEqual(code, 0)
            self.assertNotIn("finalize-two-runs", fake.verbs())


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
            self.assertEqual(len(sessions), 2)
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
