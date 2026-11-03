#!/usr/bin/env python3
"""Request schema tests: pins, fail-closed enums, deterministic bytes."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import request_schema as rs


def base_request() -> dict:
    with open(HERE / "pilot_manifest.json", encoding="utf-8") as fh:
        base = json.load(fh)
    return {k: v for k, v in base.items() if k not in ("frame", "mode")}


def framed(frame: str = "track-running") -> dict:
    return rs.build_frame_request(base_request(), frame)


class PilotManifestTests(unittest.TestCase):
    def test_manifest_pins_totals_with_versioned_source(self):
        import json as _json
        base = base_request()
        self.assertEqual(base["deck_version"], "en-austin-1")
        self.assertEqual(base["locale"], "en")
        self.assertEqual(base["app_elapsed_s"], 754)
        totals = base["expected_totals"]
        self.assertEqual(
            _json.dumps(totals, sort_keys=True),
            _json.dumps(_json.loads(
                (HERE / "expected_totals.json").read_text(encoding="utf-8")),
                sort_keys=True),
        )
        self.assertEqual(len(totals["text_seconds"]), 27)
        self.assertEqual(sum(totals["text_seconds"].values()), totals["all_seconds"])
        self.assertEqual(totals["all_seconds"], 198600)
        self.assertEqual(totals["today_seconds"], 4500)
        self.assertEqual(totals["week_seconds"], 23100)
        self.assertEqual(totals["category_seconds"]["shot-cat-food"], 41400)
        self.assertEqual(len(totals["category_seconds"]), 7)
        self.assertIn("ScreenshotFixture.swift", base["totals_source"])
        self.assertNotIn("totals_status", base)

    def test_valid_per_frame_requests(self):
        for frame in rs.PILOT_FRAMES:
            errs = rs.validate_request_dict(framed(frame))
            self.assertEqual(errs, [], f"{frame}: {errs}")

    def test_frame_order_pinned(self):
        bad = framed()
        bad["frames"] = ["insights", "track-running", "history", "add-entry",
                         "la-lock", "la-compact", "la-expanded"]
        self.assertTrue(any("frames must be exactly" in e
                            for e in rs.validate_request_dict(bad)))

    def test_unknown_enums_rejected(self):
        for key, val in (("locale", "xx"), ("region", "XX"),
                         ("timezone", "Mars/Olympus"), ("deck_version", "en-x-9"),
                         ("treatment", "dark-v9"), ("calendar", "buddhist")):
            bad = framed()
            bad[key] = val
            errs = rs.validate_request_dict(bad)
            self.assertTrue(errs, f"{key}={val} must fail")

    def test_locale_pairing_mismatch(self):
        bad = framed()
        bad["region"] = "RU"  # en requires US/Chicago
        errs = rs.validate_request_dict(bad)
        self.assertTrue(any("mismatch" in e for e in errs))

    def test_mode_binding(self):
        for la_frame in rs.LA_FRAMES:
            bad = framed(la_frame)
            bad["mode"] = rs.MODE_PINNED
            errs = rs.validate_request_dict(bad)
            self.assertTrue(any("mode for frame" in e for e in errs),
                            f"{la_frame} must require realtime mode")
        for app_frame in rs.APP_CLOCK_FRAMES:
            bad = framed(app_frame)
            bad["mode"] = rs.MODE_REALTIME
            errs = rs.validate_request_dict(bad)
            self.assertTrue(any("mode for frame" in e for e in errs),
                            f"{app_frame} must require pinned mode")

    def test_missing_frame_rejected(self):
        bad = framed()
        del bad["frame"]
        self.assertTrue(rs.validate_request_dict(bad))

    def test_unknown_frame_rejected(self):
        with self.assertRaises(rs.RequestError):
            rs.build_frame_request(base_request(), "splash")

    def test_run_id_optional_but_shaped(self):
        ok = framed()
        ok["run_id"] = "pilot-r1"
        self.assertEqual(rs.validate_request_dict(ok), [])
        bad = framed()
        bad["run_id"] = "has space!"
        self.assertTrue(rs.validate_request_dict(bad))

    def test_canonical_bytes_deterministic_and_hashed(self):
        a = rs.canonical_bytes(framed("history"))
        b = rs.canonical_bytes(framed("history"))
        self.assertEqual(a, b)
        self.assertTrue(a.endswith(b"\n"))
        self.assertRegex(rs.request_sha256_of_bytes(a), r"^[0-9a-f]{64}$")
        c = rs.canonical_bytes(framed("insights"))
        self.assertNotEqual(a, c)

    def test_malformed_json_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            fh.write("{not json")
            path = fh.name
        with self.assertRaises(rs.RequestError):
            rs.load_request_file(path)


def localized_base(locale: str) -> dict:
    base = base_request()
    region, timezone = rs.LOCALE_PAIRING[locale]
    base["locale"] = locale
    base["region"] = region
    base["timezone"] = timezone
    base["keyboard"] = {"language": rs.KEYBOARD_FOR_LOCALE[locale],
                        "software_visible": True, "presentation": "docked"}
    return base


class LocalePinTests(unittest.TestCase):
    def test_all_five_totals_files_load(self):
        for locale in rs.KNOWN_LOCALES:
            with self.subTest(locale=locale):
                totals = rs.load_pinned_totals_for_locale(locale)
                self.assertEqual(len(totals["text_seconds"]), 27)
                self.assertEqual(sum(totals["text_seconds"].values()),
                                 totals["all_seconds"])
                self.assertEqual(totals["all_seconds"], 198600)
                self.assertEqual(totals["today_seconds"], 4500)
                self.assertEqual(totals["week_seconds"],
                                 rs.EXPECTED_WEEK_SECONDS[locale])
                self.assertEqual(len(totals["category_seconds"]), 7)
                self.assertEqual(totals["category_seconds"]["shot-cat-food"], 41400)

    def test_ru_week_differs_from_other_locales(self):
        self.assertEqual(rs.EXPECTED_WEEK_SECONDS["ru"], 12300)
        for locale in ("en", "zh-Hans", "es-419", "pt-BR"):
            self.assertEqual(rs.load_pinned_totals_for_locale(locale)["week_seconds"],
                             23100)
        self.assertEqual(rs.load_pinned_totals_for_locale("ru")["week_seconds"],
                         12300)

    def test_en_deck_file_matches_expected_totals(self):
        import json as _json
        deck_en = rs.load_pinned_totals_for_locale("en")
        expected = _json.loads(
            (HERE / "expected_totals.json").read_text(encoding="utf-8"))
        self.assertEqual(_json.dumps(deck_en, sort_keys=True),
                         _json.dumps(expected, sort_keys=True))

    def test_category_totals_identical_across_locales(self):
        import json as _json
        cats = [_json.dumps(rs.load_pinned_totals_for_locale(loc)["category_seconds"],
                            sort_keys=True) for loc in rs.KNOWN_LOCALES]
        self.assertEqual(len(set(cats)), 1)

    def test_unknown_locale_pin_rejected(self):
        with self.assertRaises(rs.RequestError):
            rs.load_pinned_totals_for_locale("xx")

    def test_keyboard_language_bound_to_locale(self):
        for locale in rs.KNOWN_LOCALES:
            with self.subTest(locale=locale):
                framed_req = rs.build_frame_request(localized_base(locale),
                                                    "track-running")
                self.assertEqual(rs.validate_request_dict(framed_req), [],
                                 f"{locale}: {rs.validate_request_dict(framed_req)}")
        # ru with pilot keyboard must fail; en with ru keyboard must fail
        bad = rs.build_frame_request(localized_base("ru"), "track-running")
        bad["keyboard"] = {"language": "en-US", "software_visible": True,
                           "presentation": "docked"}
        self.assertTrue(any("keyboard.language" in e
                            for e in rs.validate_request_dict(bad)))
        bad_en = framed()
        bad_en["keyboard"] = {"language": "ru-RU", "software_visible": True,
                              "presentation": "docked"}
        self.assertTrue(any("keyboard.language" in e
                            for e in rs.validate_request_dict(bad_en)))

    def test_geometry_allowlist(self):
        self.assertEqual(rs.parse_geometry("1320x2868"), (1320, 2868))
        self.assertEqual(rs.parse_geometry("1242x2688"), (1242, 2688))
        self.assertEqual(rs.parse_geometry("1206x2622"), (1206, 2622))
        self.assertEqual(rs.parse_geometry("2064x2752"), (2064, 2752))
        self.assertEqual(rs.MATRIX_GEOMETRIES[(1206, 2622)], "iphone-6.3")
        self.assertTrue(rs.is_pilot_geometry((1320, 2868)))
        self.assertFalse(rs.is_pilot_geometry((1206, 2622)))
        self.assertFalse(rs.is_pilot_geometry((2064, 2752)))
        with self.assertRaises(rs.RequestError):
            rs.parse_geometry("100x100")
        with self.assertRaises(rs.RequestError):
            rs.parse_geometry("not-a-geometry")


class MakeRequestBuilderTests(unittest.TestCase):
    def test_base_has_no_frame_or_mode(self):
        base = rs.build_base_request("en", (1320, 2868))
        self.assertNotIn("frame", base)
        self.assertNotIn("mode", base)

    def test_en_pilot_base_matches_pins(self):
        import json as _json
        base = rs.build_base_request("en", (1320, 2868))
        self.assertEqual(base["schema_version"], rs.SCHEMA_VERSION)
        self.assertEqual(base["deck_version"], rs.PILOT_DECK_VERSION)
        self.assertEqual(
            (base["locale"], base["region"], base["timezone"]),
            ("en", *rs.LOCALE_PAIRING["en"]),
        )
        self.assertEqual(base["calendar"], "gregorian")
        self.assertEqual(base["week_rule"], "locale-native")
        self.assertEqual(
            base["reference_local_iso"], rs.PILOT_REFERENCE_LOCAL_ISO)
        self.assertEqual(base["app_elapsed_s"], rs.PILOT_APP_ELAPSED_S)
        self.assertEqual(base["appearance"], rs.PILOT_APPEARANCE)
        self.assertEqual(base["dynamic_type"], rs.PILOT_DYNAMIC_TYPE)
        self.assertEqual(
            base["keyboard"],
            {"language": "en-US", "software_visible": True,
             "presentation": "docked"},
        )
        self.assertEqual(
            base["status_bar"],
            {"time": "9:41", "battery": 100, "network": "wifi"},
        )
        self.assertEqual(base["treatment"], rs.PILOT_TREATMENT)
        self.assertEqual(base["frames"], list(rs.PILOT_FRAMES))
        self.assertEqual(
            base["geometry"], {"width": 1320, "height": 2868})
        self.assertEqual(base["configuration"], rs.SCREENSHOT_CONFIGURATION)
        self.assertEqual(base["bundle_id"], rs.SCREENSHOT_BID)
        expected = _json.loads(
            (HERE / "expected_totals.json").read_text(encoding="utf-8"))
        self.assertEqual(
            _json.dumps(base["expected_totals"], sort_keys=True),
            _json.dumps(expected, sort_keys=True),
        )

    def test_all_locales_pairing_keyboard_totals_and_frames_validate(self):
        for locale in rs.KNOWN_LOCALES:
            with self.subTest(locale=locale):
                base = rs.build_base_request(locale, (1320, 2868))
                region, timezone = rs.LOCALE_PAIRING[locale]
                self.assertEqual(base["region"], region)
                self.assertEqual(base["timezone"], timezone)
                self.assertEqual(
                    base["keyboard"]["language"],
                    rs.KEYBOARD_FOR_LOCALE[locale],
                )
                self.assertEqual(
                    base["expected_totals"],
                    rs.load_pinned_totals_for_locale(locale),
                )
                for frame in rs.PILOT_FRAMES:
                    errs = rs.validate_request_dict(
                        rs.build_frame_request(base, frame))
                    self.assertEqual(errs, [], f"{locale}/{frame}: {errs}")

    def test_all_matrix_geometries_recorded(self):
        for geometry in rs.MATRIX_GEOMETRIES:
            with self.subTest(geometry=geometry):
                base = rs.build_base_request("en", geometry)
                self.assertEqual(
                    base["geometry"],
                    {"width": geometry[0], "height": geometry[1]},
                )

    def test_unknown_locale_rejected(self):
        with self.assertRaises(rs.RequestError):
            rs.build_base_request("xx", (1320, 2868))

    def test_unsupported_geometry_rejected(self):
        with self.assertRaises(rs.RequestError):
            rs.build_base_request("en", (100, 100))


class ArchiveToleranceTests(unittest.TestCase):
    """Decks/totals resolution survives `openspec archive`.

    Active change dir first, dated-archive fallback (never the reverse):
    a re-activated change shadows the archive.
    """

    def _make_root(self, tmp: str, *, active: bool = True,
                   archived: bool = True) -> str:
        import json as _json

        single = {"all_seconds": 1, "today_seconds": 1, "week_seconds": 1,
                  "category_seconds": {}, "text_seconds": {}}
        root = Path(tmp) / "repo"
        if active:
            d = (root / "openspec" / "changes" / rs.CHANGE_NAME / "decks")
            d.mkdir(parents=True)
            marked = dict(single, week_seconds=111)
            (d / "totals-en.json").write_text(
                _json.dumps(marked), encoding="utf-8")
        if archived:
            d = (root / "openspec" / "changes" / rs.ARCHIVED_CHANGE / "decks")
            d.mkdir(parents=True)
            marked = dict(single, week_seconds=222)
            (d / "totals-en.json").write_text(
                _json.dumps(marked), encoding="utf-8")
        return str(root)

    def test_candidate_order_active_first_archive_fallback(self):
        cands = [Path(p) for p in rs.candidate_decks_dirs("ROOT")]
        self.assertEqual(
            cands[0],
            Path("ROOT/openspec/changes/app-store-screenshot-pilot/decks"))
        self.assertEqual(
            cands[1],
            Path("ROOT/openspec/changes/archive/"
                 "2026-11-03-app-store-screenshot-pilot/decks"))

    def test_active_shadows_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._make_root(tmp, active=True, archived=True)
            path = rs.totals_path_for_locale("en", root)
            self.assertNotIn("archive", path)
            totals = rs.load_pinned_totals_for_locale("en", root)
            self.assertEqual(totals["week_seconds"], 111)

    def test_archive_fallback_when_active_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._make_root(tmp, active=False, archived=True)
            path = rs.totals_path_for_locale("en", root)
            self.assertIn("archive", path)
            totals = rs.load_pinned_totals_for_locale("en", root)
            self.assertEqual(totals["week_seconds"], 222)

    def test_neither_present_points_at_active_and_load_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._make_root(tmp, active=False, archived=False)
            path = rs.totals_path_for_locale("en", root)
            self.assertNotIn("archive", path)
            self.assertTrue(path.endswith("totals-en.json"))
            with self.assertRaises(rs.RequestError):
                rs.load_pinned_totals_for_locale("en", root)

    def test_real_repo_resolves_and_totals_source_names_resolved_file(self):
        from pathlib import Path as _Path

        path = rs.totals_path_for_locale("en")
        self.assertTrue(_Path(path).is_file(), path)
        decks = _Path(rs.decks_dir())
        self.assertTrue((decks / "totals-en.json").is_file())
        self.assertEqual(_Path(path).parent, decks)
        base = rs.build_base_request("en", (1320, 2868))
        rel = str(_Path(path).relative_to(_Path(rs._repo_root())))
        self.assertEqual(
            base["totals_source"], f"{rel} (deck {rs.PILOT_DECK_VERSION})")


if __name__ == "__main__":
    unittest.main(verbosity=2)
