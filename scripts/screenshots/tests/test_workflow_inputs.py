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


def _parse_panels_source(src: str) -> dict:
    """Parse MATRIX_DEVICES keys + LOCALES from builder source as data.

    Keys-only minimization: MATRIX_DEVICES values are NEVER evaluated
    (they legitimately reference static asset constants such as
    APPLE_ASSET_69, which ast.literal_eval cannot resolve). Only the
    dict keys are extracted, each required to be a non-empty string
    literal; any dynamic shape (Name/JoinedStr/Call keys, ** unpacking,
    non-Dict assignment) fails closed. LOCALES is a plain string
    tuple/list literal evaluated for exact order. No import, no exec,
    no Pillow.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError as exc:
        raise AssertionError(f"panels builder source unparsable: {exc}")
    found: dict = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if not (isinstance(target, ast.Name) and target.id in (
                    "MATRIX_DEVICES", "LOCALES")):
                continue
            if target.id == "LOCALES":
                try:
                    val = ast.literal_eval(node.value)
                except (ValueError, SyntaxError) as exc:
                    raise AssertionError(
                        f"panels LOCALES is not a literal: {exc}")
                if not isinstance(val, (tuple, list)) or not val \
                        or not all(isinstance(v, str) and v for v in val):
                    raise AssertionError(
                        "panels LOCALES must be a non-empty tuple/list "
                        "of strings")
                found[target.id] = tuple(val)
            else:
                if not isinstance(node.value, ast.Dict):
                    raise AssertionError(
                        "panels MATRIX_DEVICES must be a dict literal "
                        "(dynamic shapes refused)")
                keys: list = []
                for k in node.value.keys:
                    if k is None:
                        raise AssertionError(
                            "panels MATRIX_DEVICES uses ** unpacking "
                            "(dynamic, refused)")
                    if not (isinstance(k, ast.Constant)
                            and isinstance(k.value, str) and k.value):
                        raise AssertionError(
                            "panels MATRIX_DEVICES has a non-literal key "
                            f"{ast.dump(k)[:80]} (refused)")
                    keys.append(k.value)
                if not keys:
                    raise AssertionError(
                        "panels MATRIX_DEVICES must be non-empty")
                if len(set(keys)) != len(keys):
                    raise AssertionError(
                        f"panels MATRIX_DEVICES has duplicate keys {keys}")
                found[target.id] = set(keys)
    if set(found) != {"MATRIX_DEVICES", "LOCALES"}:
        raise AssertionError(
            "panels builder catalog literals not found (MATRIX_DEVICES/LOCALES)")
    return found


def _panels_catalog():
    """Read MATRIX_DEVICES keys + LOCALES from scripts/panels/builder.py.

    The panels builder requires Pillow at import time, which the
    ubuntu tooling-tests job intentionally lacks (stdlib-only lane;
    Pillow installs live only in the macOS panels job). Parsing the
    catalog via ast keeps this parity gate stdlib-only without
    executing the builder and without evaluating asset values.
    """
    src = (HERE.parent / "panels" / "builder.py").read_text(
        encoding="utf-8")
    return _parse_panels_source(src)


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
        # Owner-provided portrait set (SDK-queried sim names, Xcode 27.1):
        # 17 Pro Max / 17 / iPad Pro 13 M5. Keys and canvases preserved;
        # canvases are NOT SDK-verified (devicetypes carry no dimensions).
        self.assertEqual(wi.DEVICE_CATALOG["iphone69"]["sim"],
                         "iPhone 17 Pro Max")
        self.assertEqual(wi.DEVICE_CATALOG["iphone63"]["sim"], "iPhone 17")
        self.assertEqual(wi.DEVICE_CATALOG["ipad13"]["sim"],
                         "iPad Pro 13-inch (M5)")


class PanelsCatalogParsingTests(unittest.TestCase):
    def test_static_asset_names_accepted(self):
        src = (HERE.parent / "panels" / "builder.py").read_text(
            encoding="utf-8")
        # Pin: the builder legitimately references static asset constants
        # in MATRIX_DEVICES values; the keys-only parser must accept them.
        self.assertIn("APPLE_ASSET_69", src)
        parsed = _parse_panels_source(src)
        self.assertEqual(parsed["MATRIX_DEVICES"],
                         {"iphone69", "iphone63", "ipad13"})
        self.assertEqual(parsed["LOCALES"],
                         ("en", "ru", "zh-Hans", "es-419", "pt-BR"))

    def test_wrong_key_detected(self):
        src = ('MATRIX_DEVICES = {"iphone69": {"size": "6.9"},\n'
               '                    "iphone65": {"size": "x"}}\n'
               'LOCALES = ("en", "ru", "zh-Hans", "es-419", "pt-BR")\n')
        parsed = _parse_panels_source(src)
        self.assertIn("iphone65", parsed["MATRIX_DEVICES"])
        self.assertNotEqual(set(parsed["MATRIX_DEVICES"]),
                            set(wi.SUPPORTED_DEVICES))

    def test_dynamic_keys_refused(self):
        good_locales = 'LOCALES = ("en",)\n'
        bad_sources = [
            # Name key (variable, not a string literal).
            'MATRIX_DEVICES = {SOME_VAR: {"size": "6.9"}}\n' + good_locales,
            # JoinedStr key (f-string, dynamic).
            'MATRIX_DEVICES = {f"iphone{i}": {"size": "6.9"}}\n'
            + good_locales,
            # ** unpacking (None key in ast.Dict).
            'MATRIX_DEVICES = {**OTHER}\n' + good_locales,
            # Non-Dict assignment (Call).
            'MATRIX_DEVICES = make_devices()\n' + good_locales,
            # Non-Dict assignment (Name alias).
            'MATRIX_DEVICES = OTHER\n' + good_locales,
        ]
        for src in bad_sources:
            with self.subTest(src=src.splitlines()[0][:40]):
                with self.assertRaises(AssertionError):
                    _parse_panels_source(src)


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
