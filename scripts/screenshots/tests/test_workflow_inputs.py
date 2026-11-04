#!/usr/bin/env python3
"""Early selection validation tests (task 6.1; tmpdirs only, no device).

Fail-closed: empty/unknown/duplicate/malformed/injection-shaped inputs
are rejected without evaluation. The default catalog is retained.
"""

import ast
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import workflow_inputs as wi


def _panels_catalog():
    """Read MATRIX_DEVICES/LOCALES from scripts/panels/builder.py as data.

    The panels builder requires Pillow at import time, which the
    ubuntu tooling-tests job intentionally lacks (stdlib-only lane;
    Pillow installs live only in the macOS panels job). Parsing the
    two catalog literals via ast keeps this parity gate stdlib-only
    without executing the builder.
    """
    src = (HERE.parent / "panels" / "builder.py").read_text(
        encoding="utf-8")
    found: dict = {}
    for node in ast.walk(ast.parse(src)):
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id in (
                    "MATRIX_DEVICES", "LOCALES"):
                found[target.id] = ast.literal_eval(node.value)
    if set(found) != {"MATRIX_DEVICES", "LOCALES"}:
        raise AssertionError(
            "panels builder catalog literals not found (MATRIX_DEVICES/LOCALES)")
    return found


INJECTION_SHAPES = [
    '"; rm -rf /; "',
    "$(touch /tmp/pwned)",
    "${{ secrets.FIGMA_API_KEY }}",
    "`id`",
    "__import__('os').system('id')",
    "iphone69;echo hi",
    "en\nrm -rf /",
    "iOS 27.0 && id",
]


class DefaultCatalogTests(unittest.TestCase):
    def test_defaults_retained(self):
        self.assertEqual(list(wi.DEFAULT_DEVICES),
                         ["iphone69", "iphone63", "ipad13"])
        self.assertEqual(list(wi.DEFAULT_LOCALES),
                         ["en", "ru", "zh-Hans", "es-419", "pt-BR"])
        self.assertEqual(wi.DEFAULT_RUNTIME, "iOS 27.0")

    def test_catalog_matches_single_sources(self):
        import request_schema as rs
        self.assertEqual(tuple(wi.SUPPORTED_LOCALES), tuple(rs.KNOWN_LOCALES))
        panels = _panels_catalog()
        self.assertEqual(set(wi.SUPPORTED_DEVICES),
                         set(panels["MATRIX_DEVICES"]))
        self.assertEqual(tuple(wi.SUPPORTED_LOCALES),
                         tuple(panels["LOCALES"]))

    def test_device_catalog_matches_workflow(self):
        self.assertEqual(wi.DEVICE_CATALOG["iphone69"]["geometry"], "1320x2868")
        self.assertEqual(wi.DEVICE_CATALOG["iphone63"]["geometry"], "1206x2622")
        self.assertEqual(wi.DEVICE_CATALOG["ipad13"]["geometry"], "2064x2752")
        self.assertEqual(wi.DEVICE_CATALOG["iphone69"]["island"], 1)
        self.assertEqual(wi.DEVICE_CATALOG["ipad13"]["island"], 0)


class DeviceSelectionTests(unittest.TestCase):
    def test_valid_subset_preserves_order(self):
        self.assertEqual(
            wi.parse_device_selection('["ipad13","iphone69"]'),
            ["ipad13", "iphone69"])

    def test_empty_rejected(self):
        for raw in ("", "[]", '[""]', '[" "]', "null", '"iphone69"'):
            with self.subTest(raw=raw):
                with self.assertRaises(wi.InputError):
                    wi.parse_device_selection(raw)

    def test_unknown_rejected(self):
        for raw in ('["iphone65"]', '["IPHONE69"]', '["iphone69 "]',
                    '[" iphone69"]', '[""]'):
            with self.subTest(raw=raw):
                with self.assertRaises(wi.InputError):
                    wi.parse_device_selection(raw)

    def test_duplicates_rejected(self):
        with self.assertRaises(wi.InputError):
            wi.parse_device_selection('["iphone69","iphone69"]')

    def test_malformed_rejected(self):
        for raw in ("not-json", "[iphone69]", "{]", '["iphone69",]'):
            with self.subTest(raw=raw):
                with self.assertRaises(wi.InputError):
                    wi.parse_device_selection(raw)

    def test_non_string_elements_rejected(self):
        for raw in ('[1]', '[null]', '[["iphone69"]]', '[{"a":1}]'):
            with self.subTest(raw=raw):
                with self.assertRaises(wi.InputError):
                    wi.parse_device_selection(raw)

    def test_injection_shapes_rejected_without_evaluation(self):
        for shape in INJECTION_SHAPES:
            with self.subTest(shape=shape):
                raw = '["%s"]' % shape.replace('"', '\\"')
                with self.assertRaises(wi.InputError):
                    wi.parse_device_selection(raw)


