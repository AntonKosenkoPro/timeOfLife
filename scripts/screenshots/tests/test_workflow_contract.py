#!/usr/bin/env python3
"""Regression contract for .github/workflows/app-screenshots.yml.

Pins every proven round-1 review finding as a text assertion on the
workflow file (no YAML dependency — stdlib only). If a future edit
reintroduces a fixed bug, the named test fails first.
"""

import unittest
from pathlib import Path

WORKFLOW = (
    Path(__file__).resolve().parent.parent.parent.parent
    / ".github" / "workflows" / "app-screenshots.yml"
)


def text() -> str:
    return WORKFLOW.read_text(encoding="utf-8")


class WorkflowContractTests(unittest.TestCase):
    def test_permissions_block(self):
        # security/high: least-privilege GITHUB_TOKEN scope.
        self.assertIn("permissions:\n  contents: read", text())

    def test_runtime_derived_from_input(self):
        # bug/medium: hardcoded iOS-27-0 died on any other ios_runtime input.
        self.assertNotIn("SimRuntime.iOS-27-0", text())
        self.assertIn('RT="${IOS_RUNTIME// /-}"', text())

    def test_pinned_xcodegen_install(self):
        # bug/high: xcodegen generate with no install on a clean runner.
        self.assertIn("XCODEGEN_PIN=", text())
        self.assertIn("XCODEGEN_ZIP_SHA256", text())
        self.assertIn("shasum -a 256 -c", text())

    def test_simctl_install(self):
        # bug/high: built .app never installed; get_app_container/launch fail.
        self.assertIn("derivedDataPath", text())
        self.assertIn("simctl install", text())
        self.assertIn("built app not found", text())

    def test_geometry_passthrough(self):
        # bug/high: run-frame/record-external-frame defaulted to 1320x2868.
        self.assertIn('--geometry "$GEO"', text())

    def test_no_literal_mask_default_to_simctl(self):
        # bug/medium: `--mask=default` literal rejected by simctl and
        # divergent from preflight.screenshot_argv (only black/None emitted).
        self.assertNotIn("--mask=$MASK", text())
        self.assertIn('MASK_ARGS=""', text())
        self.assertIn('MASK_ARGS="--mask=black"', text())

    def test_state_and_request_from_real_paths(self):
        # bug/critical: --state/--request pointed at files nothing creates.
        self.assertIn("runs/$RID/state-$frame.json", text())
        self.assertIn("runs/$RID/requests/$frame.capture-request.json", text())
        self.assertIn("get_app_container", text())

    def test_finalize_run_provenance(self):
        # bug/high: missing --provenance always pends; EXIT_PENDING fails step.
        self.assertIn("--provenance", text())
        self.assertIn("commit_base", text())

    def test_runs_per_set_constrained(self):
        # finalize-two-runs only reads -r1/-r2; plan-run rejects non-2.
        self.assertIn('runs_per_set must be 2', text())

    def test_finalize_tolerates_pending(self):
        # bug/high: variance across runs (caret blink/chrome) exits 3 by
        # design; only hard errors fail the job.
        self.assertIn('[ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]', text())

    def test_upload_always(self):
        # other/low: without if:always() a capture failure discards evidence.
        seg = text().split("Upload capture artifact")[1][:400]
        self.assertIn("if: always()", seg)

    def test_artifact_reshard(self):
        # bug/high: download-artifact nests shots/shots-<dev>-<lang>/… while
        # panels expects shots/<dev>/<lang>/runs/….
        self.assertIn("Flatten artifact layout", text())
        self.assertIn("flat/$dev/$lang", text())

    def test_inputs_via_env(self):
        # security/medium: workflow_dispatch inputs interpolated into shell.
        self.assertIn('DEVICES: ${{ inputs.devices }}', text())
        self.assertIn('--devices "$DEVICES"', text())
        self.assertIn('--languages "$LANGUAGES"', text())

    def test_readme_not_overwritten(self):
        # maintainability/low: cp bundle-readme.md README.md dirtied the tree.
        self.assertNotIn("cp bundle-readme.md README.md", text())
        self.assertIn("BUNDLE-README.md", text())

    def test_binary_guard_before_artifacts(self):
        # bug/high: guard ran after the zip was created, so it never passed.
        body = text()
        self.assertLess(
            body.index("No binaries in git check"),
            body.index("Write README and zip"),
        )
        self.assertIn("--untracked-files=no", body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
