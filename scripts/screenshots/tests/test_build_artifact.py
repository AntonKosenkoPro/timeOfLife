#!/usr/bin/env python3
"""Shared-build artifact helper tests (tasks 6.2-6.4; tmpdirs only).

Covers: arm64-only slice inspection, locale/pass-independent build keys,
dependency-cache usability (normal build always runs; cache never
substitutes the final artifact), permission-preserving tar with safe
extraction (no bulk extract, no hardlinks, no outside-link following, no
preexisting-file mutation), full resource hashes incl. dir symlinks, the
realistic iOS .app layout with exact appex identities, and
provenance/toolchain/config mismatch incl. schema + bundle identities.
"""

import io
import os
import stat
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import build_artifact as ba


def _plist_bytes(exe: str, bid: str) -> bytes:
    return (
        b'<?xml version="1.0"?><plist><dict>'
        b'<key>CFBundleExecutable</key><string>' + exe.encode()
        + b'</string><key>CFBundleIdentifier</key><string>' + bid.encode()
        + b'</string></dict></plist>')


def _manifest(**over) -> dict:
    base = ba.build_manifest(
        commit="a" * 40, dirty=False, configuration="Screenshot",
        xcode_version="27.1", xcode_build="27A9275",
        sdk_version="27.1", sdk_build="24A94232",
        runtime_version="iOS 27.0", runtime_build="24A434",
        arch="arm64",
        app_sha256="a" * 64, extension_sha256="b" * 64,
        archive_sha256="c" * 64, bundle_id=ba.SCREENSHOT_BUNDLE_ID,
        extension_id=ba.SCREENSHOT_EXTENSION_ID)
    base.update(over)
    return base


def _manifest_kwargs(**over) -> dict:
    kwargs = {"expected_commit": "a" * 40, "expected_xcode": "27.1",
              "expected_xcode_build": "27A9275",
              "expected_sdk_version": "27.1",
              "expected_sdk_build": "24A94232",
              "expected_runtime_version": "iOS 27.0",
              "expected_runtime_build": "24A434",
              "expected_arch": "arm64",
              "expected_configuration": "Screenshot",
              "expected_bundle_id": ba.SCREENSHOT_BUNDLE_ID,
              "expected_extension_id": ba.SCREENSHOT_EXTENSION_ID}
    kwargs.update(over)
    return kwargs


def make_fake_app(root: Path, name: str = "TimeOfLife.app") -> Path:
    """Realistic iOS simulator .app: root Info.plist + executable, rel
    symlink, exact appex at PlugIns/LifioLiveActivities.appex with root
    Info.plist + executable (matches the observed Screenshot product)."""
    app = root / name
    app.mkdir(parents=True)
    binary = app / "TimeOfLife"
    binary.write_bytes(b"\xcf\xfa\xed\xfe" + b"\x00" * 64)
    binary.chmod(0o755)
    (app / "Info.plist").write_bytes(
        _plist_bytes("TimeOfLife", ba.SCREENSHOT_BUNDLE_ID))
    (app / "Assets.car").write_bytes(b"car-bytes")
    (app / "Assets.car").chmod(0o644)
    (app / "Asset-link").symlink_to("Assets.car")
    ext = app / "PlugIns" / ba.SCREENSHOT_APPEX_NAME
    (ext).mkdir(parents=True)
    ext_bin = ext / ba.SCREENSHOT_APPEX_EXECUTABLE
    ext_bin.write_bytes(b"\xcf\xfa\xed\xfe" + b"\x11" * 32)
    ext_bin.chmod(0o755)
    (ext / "Info.plist").write_bytes(
        _plist_bytes(ba.SCREENSHOT_APPEX_EXECUTABLE,
                     ba.SCREENSHOT_EXTENSION_ID))
    return app


def make_macos_app(root: Path, name: str = "Mac.app") -> Path:
    """macOS Contents/MacOS layout: must NOT verify as an iOS product."""
    app = root / name
    macos = app / "Contents" / "MacOS"
    macos.mkdir(parents=True)
    binary = macos / "TimeOfLife"
    binary.write_bytes(b"\xcf\xfa\xed\xfe")
    binary.chmod(0o755)
    (app / "Contents" / "Info.plist").write_bytes(
        _plist_bytes("TimeOfLife", ba.SCREENSHOT_BUNDLE_ID))
    return app


