#!/usr/bin/env python3
"""Per-locale artifact/status helper tests (task 6.6 helper only).

No workflow rewiring here: naming, hyphenated-locale parsing, explicit
failed/unattempted statuses, and worker summaries. Tmpdirs only.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import workflow_artifacts as wa


class NamingTests(unittest.TestCase):
    def test_names_for_full_matrix(self):
        for device in ("iphone69", "iphone63", "ipad13"):
            for locale in ("en", "ru", "zh-Hans", "es-419", "pt-BR"):
                with self.subTest(device=device, locale=locale):
                    name = wa.artifact_name(device, locale)
                    self.assertEqual(name, f"shots-{device}-{locale}")
                    dev, lang = wa.parse_artifact_name(name)
                    self.assertEqual((dev, lang), (device, locale))

    def test_hyphenated_locales_not_misrouted(self):
        dev, lang = wa.parse_artifact_name("shots-iphone69-es-419")
        self.assertEqual((dev, lang), ("iphone69", "es-419"))
        dev, lang = wa.parse_artifact_name("shots-ipad13-zh-Hans")
        self.assertEqual((dev, lang), ("ipad13", "zh-Hans"))

    def test_bad_names_rejected(self):
        for raw in ("", "shots-", "shots-iphone69", "shots-iphone65-en",
                    "shots-iphone69-xx", "other-iphone69-en", "shots-en"):
            with self.subTest(raw=raw):
                with self.assertRaises(wa.ArtifactError):
                    wa.parse_artifact_name(raw)
        with self.assertRaises(wa.ArtifactError):
            wa.artifact_name("iphone65", "en")
        with self.assertRaises(wa.ArtifactError):
            wa.artifact_name("iphone69", "xx")

    def test_artifact_dir_shape(self):
        d = wa.locale_artifact_dir(Path("/tmp/shots"), "iphone69", "ru")
        self.assertEqual(d, Path("/tmp/shots/iphone69/ru"))


class StatusTests(unittest.TestCase):
    def test_ok_needs_no_reason(self):
        rec = wa.status_record(device="iphone69", locale="en", pass_name="r1",
                               status="ok")
        self.assertEqual(rec["status"], "ok")
        self.assertEqual(rec["run_id"], "iphone69-en-r1")

    def test_failed_unattempted_require_reason(self):
        with self.assertRaises(wa.ArtifactError):
            wa.status_record(device="iphone69", locale="en", pass_name="r1",
                             status="failed", reason="  ")
        with self.assertRaises(wa.ArtifactError):
            wa.status_record(device="iphone69", locale="en", pass_name="r1",
                             status="unattempted")
        rec = wa.status_record(device="iphone69", locale="en", pass_name="r1",
                               status="failed", reason="boot timed out")
        self.assertEqual(rec["reason"], "boot timed out")

    def test_bad_enums_rejected(self):
        with self.assertRaises(wa.ArtifactError):
            wa.status_record(device="iphone69", locale="en", pass_name="r3",
                             status="ok")
        with self.assertRaises(wa.ArtifactError):
            wa.status_record(device="iphone69", locale="en", pass_name="r1",
                             status="green")

    def test_write_load_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            rec = wa.status_record(device="ipad13", locale="ru",
                                   pass_name="r2", status="failed",
                                   reason="simctl install refused")
            path = wa.write_status(Path(tmp), rec)
            self.assertTrue(path.is_file())
            self.assertEqual(wa.load_status(path), rec)

    def test_expected_passes(self):
        self.assertEqual(wa.expected_passes(), ("r1", "r2"))


class StatusBoundaryTests(unittest.TestCase):
    """write/load/status_path_for validate strict shape; hostile dicts
    never escape out_dir (repro: approved scratch repro-status.py)."""

    def _evil_records(self) -> list:
        base = {"schema_version": 1, "device": "iphone69", "locale": "en",
                "pass": "r1", "status": "ok", "reason": "",
                "run_id": "iphone69-en-r1"}
        variants = []
        for key, val in (
            ("device", "../evil"), ("device", "/abs"),
            ("device", "iphone69 "), ("device", 123),
            ("device", None), ("locale", "../../x"),
            ("locale", "en\n"), ("pass", "r1/../../y"),
            ("pass", "r3"), ("pass", None),
            ("status", "ok;rm"), ("status", "OK"), ("status", 0),
            ("reason", 123), ("reason", None),
            ("run_id", ""), ("run_id", 123), ("run_id", "../x"),
            ("schema_version", "1"), ("schema_version", 2),
            ("schema_version", True),
        ):
            rec = dict(base)
            rec[key] = val
            variants.append(rec)
        missing = dict(base)
        del missing["reason"]
        variants.append(missing)
        extra = dict(base)
        extra["note"] = "stowaway"
        variants.append(extra)
        denorm = dict(base, status="failed", reason="  padded  ")
        variants.append(denorm)
        return variants

    def test_hostile_records_rejected_without_writes(self):
        for rec in self._evil_records():
            with self.subTest(rec=rec):
                with tempfile.TemporaryDirectory() as tmp:
                    out = Path(tmp) / "out"
                    out.mkdir()
                    with self.assertRaises(wa.ArtifactError):
                        wa.write_status(out, rec)
                    self.assertEqual(list(out.iterdir()), [])
                    self.assertEqual(
                        [p for p in Path(tmp).rglob("*.status.json")], [])

    def test_non_dict_records_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            out.mkdir()
            for rec in (None, [], "x", 42):
                with self.subTest(rec=rec):
                    with self.assertRaises(wa.ArtifactError):
                        wa.write_status(out, rec)

    def test_status_path_for_validates(self):
        with self.assertRaises(wa.ArtifactError):
            wa.status_path_for(Path("/tmp/out"),
                               {"schema_version": 1, "device": "../evil",
                                "locale": "en", "pass": "r1", "status": "ok",
                                "reason": "", "run_id": "x"})
        rec = wa.status_record(device="iphone69", locale="es-419",
                               pass_name="r2", status="ok")
        self.assertEqual(
            wa.status_path_for(Path("/tmp/out"), rec),
            Path("/tmp/out/iphone69-es-419-r2.status.json"))

    def test_load_rejects_bad_shape(self):
        import json as _json
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.status.json"
            bad.write_text(_json.dumps({"schema_version": 1,
                                        "device": "../evil", "locale": "en",
                                        "pass": "r1", "status": "ok",
                                        "reason": "",
                                        "run_id": "x"}), encoding="utf-8")
            with self.assertRaises(wa.ArtifactError):
                wa.load_status(bad)
            malformed = Path(tmp) / "malformed.status.json"
            malformed.write_text("{not json", encoding="utf-8")
            with self.assertRaises(wa.ArtifactError):
                wa.load_status(malformed)
            notobj = Path(tmp) / "notobj.status.json"
            notobj.write_text("[]", encoding="utf-8")
            with self.assertRaises(wa.ArtifactError):
                wa.load_status(notobj)


class SummaryTests(unittest.TestCase):
    def _recs(self) -> list:
        return [
            wa.status_record(device="iphone69", locale="en", pass_name="r1",
                             status="ok"),
            wa.status_record(device="iphone69", locale="en", pass_name="r2",
                             status="ok"),
            wa.status_record(device="iphone69", locale="ru", pass_name="r1",
                             status="failed", reason="boot timed out"),
            wa.status_record(device="iphone69", locale="ru", pass_name="r2",
                             status="unattempted",
                             reason="stopped after r1 contamination"),
        ]

    def test_summarize_counts(self):
        s = wa.summarize_statuses(self._recs())
        self.assertEqual(s["counts"], {"ok": 2, "failed": 1, "unattempted": 1})
        self.assertEqual(len(s["failed"]), 1)
        self.assertEqual(len(s["unattempted"]), 1)

    def test_worker_summary_pair_completeness(self):
        s = wa.worker_summary("iphone69", ["en", "ru"], self._recs())
        by_pair = {(c["device"], c["locale"]): c["complete"]
                   for c in s["pairs"]}
        self.assertTrue(by_pair[("iphone69", "en")])
        self.assertFalse(by_pair[("iphone69", "ru")])
        # missing pair is explicitly incomplete, never invented
        s2 = wa.worker_summary("iphone69", ["en", "pt-BR"], self._recs())
        pt = [c for c in s2["pairs"] if c["locale"] == "pt-BR"][0]
        self.assertFalse(pt["complete"])
        self.assertEqual(pt["status"], "missing")


class StageUploadTests(unittest.TestCase):
    def test_stage_copies_summary_into_pair_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shots"
            pair = root / "iphone69" / "es-419"
            pair.mkdir(parents=True)
            (pair / "runs").mkdir()
            (root / "iphone69" / "worker-summary.json").write_text(
                '{"device": "iphone69"}', encoding="utf-8")
            out = wa.stage_pair_upload(root, "iphone69", "es-419")
            self.assertEqual(out, pair)
            self.assertTrue(
                (pair / "worker-summary.json").is_file())
            # idempotent: second staging keeps the same bytes
            out2 = wa.stage_pair_upload(root, "iphone69", "es-419")
            self.assertEqual(
                (pair / "worker-summary.json").read_text(encoding="utf-8"),
                '{"device": "iphone69"}')
            self.assertEqual(out2, pair)

    def test_stage_without_summary_still_returns_pair_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shots"
            out = wa.stage_pair_upload(root, "iphone69", "ru")
            self.assertEqual(out, root / "iphone69" / "ru")
            self.assertTrue(out.is_dir())

    def test_stage_rejects_unknown(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shots"
            with self.assertRaises(wa.ArtifactError):
                wa.stage_pair_upload(root, "iphone65", "en")
            with self.assertRaises(wa.ArtifactError):
                wa.stage_pair_upload(root, "iphone69", "xx")


class ReshardTests(unittest.TestCase):
    def _download_tree(self, root: Path) -> Path:
        # Faithful download-artifact nesting: shots/<artifact-name>/
        # holding the pair-dir payload (runs/, statuses, summary copy).
        dl = root / "shots"
        for dev, lang in (("iphone69", "en"), ("iphone69", "es-419"),
                          ("ipad13", "zh-Hans")):
            art = dl / f"shots-{dev}-{lang}"
            runs = art / "runs" / f"{dev}-{lang}-r1"
            runs.mkdir(parents=True)
            (runs / "run-manifest.json").write_text(
                json.dumps({"run_id": f"{dev}-{lang}-r1"}),
                encoding="utf-8")
            (art / f"{dev}-{lang}-r1.status.json").write_text(
                json.dumps({"status": "ok"}), encoding="utf-8")
            (art / "worker-summary.json").write_text("{}", encoding="utf-8")
        return dl

    def test_reshard_flattens_without_double_locale(self):
        import json as _json

        with tempfile.TemporaryDirectory() as tmp:
            dl = self._download_tree(Path(tmp))
            out = Path(tmp) / "flat"
            report = wa.reshard_downloaded_artifacts(dl, out)
            self.assertEqual(report["cells"], 3)
            self.assertEqual(report["manifests"], 3)
            for dev, lang in (("iphone69", "en"), ("iphone69", "es-419"),
                              ("ipad13", "zh-Hans")):
                cell = out / dev / lang
                self.assertTrue(
                    (cell / "runs" / f"{dev}-{lang}-r1"
                     / "run-manifest.json").is_file(), cell)
                # no doubled locale nesting: runs/ must sit directly in
                # the cell, never under cell/<locale>/runs/
                self.assertFalse((cell / lang).exists(), cell)
                self.assertTrue(
                    (cell / f"{dev}-{lang}-r1.status.json").is_file())
                self.assertTrue((cell / "worker-summary.json").is_file())

    def test_reshard_rejects_unknown_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            dl = Path(tmp) / "shots"
            (dl / "shots-iphone65-en").mkdir(parents=True)
            with self.assertRaises(wa.ArtifactError):
                wa.reshard_downloaded_artifacts(dl, Path(tmp) / "flat")

    def test_reshard_empty_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            dl = Path(tmp) / "shots"
            dl.mkdir()
            with self.assertRaises(wa.ArtifactError):
                wa.reshard_downloaded_artifacts(dl, Path(tmp) / "flat")


class BackfillTests(unittest.TestCase):
    def test_backfill_writes_only_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shots"
            loc = root / "iphone69" / "en"
            loc.mkdir(parents=True)
            rec = wa.status_record(device="iphone69", locale="en",
                                   pass_name="r1", status="ok")
            wa.write_status(loc, rec)
            created = wa.backfill_unattempted(
                root, "iphone69", ["en", "ru"], "worker never reached pair")
            # en-r1 preserved; en-r2 + ru-r1/r2 backfilled
            self.assertEqual(
                sorted((r["locale"], r["pass"]) for r in created),
                [("en", "r2"), ("ru", "r1"), ("ru", "r2")])
            for r in created:
                self.assertEqual(r["status"], "unattempted")
                self.assertEqual(r["reason"], "worker never reached pair")
            kept = wa.load_status(loc / "iphone69-en-r1.status.json")
            self.assertEqual(kept["status"], "ok")
            for loc_name, p in (("en", "r2"), ("ru", "r1"), ("ru", "r2")):
                got = wa.load_status(
                    root / "iphone69" / loc_name
                    / f"iphone69-{loc_name}-{p}.status.json")
                self.assertEqual(got["status"], "unattempted")

    def test_backfill_rejects_bad_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "shots"
            with self.assertRaises(wa.ArtifactError):
                wa.backfill_unattempted(root, "iphone65", ["en"], "x")
            with self.assertRaises(wa.ArtifactError):
                wa.backfill_unattempted(root, "iphone69", ["xx"], "x")
            with self.assertRaises(wa.ArtifactError):
                wa.backfill_unattempted(root, "iphone69", ["en"], "  ")


if __name__ == "__main__":
    unittest.main(verbosity=2)
