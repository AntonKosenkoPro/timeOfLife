#!/usr/bin/env python3
"""Packaging bundle layout tests (task 6.6/8.3 helper proof, single pass).

The delivered ZIP must be self-contained: panels output, raw
per-locale captures (single pass, frame records, receipts, statuses),
and the build manifest — with hashes, source status, and receipts
intact after a zip round-trip. Tmpdirs + stdlib zipfile only (mirrors
the workflow zip top-level names: panels, shots, build-manifest.json).
"""

import hashlib
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def write(path: Path, data: bytes) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


class BundleLayoutTests(unittest.TestCase):
    def _mini_bundle(self, root: Path) -> dict:
        """Miniature panels + shots + build manifest tree."""
        panels = root / "panels"
        write(panels / "6.9" / "panel-en-1.png", b"PNG-69-EN-1")
        write(panels / "matrix-manifest.json", json.dumps(
            {"status": "incomplete",
             "counts": {"rendered": 1, "blocked": 1}}).encode())
        write(panels / "BUNDLE-README.md", b"# bundle\npending handoff\n")
        shots = root / "shots"
        for lang in ("en", "es-419"):
            # single automated pass per pair (§9): exactly one run dir
            # per clean pair output for the packaging harvest to discover
            rid = f"iphone69-{lang}-r1"
            rdir = shots / "iphone69" / lang / "runs" / rid
            write(rdir / "frames" / "track-running.png",
                  f"PNG-{lang}-r1".encode())
            write(rdir / "frames" / "track-running.json", json.dumps(
                {"frame": "track-running",
                 "screenshot_sha256": sha(
                     rdir / "frames" / "track-running.png")}).encode())
            write(rdir / "run-manifest.json", json.dumps(
                {"run_id": rid, "status": "needs-inspection",
                 "pending_evidence": ["la-lock: handoff"]}).encode())
            write(shots / "iphone69" / lang
                  / f"iphone69-{lang}-r1.status.json",
                  json.dumps({"status": "ok"}).encode())
        write(shots / "iphone69" / "worker-summary.json",
              json.dumps({"device": "iphone69"}).encode())
        manifest = {"commit": "a" * 40, "arch": "arm64",
                    "xcode_build": "27A9275", "sdk_build": "24A94232"}
        write(root / "build-manifest.json",
              json.dumps(manifest).encode())
        return manifest

    def _zip_bundle(self, root: Path, out: Path) -> None:
        # Same top-level names as the workflow zip step.
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            for top in ("panels", "shots"):
                for path in sorted((root / top).rglob("*")):
                    if path.is_file():
                        zf.write(path, path.relative_to(root).as_posix())
            zf.write(root / "build-manifest.json", "build-manifest.json")

    def test_zip_round_trip_preserves_everything(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "bundle-src"
            manifest = self._mini_bundle(root)
            expected = {}
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    expected[path.relative_to(root).as_posix()] = sha(path)
            zippath = Path(tmp) / "lifio-test.zip"
            self._zip_bundle(root, zippath)
            names = zipfile.ZipFile(zippath).namelist()
            self.assertIn("panels/6.9/panel-en-1.png", names)
            self.assertIn("panels/matrix-manifest.json", names)
            self.assertIn("panels/BUNDLE-README.md", names)
            self.assertIn("build-manifest.json", names)
            dest = Path(tmp) / "bundle-out"
            dest = dest.resolve()
            with zipfile.ZipFile(zippath) as zf:
                for name in names:
                    target = dest / name
                    # no traversal: every member stays inside dest
                    self.assertTrue(
                        target.resolve() == dest
                        or dest in target.resolve().parents, name)
                    zf.extract(name, dest)
            # every path survives with identical bytes
            for rel, digest in expected.items():
                self.assertEqual(sha(dest / rel), digest, rel)
            # source status + receipts + statuses remain readable
            got_manifest = json.loads(
                (dest / "panels" / "matrix-manifest.json").read_text())
            self.assertEqual(got_manifest["status"], "incomplete")
            got_build = json.loads(
                (dest / "build-manifest.json").read_text())
            self.assertEqual(got_build, manifest)
            run = json.loads(
                (dest / "shots" / "iphone69" / "es-419" / "runs"
                 / "iphone69-es-419-r1" / "run-manifest.json").read_text())
            self.assertEqual(run["status"], "needs-inspection")
            self.assertIn("la-lock: handoff", run["pending_evidence"])
            status = json.loads(
                (dest / "shots" / "iphone69" / "es-419"
                 / "iphone69-es-419-r1.status.json").read_text())
            self.assertEqual(status["status"], "ok")
            summary = json.loads(
                (dest / "shots" / "iphone69"
                 / "worker-summary.json").read_text())
            self.assertEqual(summary["device"], "iphone69")


if __name__ == "__main__":
    unittest.main(verbosity=2)