class LocaleSelectionTests(unittest.TestCase):
    def test_valid_subset(self):
        self.assertEqual(wi.parse_locale_selection('["ru","en"]'), ["ru", "en"])

    def test_empty_unknown_duplicate_malformed_rejected(self):
        for raw in ("", "[]", '["xx"]', '["EN"]',
                    '["en","en"]', "not-json", "[en]", "[1]"):
            with self.subTest(raw=raw):
                with self.assertRaises(wi.InputError):
                    wi.parse_locale_selection(raw)

    def test_hyphenated_locales_accepted_exactly(self):
        got = wi.parse_locale_selection('["zh-Hans","es-419","pt-BR"]')
        self.assertEqual(got, ["zh-Hans", "es-419", "pt-BR"])

    def test_injection_shapes_rejected(self):
        for shape in INJECTION_SHAPES:
            with self.subTest(shape=shape):
                raw = '["%s"]' % shape.replace('"', '\\"')
                with self.assertRaises(wi.InputError):
                    wi.parse_locale_selection(raw)


class RuntimeTests(unittest.TestCase):
    def test_valid_runtime(self):
        self.assertEqual(wi.validate_runtime("iOS 27.0"), "iOS 27.0")

    def test_runtime_rejected(self):
        for raw in ("", "27.0", "iOS27.0", "iOS 27", "ios 27.0",
                    " android 15", "iOS 27.0; id"):
            with self.subTest(raw=raw):
                with self.assertRaises(wi.InputError):
                    wi.validate_runtime(raw)
        # surrounding whitespace is normalized, not rejected
        self.assertEqual(wi.validate_runtime("  iOS 27.0  "), "iOS 27.0")

    def test_runtime_injection_rejected(self):
        for shape in INJECTION_SHAPES:
            with self.subTest(shape=shape):
                with self.assertRaises(wi.InputError):
                    wi.validate_runtime(shape)


class SelectionSummaryTests(unittest.TestCase):
    def test_default_summary_counts(self):
        s = wi.validate_selection(
            '["iphone69","iphone63","ipad13"]',
            '["en","ru","zh-Hans","es-419","pt-BR"]', "iOS 27.0")
        self.assertEqual(s["worker_count"], 3)
        self.assertEqual(s["pair_count"], 15)
        # single automated pass per pair (§9): 15, not 30
        self.assertEqual(s["pass_count"], 15)

    def test_subset_summary(self):
        s = wi.validate_selection('["iphone69"]', '["en","ru"]', "iOS 27.0")
        self.assertEqual((s["worker_count"], s["pair_count"], s["pass_count"]),
                         (1, 2, 2))

    def test_single_pass_source(self):
        # PASSES is the single central pass constant (§9): exactly
        # ("r1",), shared by reference (no duplicate tuple), with the
        # summary count derived from it.
        self.assertEqual(wi.PASSES, ("r1",))
        self.assertEqual(wi.PASSES_PER_PAIR, 1)
        self.assertEqual(wi.PASSES_PER_PAIR, len(wi.PASSES))

    def test_island_flags(self):
        self.assertEqual(wi.island_for_device("iphone69"), 1)
        self.assertEqual(wi.island_for_device("iphone63"), 1)
        self.assertEqual(wi.island_for_device("ipad13"), 0)
        with self.assertRaises(wi.InputError):
            wi.island_for_device("iphone65")


if __name__ == "__main__":
    unittest.main(verbosity=2)
