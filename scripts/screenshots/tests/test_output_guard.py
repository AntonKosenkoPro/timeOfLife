#!/usr/bin/env python3
"""Output-root guard + lock tests (tmp dirs only; never the owner dir)."""

import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import output_guard as guard


class OutputGuardTests(unittest.TestCase):
    def test_repo_root_rejected(self):
        repo = str(guard.repo_root())
        with self.assertRaises(guard.GuardError):
            guard.resolve_out_root(repo)
        with self.assertRaises(guard.GuardError):
            guard.resolve_out_root(str(Path(repo) / "scripts"))

    def test_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            link = Path(tmp) / "into-repo"
            link.symlink_to(guard.repo_root(), target_is_directory=True)
            with self.assertRaises(guard.GuardError):
                guard.resolve_out_root(str(link))
            nested = link / "scripts"
            with self.assertRaises(guard.GuardError):
                guard.resolve_out_root(str(nested))

    def test_missing_or_file_root_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(guard.GuardError):
                guard.ensure_out_root(str(Path(tmp) / "nope"))
            f = Path(tmp) / "file"
            f.write_text("x")
            with self.assertRaises(guard.GuardError):
                guard.ensure_out_root(str(f))

    def test_valid_external_tmp_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(guard.ensure_out_root(tmp), Path(tmp).resolve())

    def test_owner_dir_resolves_outside_repo(self):
        owner = "/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot"
        resolved = guard.resolve_out_root(owner)
        self.assertTrue(resolved.is_dir())
        self.assertNotIn(guard.repo_root().resolve(), [resolved, *resolved.parents])

    def test_lock_acquire_release_cycle(self):
        udid = f"UDID-cycle-{os.getpid()}"
        lp = guard.acquire_lock(udid, "run-a")
        try:
            self.assertTrue(lp.is_file())
            with self.assertRaises(guard.GuardError):
                guard.acquire_lock(udid, "run-b")  # held
            # foreign release refused
            with self.assertRaises(guard.GuardError):
                guard.release_lock(lp, "run-b")
            # partial-ID release refused (exact match only)
            with self.assertRaises(guard.GuardError):
                guard.release_lock(lp, "run-")
            guard.release_lock(lp, "run-a")
            self.assertFalse(lp.exists())
            # re-acquire after release works
            lp2 = guard.acquire_lock(udid, "run-b")
            guard.release_lock(lp2, "run-b")
        finally:
            try:
                guard.release_lock(guard.lock_path_for(udid), "run-a")
            except guard.GuardError:
                pass
            try:
                guard.release_lock(guard.lock_path_for(udid), "run-b")
            except guard.GuardError:
                pass

    def test_locks_are_per_device(self):
        a = guard.acquire_lock(f"UDID-A-{os.getpid()}", "run-a")
        try:
            b = guard.acquire_lock(f"UDID-B-{os.getpid()}", "run-a")
            try:
                self.assertNotEqual(a, b)
            finally:
                guard.release_lock(b, "run-a")
        finally:
            guard.release_lock(a, "run-a")

    def test_unparsable_lock_never_released(self):
        lp = guard.lock_path_for(f"UDID-garbage-{os.getpid()}")
        lp.write_text("garbage\n", encoding="utf-8")
        try:
            with self.assertRaises(guard.GuardError):
                guard.release_lock(lp, "run-a")
        finally:
            lp.unlink()

    def test_lock_path_is_device_global(self):
        import tempfile as _tf
        lp = guard.lock_path_for("UDID-9")
        self.assertEqual(lp.parent, Path(_tf.gettempdir()))
        self.assertIn("UDID-9", lp.name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