class IdentityConstantsTests(unittest.TestCase):
    def test_bundle_ids_match_runner_and_product(self):
        import request_schema as rs
        self.assertEqual(ba.SCREENSHOT_BUNDLE_ID, rs.SCREENSHOT_BID)
        self.assertEqual(ba.SCREENSHOT_EXTENSION_ID,
                         rs.SCREENSHOT_BID + ".liveactivities")
        self.assertEqual(ba.SCREENSHOT_APPEX_NAME, "LifioLiveActivities.appex")
        self.assertEqual(ba.SCREENSHOT_APPEX_EXECUTABLE, "LifioLiveActivities")

    def test_real_screenshot_product_verifies(self):
        import glob
        cands = glob.glob(str(
            Path.home() / "Library/Developer/Xcode/DerivedData/TimeOfLife-*"
            / "Build/Products/Screenshot-iphonesimulator/TimeOfLife.app"))
        if not cands:
            self.skipTest("no local Screenshot build product to inspect")
        app = Path(sorted(cands)[-1])
        self.assertEqual(ba.verify_app_structure(app), [])
        import plistlib
        with open(app / "Info.plist", "rb") as fh:
            info = plistlib.load(fh)
        with open(app / "PlugIns" / ba.SCREENSHOT_APPEX_NAME / "Info.plist",
                  "rb") as fh:
            ext = plistlib.load(fh)
        self.assertEqual(info["CFBundleIdentifier"], ba.SCREENSHOT_BUNDLE_ID)
        self.assertEqual(info["CFBundleExecutable"], "TimeOfLife")
        self.assertEqual(ext["CFBundleIdentifier"],
                         ba.SCREENSHOT_EXTENSION_ID)
        self.assertEqual(ext["CFBundleExecutable"],
                         ba.SCREENSHOT_APPEX_EXECUTABLE)


class ToolchainTests(unittest.TestCase):
    def test_parse_xcode_version(self):
        self.assertEqual(
            ba.parse_xcode_version("Xcode 27.1\nBuild version 17C00\n"), "27.1")
        self.assertEqual(ba.parse_xcode_version("Xcode 27.1.2"), "27.1.2")
        with self.assertRaises(ba.ArtifactError):
            ba.parse_xcode_version("no toolchain here")
        with self.assertRaises(ba.ArtifactError):
            ba.parse_xcode_version("")

    def test_parse_xcode_build(self):
        self.assertEqual(
            ba.parse_xcode_build("Xcode 27.1\nBuild version 17C00\n"), "17C00")
        with self.assertRaises(ba.ArtifactError):
            ba.parse_xcode_build("Xcode 27.1\n")
        with self.assertRaises(ba.ArtifactError):
            ba.parse_xcode_build("")

    def test_xcode_pin_exact(self):
        self.assertEqual(ba.validate_xcode_pin("27.1", "27.1"), [])
        self.assertTrue(ba.validate_xcode_pin("27.0", "27.1"))
        self.assertTrue(ba.validate_xcode_pin("", "27.1"))


class SliceTests(unittest.TestCase):
    def test_arm64_only_accepted(self):
        self.assertEqual(ba.parse_lipo_archs("arm64"), frozenset({"arm64"}))
        self.assertEqual(ba.parse_lipo_archs("  arm64\n"), frozenset({"arm64"}))
        self.assertEqual(ba.validate_slices(frozenset({"arm64"}),
                                            frozenset({"arm64"})), [])

    def test_universal_or_intel_rejected(self):
        self.assertTrue(ba.validate_slices(
            frozenset({"arm64", "x86_64"}), frozenset({"arm64"})))
        self.assertTrue(ba.validate_slices(
            frozenset({"x86_64"}), frozenset({"x86_64"})))
        self.assertTrue(ba.validate_slices(
            frozenset({"arm64"}), frozenset({"arm64", "x86_64"})))

    def test_empty_or_garbage_rejected(self):
        with self.assertRaises(ba.ArtifactError):
            ba.parse_lipo_archs("")
        with self.assertRaises(ba.ArtifactError):
            ba.parse_lipo_archs("   \n")
        with self.assertRaises(ba.ArtifactError):
            ba.parse_lipo_archs("arm64; rm -rf /")


