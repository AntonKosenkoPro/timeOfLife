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
        # Round-2 (PR #225): the dispatch input could only ever abort the
        # leg (the step right below hard-rejected anything but 2), so the
        # input is gone and the count is pinned at 2 in the job env.
        # finalize-two-runs still only reads -r1/-r2.
        body = text()
        self.assertNotIn("runs_per_set:", body)
        self.assertNotIn("inputs.runs_per_set", body)
        self.assertIn('RUNS_PER_SET: "2"', body)

    def test_device_catalog_reads_env(self):
        # security/high round-2: matrix.device interpolated into Python
        # source allowed breakout; the catalog reads os.environ now.
        body = text()
        self.assertIn("DEVICE_KEY: ${{ matrix.device }}", body)
        self.assertIn('os.environ["DEVICE_KEY"]', body)
        self.assertNotIn('key = "${{ matrix.device }}"', body)

    def test_sim_create_reads_env(self):
        # security/high round-2: simctl create interpolated matrix.device.
        body = text()
        self.assertIn('"shot-ci-$DEVICE_KEY"', body)
        self.assertNotIn('"shot-ci-${{ matrix.device }}"', body)

    def test_capture_loop_reads_env(self):
        # security/high round-2: OUT/RID/--locale/simctl args interpolated
        # matrix.device/matrix.language into shell/Python source.
        body = text()
        self.assertIn("LANG_KEY: ${{ matrix.language }}", body)
        self.assertIn('"$DEVICE_KEY', body)
        self.assertIn('--locale "$LANG_KEY"', body)
        self.assertIn('os.environ["OUT_DIR"]', body)
        self.assertIn('os.environ["RUN_RID"]', body)
        self.assertNotIn('"${{ matrix.device }}"', body)
        self.assertNotIn('"${{ matrix.language }}"', body)
        self.assertNotIn('Path("$OUT")', body)

    def test_la_frames_are_pending_handoffs(self):
        # bug/high round-2: simctl cannot produce genuine Lock Screen /
        # island pixels, so read_timer OCR failed closed (exit 2) and
        # aborted the leg under bash -e. CI la frames are deterministic
        # record-pending-frame stubs; the manifest pends human handoff.
        body = text()
        self.assertIn("record-pending-frame", body)
        self.assertIn("--reason", body)
        self.assertIn("IS_ISLAND: ${{ steps.dev.outputs.island }}", body)
        seg = body.split("for frame in la-lock")[1].split("finalize-run")[0]
        self.assertNotIn("read_timer.py", seg)
        self.assertNotIn("capture.py record-external-frame", seg)

    def test_state_copy_guarded(self):
        # bug/medium round-2: unguarded cp under bash -e aborted the leg
        # on a missing/stale state file, skipping teardown + manifest.
        body = text()
        self.assertIn("capture-state.json unavailable", body)
        seg = body.split("Copy the state out")[1].split("REC_MASK=")[0]
        self.assertIn('|| CONTAINER=""', seg)
        self.assertNotIn("\n              cp \"$CONTAINER", seg)

    def test_finalize_tolerance_lines(self):
        # maintainability/low round-2: the trailing backslash merged the
        # || line with the if, so a later comment/blank line would have
        # silently reparented the if into the || branch.
        body = text()
        self.assertNotIn("|| rc=$?; \\", body)
        self.assertIn('--provenance "$OUT/provenance-$RID.json" || rc=$?', body)

    def test_panels_runs_when_legs_fail(self):
        # other/medium round-2: needs:screenshots with no tolerance skipped
        # the bundle on one red leg, discarding the successful artifacts.
        body = text()
        seg = body.split("panels:")[1].split("runs-on:")[0]
        self.assertIn('if: "!cancelled()"', seg)

    def test_binary_guard_inspects_tracked_content(self):
        # bug/medium round-2: git status on a fresh checkout can never see
        # a binary committed in the PR, so the guard could never fail.
        # Scoped to pipeline outputs: Design/ artwork and the AppIcon set
        # are owner-approved, so a repo-wide png pattern would false-positive.
        body = text()
        self.assertIn("git ls-files -z", body)
        self.assertIn(r"\.zip$|(^|/)(shots|panels)/.*\.(png|jpg|jpeg)$", body)

    def test_reshard_handles_hyphenated_locales(self):
        # bug/high round-2: splitting artifact names on the last hyphen
        # misrouted es-419/zh-Hans/pt-BR cells (dev=iphone69-es, lang=419).
        body = text()
        self.assertIn('for cand in iphone69 iphone63 ipad13', body)
        self.assertIn('lang=${rest#"$dev"-}', body)
        self.assertNotIn("lang=${rest##*-}; dev=${rest%-*}", body)

    def test_pillow_before_bezel_fetch(self):
        # bug/medium round-2: fetch_bezel_assets imports builder at module
        # level, and builder exits when PIL is missing — but the pin install
        # ran only in the later Render step.
        body = text()
        fetch_seg = body.split("Fetch Apple bezel assets")[1].split("Render panels")[0]
        self.assertIn('pip install "Pillow==13.0.0"', fetch_seg)

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