class BuildKeyTests(unittest.TestCase):
    def _key(self) -> str:
        return ba.build_key(commit="a" * 40, xcode_version="27.1",
                            xcode_build="27A9275",
                            sdk_version="27.1", sdk_build="24A94232",
                            arch="arm64", configuration="Screenshot")

    def test_key_deterministic_hex(self):
        self.assertRegex(self._key(), r"^[0-9a-f]{64}$")
        self.assertEqual(self._key(), self._key())

    def test_key_independent_of_device_locale_pass(self):
        # No per-locale/pass rebuild: locale/pass/device are not key inputs
        # at all (signature-level proof, not just equal outputs).
        import inspect
        params = set(inspect.signature(ba.build_key).parameters)
        self.assertFalse({"device", "locale", "pass", "run_id"} & params)
        self.assertEqual(self._key(), self._key())

    def test_key_changes_with_inputs(self):
        others = [
            self._key_with(xcode_version="27.0"),
            self._key_with(xcode_build="27A9999"),
            self._key_with(arch="x86_64"),
            self._key_with(configuration="Release"),
            self._key_with(commit="b" * 40),
            self._key_with(sdk_version="27.0"),
            self._key_with(sdk_build="24A9999"),
        ]
        for other in others:
            self.assertNotEqual(self._key(), other)

    def _key_with(self, **over) -> str:
        kwargs = {"commit": "a" * 40, "xcode_version": "27.1",
                  "xcode_build": "27A9275",
                  "sdk_version": "27.1", "sdk_build": "24A94232",
                  "arch": "arm64", "configuration": "Screenshot"}
        kwargs.update(over)
        return ba.build_key(**kwargs)


class CacheTests(unittest.TestCase):
    def test_cache_key_deterministic_and_sensitive(self):
        k1 = ba.dependency_cache_key({"Package.resolved": "a" * 64},
                                     "27.1", "27A9275", "27.1", "24A94232",
                                     "arm64", "Screenshot")
        k2 = ba.dependency_cache_key({"Package.resolved": "a" * 64},
                                     "27.1", "27A9275", "27.1", "24A94232",
                                     "arm64", "Screenshot")
        self.assertEqual(k1, k2)
        k3 = ba.dependency_cache_key({"Package.resolved": "b" * 64},
                                     "27.1", "27A9275", "27.1", "24A94232",
                                     "arm64", "Screenshot")
        self.assertNotEqual(k1, k3)
        # exact toolchain/SDK build IDs are key inputs: a rebuilt
        # toolchain re-keys instead of restoring stale checkouts
        k4 = ba.dependency_cache_key({"Package.resolved": "a" * 64},
                                     "27.1", "27A9999", "27.1", "24A94232",
                                     "arm64", "Screenshot")
        self.assertNotEqual(k1, k4)
        k5 = ba.dependency_cache_key({"Package.resolved": "a" * 64},
                                     "27.1", "27A9275", "27.1", "24A9999",
                                     "arm64", "Screenshot")
        self.assertNotEqual(k1, k5)
        with self.assertRaises(ba.ArtifactError):
            ba.dependency_cache_key({}, "27.1", "27A9275", "27.1",
                                    "24A94232", "arm64", "Screenshot")

    def test_cold_miss_is_not_usable(self):
        self.assertFalse(ba.cache_usable(False, []))

    def test_incompatible_hit_is_not_usable(self):
        cached = _manifest()
        errs = ba.check_cache_hit_usable(cached, **_manifest_kwargs(
            expected_commit="b" * 40))
        self.assertTrue(errs)
        self.assertFalse(ba.cache_usable(True, errs))

    def test_compatible_hit_is_usable_but_never_substitutes_build(self):
        # Usable means dependency restore may proceed; the docstring-level
        # contract (asserted here via API shape) is that no helper returns
        # a loose app: the only install path still requires a normal build
        # + fresh manifest verification. cache_usable returns a bool, never
        # an artifact path or manifest.
        cached = _manifest()
        errs = ba.check_cache_hit_usable(cached, **_manifest_kwargs())
        self.assertEqual(errs, [])
        usable = ba.cache_usable(True, errs)
        self.assertTrue(usable)
        self.assertIsInstance(usable, bool)

    def test_no_rebuild_shortcut_api(self):
        # Design: the normal build always runs after cache restore, so no
        # "skip the build" decision helper may exist.
        self.assertFalse(hasattr(ba, "needs_rebuild"))

    def test_no_speculative_source_cache(self):
        self.assertFalse(hasattr(ba, "source_fingerprint"))

    def test_each_identity_mismatch_rejected(self):
        base = _manifest_kwargs()
        for field, override in (
            ("arch", {"expected_arch": "x86_64"}),
            ("xcode", {"expected_xcode": "26.0"}),
            ("xcode_build", {"expected_xcode_build": "27A9999"}),
            ("configuration", {"expected_configuration": "Release"}),
            ("sdk_version", {"expected_sdk_version": "27.0"}),
            ("sdk_build", {"expected_sdk_build": "24A9999"}),
            ("runtime_version", {"expected_runtime_version": "iOS 18.6"}),
            ("runtime_build", {"expected_runtime_build": "22G86"}),
            ("commit", {"expected_commit": "b" * 40}),
            ("bundle", {"expected_bundle_id": "com.example.other"}),
            ("extension", {"expected_extension_id": "com.example.other"}),
        ):
            with self.subTest(field=field):
                cached = _manifest()
                kwargs = dict(base)
                kwargs.update(override)
                self.assertTrue(
                    ba.check_cache_hit_usable(cached, **kwargs), field)


class ManifestTests(unittest.TestCase):
    def test_round_trip_and_verify(self):
        m = _manifest()
        self.assertEqual(ba.verify_manifest(m, **_manifest_kwargs()), [])

    def test_mismatches_each_reported(self):
        cases = [
            ({"commit": "b" * 40}, "commit"),
            ({"configuration": "Release"}, "configuration"),
            ({"arch": "x86_64"}, "arch"),
            ({"xcode_version": "26.0"}, "xcode"),
            ({"xcode_build": "27A9999"}, "xcode_build"),
            ({"sdk_version": "27.0"}, "sdk_version"),
            ({"sdk_build": "24A9999"}, "sdk_build"),
            ({"runtime_version": "iOS 18.6"}, "runtime_version"),
            ({"runtime_build": "22G86"}, "runtime_build"),
            ({"bundle_id": "com.example.other"}, "bundle_id"),
            ({"extension_id": "com.example.other"}, "extension_id"),
            ({"schema_version": 999}, "schema_version"),
            ({"app_sha256": "zz"}, "app_sha"),
            ({"archive_sha256": ""}, "archive"),
            ({"dirty": "yes"}, "dirty"),
        ]
        for over, label in cases:
            with self.subTest(label=label):
                m = _manifest(**over)
                self.assertTrue(
                    ba.verify_manifest(m, **_manifest_kwargs()), label)

    def test_malformed_shapes_rejected(self):
        self.assertTrue(ba.verify_manifest([], **_manifest_kwargs()))
        self.assertTrue(ba.verify_manifest({}, **_manifest_kwargs()))
        self.assertTrue(ba.verify_manifest(
            {"schema_version": 1}, **_manifest_kwargs()))

    def test_toolchain_build_fields_required(self):
        # SDK/runtime build IDs are REQUIRED provenance (wiring pins the
        # exact toolchain); a manifest that cannot name its builds is
        # unbuildable and unverifiable.
        with self.assertRaises((TypeError, ba.ArtifactError)):
            ba.build_manifest(
                commit="a" * 40, dirty=False, configuration="Screenshot",
                xcode_version="27.1", arch="arm64",
                app_sha256="a" * 64, extension_sha256="b" * 64,
                archive_sha256="c" * 64, bundle_id=ba.SCREENSHOT_BUNDLE_ID,
                extension_id=ba.SCREENSHOT_EXTENSION_ID)
        m = _manifest()
        for field in ("xcode_build", "sdk_version", "sdk_build",
                      "runtime_version", "runtime_build"):
            self.assertTrue(m[field], field)
        self.assertTrue(ba.verify_manifest(m, **_manifest_kwargs(
            expected_xcode_build="27A9999")))
        self.assertTrue(ba.verify_manifest(m, **_manifest_kwargs(
            expected_sdk_build="24A9999")))
        self.assertTrue(ba.verify_manifest(m, **_manifest_kwargs(
            expected_runtime_build="22G86")))

    def test_resources_round_trip_and_verify(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = make_fake_app(Path(tmp))
            hashes = ba.resource_hashes(app)
            m = _manifest(resources={
                "files": dict(hashes["files"]),
                "symlinks": dict(hashes["symlinks"])})
            self.assertEqual(ba.verify_manifest(m, **_manifest_kwargs()), [])
            res = m["resources"]
            self.assertEqual(ba.verify_hashes(
                app, res["files"], res["symlinks"]), [])
            (app / "Assets.car").write_bytes(b"tampered")
            self.assertTrue(ba.verify_hashes(
                app, res["files"], res["symlinks"]))
        with self.assertRaises(ba.ArtifactError):
            ba.build_manifest(
                commit="a" * 40, dirty=False, configuration="Screenshot",
                xcode_version="27.1", xcode_build="27A9275",
                sdk_version="27.1", sdk_build="24A94232",
                runtime_version="iOS 27.0", runtime_build="24A434",
                arch="arm64",
                app_sha256="a" * 64, extension_sha256="b" * 64,
                archive_sha256="c" * 64, bundle_id=ba.SCREENSHOT_BUNDLE_ID,
                extension_id=ba.SCREENSHOT_EXTENSION_ID,
                resources={"files": "nope"})
        with self.assertRaises(ba.ArtifactError):
            ba.build_manifest(
                commit="a" * 40, dirty=False, configuration="Screenshot",
                xcode_version="27.1", xcode_build="27A9275",
                sdk_version="27.1", sdk_build="24A94232",
                runtime_version="iOS 27.0", runtime_build="24A434",
                arch="arm64",
                app_sha256="a" * 64, extension_sha256="b" * 64,
                archive_sha256="c" * 64, bundle_id=ba.SCREENSHOT_BUNDLE_ID,
                extension_id=ba.SCREENSHOT_EXTENSION_ID,
                resources={"files": {}, "extra": 1})

    def test_dirty_must_be_bool(self):
        with self.assertRaises(ba.ArtifactError):
            ba.build_manifest(commit="a" * 40, dirty="yes",
                              configuration="Screenshot", xcode_version="27.1",
                              xcode_build="27A9275",
                              sdk_version="27.1", sdk_build="24A94232",
                              runtime_version="iOS 27.0",
                              runtime_build="24A434", arch="arm64",
                              app_sha256="a" * 64, extension_sha256="b" * 64,
                              archive_sha256="c" * 64,
                              bundle_id=ba.SCREENSHOT_BUNDLE_ID,
                              extension_id=ba.SCREENSHOT_EXTENSION_ID)

    def test_strict_config_and_arch_at_build(self):
        with self.assertRaises(ba.ArtifactError):
            ba.build_manifest(
                commit="a" * 40, dirty=False, configuration="Release",
                xcode_version="27.1", xcode_build="27A9275",
                sdk_version="27.1", sdk_build="24A94232",
                runtime_version="iOS 27.0", runtime_build="24A434",
                arch="arm64",
                app_sha256="a" * 64, extension_sha256="b" * 64,
                archive_sha256="c" * 64, bundle_id=ba.SCREENSHOT_BUNDLE_ID,
                extension_id=ba.SCREENSHOT_EXTENSION_ID)
        with self.assertRaises(ba.ArtifactError):
            ba.build_manifest(
                commit="a" * 40, dirty=False, configuration="Screenshot",
                xcode_version="27.1", xcode_build="27A9275",
                sdk_version="27.1", sdk_build="24A94232",
                runtime_version="iOS 27.0", runtime_build="24A434",
                arch="x86_64",
                app_sha256="a" * 64, extension_sha256="b" * 64,
                archive_sha256="c" * 64, bundle_id=ba.SCREENSHOT_BUNDLE_ID,
                extension_id=ba.SCREENSHOT_EXTENSION_ID)


class TarTests(unittest.TestCase):
    def test_no_bulk_extract_in_helper(self):
        src = Path(__file__).resolve().parent.parent / "build_artifact.py"
        text = src.read_text(encoding="utf-8")
        self.assertNotIn("extractall(", text)
        self.assertNotIn(".extract(", text)

    def test_pack_extract_preserves_perms_symlinks_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            app = make_fake_app(tmp_p)
            tar_path = tmp_p / "app.tar.gz"
            meta = ba.pack_app(app, tar_path)
            self.assertTrue(tar_path.is_file())
            self.assertRegex(meta["archive_sha256"], r"^[0-9a-f]{64}$")
            dest = tmp_p / "out"
            dest.mkdir()
            members = ba.safe_extract(tar_path, dest)
            self.assertTrue(members)
            out_app = dest / app.name
            mode = os.stat(out_app / "TimeOfLife").st_mode
            self.assertTrue(mode & stat.S_IXUSR)
            ext_mode = os.stat(
                out_app / "PlugIns" / ba.SCREENSHOT_APPEX_NAME
                / ba.SCREENSHOT_APPEX_EXECUTABLE).st_mode
            self.assertTrue(ext_mode & stat.S_IXUSR)
            car_mode = os.stat(out_app / "Assets.car").st_mode
            self.assertFalse(car_mode & stat.S_IXUSR)
            link = out_app / "Asset-link"
            self.assertTrue(link.is_symlink())
            self.assertEqual(os.readlink(link), "Assets.car")
            hashes = ba.resource_hashes(out_app)
            self.assertIn("TimeOfLife", hashes["files"])
            self.assertIn("Asset-link", hashes["symlinks"])
            self.assertEqual(ba.verify_hashes(
                out_app, hashes["files"], hashes["symlinks"]), [])

    def test_dir_symlink_to_valid_dir_recorded_and_retarget_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            app = make_fake_app(tmp_p)
            fw = app / "Frameworks" / "F.framework" / "Versions"
            (fw / "A").mkdir(parents=True)
            (fw / "A" / "F").write_bytes(b"fw")
            (fw / "Current").symlink_to("A")
            hashes = ba.resource_hashes(app)
            self.assertIn("Frameworks/F.framework/Versions/Current",
                          hashes["symlinks"])
            self.assertEqual(hashes["symlinks"][
                "Frameworks/F.framework/Versions/Current"], "A")
            self.assertEqual(ba.verify_hashes(
                app, hashes["files"], hashes["symlinks"]), [])
            (fw / "Current").unlink()
            (fw / "B").mkdir()
            (fw / "B" / "F").write_bytes(b"fw2")
            (fw / "Current").symlink_to("B")
            self.assertTrue(ba.verify_hashes(
                app, hashes["files"], hashes["symlinks"]))

    def test_hashes_detect_tamper_missing_extra(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            app = make_fake_app(tmp_p)
            hashes = ba.resource_hashes(app)
            (app / "Assets.car").write_bytes(b"tampered")
            self.assertTrue(ba.verify_hashes(
                app, hashes["files"], hashes["symlinks"]))
            (app / "Assets.car").write_bytes(b"car-bytes")
            self.assertEqual(ba.verify_hashes(
                app, hashes["files"], hashes["symlinks"]), [])
            (app / "Assets.car").unlink()
            self.assertTrue(ba.verify_hashes(
                app, hashes["files"], hashes["symlinks"]))
            (app / "Assets.car").write_bytes(b"car-bytes")
            (app / "stowaway.bin").write_bytes(b"x")
            self.assertTrue(ba.verify_hashes(
                app, hashes["files"], hashes["symlinks"]))

    def _craft_tar(self, path: Path, members: list) -> None:
        with tarfile.open(path, "w:gz", format=tarfile.PAX_FORMAT) as tf:
            for m in members:
                tf.addfile(m[0], m[1])

    def _reg(self, name: str, data: bytes = b"x") -> tuple:
        info = tarfile.TarInfo(name=name)
        info.size = len(data)
        return (info, io.BytesIO(data))

    def test_unsafe_members_rejected_and_contained(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            evil = tmp_p / "evil.tar.gz"
            link_abs = tarfile.TarInfo(name="link")
            link_abs.type = tarfile.SYMTYPE
            link_abs.linkname = "/etc/passwd"
            link_out = tarfile.TarInfo(name="dir/link")
            link_out.type = tarfile.SYMTYPE
            link_out.linkname = "../../outside"
            self._craft_tar(evil, [
                self._reg("/abs.txt"),
                self._reg("../escape.txt"),
                (link_abs, None),
                (link_out, None),
            ])
            dest = tmp_p / "dest"
            dest.mkdir()
            with self.assertRaises(ba.ArtifactError):
                ba.safe_extract(evil, dest)
            self.assertFalse((tmp_p / "escape.txt").exists())
            self.assertFalse(Path("/abs.txt").exists())

    def test_hardlinks_rejected_explicitly(self):
        # Hardlink targets are archive-root-relative, not parent-relative,
        # so they must never be installed via the symlink path. The real
        # Screenshot product ships zero hardlinks (verified read-only).
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            path = tmp_p / "hard.tar.gz"
            hard = tarfile.TarInfo(name="TimeOfLife.app/Alias")
            hard.type = tarfile.LNKTYPE
            hard.linkname = "TimeOfLife.app/TimeOfLife"
            self._craft_tar(path, [self._reg("TimeOfLife.app/TimeOfLife"),
                                   (hard, None)])
            dest = tmp_p / "dest"
            dest.mkdir()
            with self.assertRaises(ba.ArtifactError):
                ba.safe_extract(path, dest)

    def test_duplicate_members_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            path = tmp_p / "dup.tar.gz"
            self._craft_tar(path, [self._reg("a.txt", b"one"),
                                   self._reg("a.txt", b"two")])
            dest = tmp_p / "dest"
            dest.mkdir()
            with self.assertRaises(ba.ArtifactError):
                ba.safe_extract(path, dest)

    def test_preexisting_files_never_mutated(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            path = tmp_p / "over.tar.gz"
            self._craft_tar(path, [self._reg("victim.txt", b"evil")])
            dest = tmp_p / "dest"
            dest.mkdir()
            victim = dest / "victim.txt"
            victim.write_bytes(b"original")
            with self.assertRaises(ba.ArtifactError):
                ba.safe_extract(path, dest)
            self.assertEqual(victim.read_bytes(), b"original")
            # preexisting symlink is not followed or replaced either
            victim.unlink()
            victim.symlink_to("/etc/hostname")
            with self.assertRaises(ba.ArtifactError):
                ba.safe_extract(path, dest)
            self.assertTrue(victim.is_symlink())

    def test_alias_plant_then_traverse_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            path = tmp_p / "alias.tar.gz"
            link = tarfile.TarInfo(name="a")
            link.type = tarfile.SYMTYPE
            link.linkname = "sub"
            self._craft_tar(path, [(link, None),
                                   self._reg("a/evil.txt", b"x")])
            dest = tmp_p / "dest"
            dest.mkdir()
            (dest / "sub").mkdir()
            with self.assertRaises(ba.ArtifactError):
                ba.safe_extract(path, dest)
            self.assertFalse((dest / "sub" / "evil.txt").exists())

    def test_app_structure_ios_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            app = make_fake_app(tmp_p)
            self.assertEqual(ba.verify_app_structure(app), [])

    def test_app_structure_rejects_macos_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            app = make_macos_app(tmp_p)
            self.assertTrue(ba.verify_app_structure(app))

    def test_app_structure_exact_appex_identities(self):
        import shutil
        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            # wrong app bundle id
            app = make_fake_app(tmp_p, name="A.app")
            (app / "Info.plist").write_bytes(
                _plist_bytes("TimeOfLife", "com.example.other"))
            self.assertTrue(ba.verify_app_structure(app))
            shutil.rmtree(app)
            # wrong appex bundle id
            app = make_fake_app(tmp_p, name="B.app")
            ext = app / "PlugIns" / ba.SCREENSHOT_APPEX_NAME
            (ext / "Info.plist").write_bytes(
                _plist_bytes(ba.SCREENSHOT_APPEX_EXECUTABLE,
                             "com.example.other"))
            self.assertTrue(ba.verify_app_structure(app))
            shutil.rmtree(app)
            # appex executable not the exact named binary
            app = make_fake_app(tmp_p, name="C.app")
            ext = app / "PlugIns" / ba.SCREENSHOT_APPEX_NAME
            (ext / ba.SCREENSHOT_APPEX_EXECUTABLE).rename(ext / "Other")
            self.assertTrue(ba.verify_app_structure(app))
            shutil.rmtree(app)
            # renamed appex directory is not accepted
            app = make_fake_app(tmp_p, name="D.app")
            ext = app / "PlugIns" / ba.SCREENSHOT_APPEX_NAME
            ext.rename(app / "PlugIns" / "Other.appex")
            self.assertTrue(ba.verify_app_structure(app))
            shutil.rmtree(app)
            # missing appex fails
            app = make_fake_app(tmp_p, name="E.app")
            shutil.rmtree(app / "PlugIns")
            self.assertTrue(ba.verify_app_structure(app))
            # stripped exec bit fails (app + extension)
            app = make_fake_app(tmp_p, name="F.app")
            (app / "TimeOfLife").chmod(0o644)
            self.assertTrue(ba.verify_app_structure(app))
            (app / "TimeOfLife").chmod(0o755)
            (app / "PlugIns" / ba.SCREENSHOT_APPEX_NAME
             / ba.SCREENSHOT_APPEX_EXECUTABLE).chmod(0o644)
            self.assertTrue(ba.verify_app_structure(app))

    def test_extracted_modes_match_archive(self):
        import stat as _stat

        with tempfile.TemporaryDirectory() as tmp:
            tmp_p = Path(tmp)
            app = make_fake_app(tmp_p)
            tar_path = tmp_p / "app.tar.gz"
            ba.pack_app(app, tar_path)
            dest = tmp_p / "out"
            dest.mkdir()
            members = ba.safe_extract(tar_path, dest)
            self.assertTrue(members)
            self.assertEqual(
                ba.verify_extracted_modes(tar_path, dest), [])
            # a stripped executable bit is caught with the exact path
            (dest / app.name / "TimeOfLife").chmod(0o644)
            errs = ba.verify_extracted_modes(tar_path, dest)
            self.assertEqual(len(errs), 1)
            self.assertIn("TimeOfLife", errs[0])
            # foreign extra files are reported, never silently accepted
            (dest / app.name / "stowaway.bin").write_bytes(b"x")
            errs = ba.verify_extracted_modes(tar_path, dest)
            self.assertTrue(any("stowaway" in e for e in errs))

    def test_devices_installable(self):
        m = _manifest()
        self.assertEqual(ba.check_devices_installable(
            ["iphone69", "ipad13"],
            ["iphone69", "iphone63", "ipad13"], m), [])
        self.assertTrue(ba.check_devices_installable(
            ["iphone65"], ["iphone69", "iphone63", "ipad13"], m))
        bad = dict(m, arch="x86_64")
        self.assertTrue(ba.check_devices_installable(
            ["iphone69"], ["iphone69", "iphone63", "ipad13"], bad))

    def test_devices_installable_rejects_non_dict_manifest(self):
        for manifest in (None, [], "x", 42):
            with self.subTest(manifest=manifest):
                errs = ba.check_devices_installable(
                    ["iphone69"], ["iphone69", "iphone63", "ipad13"],
                    manifest)
                self.assertTrue(errs)


if __name__ == "__main__":
    unittest.main(verbosity=2)
