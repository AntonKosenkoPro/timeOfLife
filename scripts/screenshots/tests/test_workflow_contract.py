#!/usr/bin/env python3
"""Regression contract for .github/workflows/app-screenshots.yml.

Device-affine session architecture (change optimize-app-screenshot-workflow):
one validated Ubuntu selection job, one explicit arm64 Screenshot build
with a verified artifact, one device worker per selected device driving
sequential locales/passes/domains through run_device_worker.py, then the
existing panels packaging. Each pins a proven review finding or a 6.x
requirement as a text assertion on the workflow file (no YAML
dependency — stdlib only). If a future edit reintroduces a fixed bug,
the named test fails first.
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

    def test_validate_ubuntu_job(self):
        # 6.1: device/locale/runtime selection is validated on cheap
        # Ubuntu BEFORE any macOS work, via workflow_inputs (never
        # evaluated as source); downstream jobs consume its outputs.
        body = text()
        seg = body.split("validate:")[1].split("build:")[0]
        self.assertIn("ubuntu-latest", seg)
        self.assertIn("workflow_inputs", seg)
        self.assertIn("validate_selection", seg)
        self.assertIn("devices:", seg)
        self.assertIn("GITHUB_OUTPUT", seg)

    def test_no_locale_matrix(self):
        # 6.5: workers are device-affine; locales run sequentially inside
        # the worker. No locale jobs, no matrix.language anywhere.
        body = text()
        self.assertNotIn("matrix.language", body)
        self.assertIn("matrix.device", body)
        self.assertIn("fromJSON(needs.validate.outputs.devices)", body)

    def test_device_matrix_capped(self):
        # 6.5: at most five device workers, overlapping; one red worker
        # never discards the others' artifacts.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertIn("max-parallel: 5", seg)
        self.assertIn("fail-fast: false", seg)

    def test_build_once_arm64(self):
        # 6.2: exactly one build job (never a matrix), explicitly
        # arm64-only, Release-optimized Screenshot configuration; no
        # per-locale or per-pass rebuild can be keyed.
        body = text()
        self.assertIn("ARCHS=arm64", body)
        self.assertIn("-configuration Screenshot", body)
        build_seg = body.split("\n  build:\n")[1].split("\n  screenshots:\n")[0]
        self.assertNotIn("matrix:", build_seg)
        self.assertNotIn("matrix.device", build_seg)
        self.assertNotIn("matrix.language", build_seg)

    def test_build_manifest_pins_toolchain(self):
        # 6.2/6.4: the shared artifact carries a build manifest with the
        # EXACT Xcode marketing version + build ID and SDK build ID
        # (REQUIRED, not optional); workers verify it before installing.
        body = text()
        self.assertIn("parse_xcode_build", body)
        self.assertIn("xcode_build", body)
        self.assertIn("sdk_build", body)
        self.assertIn("build_manifest", body)
        self.assertIn("verify_manifest", body)

    def test_lipo_slice_inspection(self):
        # 6.2: ONLY_ACTIVE_ARCH on a generic destination does not prove
        # arm64-only; app AND extension slices are inspected and must be
        # exactly arm64 (no universal binaries in the fleet).
        body = text()
        self.assertIn('"lipo", "-archs"', body)
        self.assertIn("validate_slices", body)
        self.assertIn("parse_lipo_archs", body)

    def test_extension_hash_bound_to_named_appex(self):
        # bug/medium (review 3355): extension_sha256 was taken from the
        # first .appex of a sorted glob while verify_app_structure
        # checks the exact expected appex and ignores other PlugIns
        # members — an extra .appex sorting first made the manifest
        # attest the wrong extension while the structure check passed
        # (reproduced with an AAAHelper.appex fixture). Both the build
        # packaging and the worker re-hash bind to SCREENSHOT_APPEX_NAME.
        body = text()
        self.assertNotIn('*.appex', body)
        self.assertNotIn("appexes[0]", body)
        build_seg = body.split("Inspect slices and package")[1].split(
            "Upload build artifact")[0]
        self.assertIn("SCREENSHOT_APPEX_NAME", build_seg)
        worker_seg = body.split("\n  screenshots:\n")[1].split(
            "\n  panels:\n")[0]
        verify_seg = worker_seg.split("Verify build artifact")[1].split(
            "Resolve device catalog")[0]
        self.assertIn("SCREENSHOT_APPEX_NAME", verify_seg)

    def test_dependency_cache_correct(self):
        # 6.3: dependency cache key covers lockfile + toolchain/SDK/arch/
        # config; a cold miss rebuilds (never skips, never substitutes a
        # stale artifact) and the normal build always runs after restore.
        body = text()
        self.assertIn("actions/cache@v4", body)
        self.assertIn("dependency_cache_key", body)
        self.assertIn("Package.resolved", body)
        self.assertNotIn("fail-on-cache-miss: true", body)
        build_seg = body.split("\n  build:\n")[1].split("\n  screenshots:\n")[0]
        self.assertIn("xcodebuild build -scheme TimeOfLife", build_seg)

    def test_tar_verified_before_install(self):
        # 6.4: permission-preserving tar + full resource/provenance
        # verification happen BEFORE simctl install; extraction is
        # fail-closed (never bulk extract) and a provenance mismatch
        # fails before any install.
        body = text()
        self.assertIn("pack_app", body)
        self.assertIn("safe_extract", body)
        self.assertIn("resource_hashes", body)
        self.assertIn("verify_hashes", body)
        self.assertIn("verify_extracted_modes", body)
        self.assertIn("app_sha256", body)
        self.assertIn("extension_sha256", body)
        self.assertIn("archive_sha256", body)
        self.assertNotIn("extractall(", body)
        build_seg = body.split("\n  build:\n")[1]
        worker_seg = build_seg.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertLess(
            worker_seg.index("verify_manifest"),
            worker_seg.index("simctl install"),
        )
        self.assertLess(
            worker_seg.index("safe_extract"),
            worker_seg.index("simctl install"),
        )
        self.assertLess(
            worker_seg.index('manifest["archive_sha256"]'),
            worker_seg.index("safe_extract"),
        )

    def test_worker_uses_run_device_worker(self):
        # 6.5/9.1: one owned simulator/install per worker; locales run
        # sequentially with a SINGLE automated pass and both session
        # domains inside run_device_worker.py (actual CLI, lease-gated,
        # auditable CI flag). Exactly one create/boot/install per worker.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertIn("run_device_worker.py", seg)
        self.assertIn("--device-key", seg)
        self.assertIn("--locales", seg)
        self.assertIn("LIFIO_CAPTURE_LEASE", seg)
        self.assertIn("LIFIO_CAPTURE_CI", seg)
        self.assertEqual(seg.count("simctl create"), 1)
        self.assertEqual(seg.count("simctl install"), 1)
        self.assertIn('simctl boot "$UDID"', seg)

    def test_single_pass_no_automatic_comparison(self):
        # 9.1/9.2: one automated pass per locale — no r1/r2 sequencing
        # language in the worker steps and no automatic comparison
        # invocation; human inspection across manual reruns replaces it.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertNotIn("r1/r2", seg)
        self.assertNotIn("finalize-two-runs", seg)
        self.assertNotIn("both passes", seg)

    def test_no_per_frame_cli(self):
        # Session architecture replaced per-frame verbs: the worker job
        # must not invoke run-frame/prepare-frame/teardown-frame or the
        # legacy pending-frame handoff loop.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertNotIn("run-frame", seg)
        self.assertNotIn("prepare-frame", seg)
        self.assertNotIn("teardown-frame", seg)
        self.assertNotIn("record-pending-frame", seg)

    def test_five_locale_uploads_always(self):
        # 6.6/9.3: independent per-locale artifacts (single pass +
        # diagnostics) upload even on worker failure; failed/unattempted
        # pairs stay listed instead of claimed complete.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        for locale in ("en", "ru", "zh-Hans", "es-419", "pt-BR"):
            self.assertIn(f"shots-${{{{ matrix.device }}}}-{locale}", seg)
        self.assertGreaterEqual(seg.count("if: always()"), 5)
        self.assertIn("worker-summary.json", seg)

    def test_scoped_cleanup(self):
        # Contamination never leaks simulators: each worker deletes only
        # its own UDID on every exit path.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertIn("simctl delete", seg)
        self.assertIn("if: always()", seg)

    def test_pinned_xcodegen_install(self):
        # bug/high: xcodegen generate with no install on a clean runner.
        self.assertIn("XCODEGEN_PIN=", text())
        self.assertIn("XCODEGEN_ZIP_SHA256", text())
        self.assertIn("shasum -a 256 -c", text())

    def test_runtime_derived_from_input(self):
        # bug/medium: hardcoded runtime died on any other ios_runtime
        # input; the iOS 27 download fallback is retained.
        body = text()
        self.assertNotIn("SimRuntime.iOS-27-0", body)
        self.assertIn("xcodebuild -downloadPlatform iOS", body)

    def test_capture_provenance_made_once(self):
        # The capture.py provenance shape ({commit_base, dirty}) is
        # produced once per worker run and forwarded to the device
        # worker; it is NOT the build manifest (different shapes for
        # different gates).
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertIn("commit_base", seg)
        self.assertIn("--provenance", seg)
        self.assertEqual(seg.count('"commit_base"'), 1)

    def test_inputs_via_env(self):
        # security/medium: workflow_dispatch inputs interpolated into shell.
        body = text()
        self.assertIn("DEVICES: ${{ inputs.devices }}", body)
        self.assertNotIn('key = "${{ matrix.device }}"', body)
        self.assertNotIn('"${{ matrix.device }}"', body)
        self.assertNotIn('"${{ matrix.language }}"', body)

    def test_no_new_secrets_or_environments(self):
        # No new ambient authority: the only secret stays the
        # repo-scoped private-asset key, bound step-scoped in exactly
        # two steps (Ubuntu manifest preflight + panels fetch), and no
        # environment: stage is added. (Figma key retired; §10.4.)
        body = text()
        self.assertNotIn("environment:", body)
        self.assertEqual(body.count("secrets."), 2)
        self.assertEqual(body.count("secrets.APPLE_BEZELS_TOKEN"), 2)

    def test_panels_runs_when_workers_fail(self):
        # other/medium: one red device worker must not discard the whole
        # bundle; panels still runs on validated + captured inputs and
        # records blocked cells.
        body = text()
        seg = body.split("\n  panels:\n")[1].split("runs-on:")[0]
        self.assertIn('if: "!cancelled()', seg)
        self.assertIn("needs: [validate, screenshots]", body)

    def test_panels_skipped_when_upstream_skipped(self):
        # bug/low (review 3464): job-level `if: "!cancelled()"` alone
        # runs panels even when validate/build failed and screenshots
        # was skipped — both download-artifact steps then fail opaquely
        # on zero artifacts. The job runs on red workers (result
        # failure, proven by 41817895686 step-level resilience) but
        # skips cleanly when there is nothing to package.
        body = text()
        seg = body.split("\n  panels:\n")[1].split("runs-on:")[0]
        self.assertIn('if: "!cancelled()', seg)
        self.assertIn("needs.screenshots.result != 'skipped'", seg)

    def test_binary_guard_inspects_tracked_content(self):
        # bug/medium: git status on a fresh checkout can never see
        # a binary committed in the PR, so the guard could never fail.
        body = text()
        self.assertIn("git ls-files -z", body)
        self.assertIn(r"\.zip$|(^|/)(shots|panels)/.*\.(png|jpg|jpeg)$", body)

    def test_artifact_reshard(self):
        # bug/high: download-artifact nests shots/shots-<dev>-<lang>/… while
        # panels expects shots/<dev>/<lang>/runs/…. Re-sharding runs
        # through the single tested helper (never a second shell copy
        # that could drift).
        body = text()
        self.assertIn("Flatten artifact layout", body)
        self.assertIn("reshard_downloaded_artifacts", body)
        self.assertNotIn("flat/$dev/$lang", body)

    def test_reshard_handles_hyphenated_locales(self):
        # bug/high: splitting artifact names on the last hyphen
        # misrouted es-419/zh-Hans/pt-BR cells. Re-sharding runs through
        # the single helper (which unit-tests the hyphenated cases),
        # never a second shell copy.
        body = text()
        self.assertIn("reshard_downloaded_artifacts", body)
        self.assertNotIn("lang=${rest##*-}; dev=${rest%-*}", body)
        seg = body.split("Flatten artifact layout")[1].split("Fetch Apple")[0]
        self.assertNotIn("for cand in iphone69 iphone63 ipad13", seg)

    def test_pillow_before_bezel_fetch(self):
        # The local stage helper verifies PNG geometry/alpha via the
        # panel builder, so Pillow installs first in the fetch step.
        body = text()
        fetch_seg = body.split("Fetch Apple bezel assets")[1].split("Render panels")[0]
        self.assertIn('python3 -m pip install --break-system-packages "Pillow==13.0.0"', fetch_seg)

    def test_capture_path_needs_no_pillow(self):
        # performance/low: scripts/screenshots/ is stdlib-only, so no
        # pip install belongs in validate/build/worker jobs; Pillow
        # installs live only in the panels job.
        body = text()
        pre_panels = body.split("panels:")[0]
        self.assertNotIn("pip install", pre_panels)
        self.assertNotIn("import PIL", pre_panels)
        panels = body.split("\n  panels:\n")[1]
        self.assertIn('python3 -m pip install --break-system-packages "Pillow==13.0.0"', panels)

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

    def test_panels_tolerates_incomplete_matrix(self):
        # bug/high: blocked cells must still zip; only a missing manifest
        # fails the job.
        body = text()
        seg = body.split("Render panels")[1].split("Write README and zip")[0]
        self.assertIn("matrix-manifest.json", seg)
        self.assertIn("::warning::panels matrix incomplete", seg)
        self.assertNotIn("continue-on-error", seg)

    def test_panels_steps_run_despite_bezel_failure(self):
        # 41813403434/41776556435: the bezel fetch failed and the default
        # success() gating skipped Render/Write/Upload, so no final ZIP
        # existed despite downloadable partial panels. Each of the three
        # packaging steps pins its own `if: "!cancelled()"` (the existing
        # job-level gate alone does not run them after a step failure).
        body = text()
        render = body.split("- name: Render panels")[1].split(
            "- name: Write README and zip")[0]
        self.assertIn('if: "!cancelled()"', render)
        write = body.split("- name: Write README and zip")[1].split(
            "- name: Upload bundle")[0]
        self.assertIn('if: "!cancelled()"', write)
        upload = body.split("- name: Upload bundle")[1]
        self.assertIn('if: "!cancelled()"', upload)

    def test_bezel_fetch_failure_is_diagnosable(self):
        # The fetch transcript must exist for EVERY failure mode and the
        # step must preserve its exit code: the job stays red (no
        # continue-on-error) while later steps still bundle the log.
        # mkdir precedes the secret guard so even a missing secret lands
        # its non-secret reason in bezel-fetch.log, never only console.
        body = text()
        fetch = body.split("Fetch Apple bezel assets")[1].split(
            "Render panels")[0]
        self.assertNotIn("continue-on-error", fetch)
        self.assertIn('mkdir -p "$RUNNER_TEMP/bezels"', fetch)
        self.assertLess(
            fetch.index('mkdir -p "$RUNNER_TEMP/bezels"'),
            fetch.index("APPLE_BEZELS_TOKEN secret missing"),
        )
        self.assertIn('tee "$RUNNER_TEMP/bezels/bezel-fetch.log"', fetch)
        self.assertIn('>"$RUNNER_TEMP/bezels/bezel-fetch.log" 2>&1', fetch)
        self.assertIn('exit "$rc"', fetch)

    def test_bezel_transcript_copied_loudly(self):
        # The transcript copies into the bundle must never swallow
        # failures: copy errors and missing log/dir warn explicitly;
        # the bundle stays partial on evidence, never falsely complete,
        # never silently short. Both the fetch log and the stage
        # transcript (hashes/provenance evidence, never raw PNGs) are
        # preserved.
        body = text()
        render = body.split("Render panels")[1].split(
            "Write README and zip")[0]
        self.assertIn("bezel-fetch.log", render)
        self.assertIn("could not copy bezel-fetch.log", render)
        self.assertIn("no bezel-fetch.log to bundle", render)
        self.assertIn("no panels dir to receive bezel-fetch.log", render)
        self.assertIn("bundled bezel-stage.json", render)
        self.assertIn("could not copy bezel-stage.json", render)
        self.assertIn("no bezel-stage.json to bundle", render)
        self.assertIn("no panels dir to receive bezel-stage.json", render)
        self.assertNotIn("|| true", render)

    def test_apple_bezel_release_pins(self):
        # §10.4 private-release delivery (Figma live fetch retired):
        # explicit release tag + asset repo, the 3 canonical PNG names,
        # the release manifest name, and the pinned manifest SHA passed
        # explicitly to the local stage helper (hash-before-use: the
        # helper trusts no manifest bytes before this SHA matches).
        # A drifted source fails verification; pins are never edited to
        # chase it, geometry never relaxed.
        body = text()
        fetch = body.split("Fetch Apple bezel assets")[1].split(
            "Render panels")[0]
        self.assertIn("gh release download apple-bezels-v1", fetch)
        self.assertIn("--repo AntonKosenkoPro/lifio-design-assets", fetch)
        self.assertIn('"iphone-17-pro-max-silver-portrait.png"', fetch)
        self.assertIn('"iphone-17-white-portrait.png"', fetch)
        self.assertIn('"ipad-pro-m5-13inch-silver-portrait.png"', fetch)
        self.assertIn('"apple-bezels-manifest.json"', fetch)
        self.assertIn("stage_bezel_assets.py", fetch)
        # Stable stage-helper CLI (C-owner confirmed, verified against
        # the actual file — not guessed): REQUIRED --manifest is never
        # omitted; --source-dir/--out point at RUNNER_TEMP (never git,
        # never the public ZIP).
        self.assertIn("--source-dir", fetch)
        self.assertIn("--out", fetch)
        self.assertIn("--manifest", fetch)
        self.assertIn(
            "--expected-manifest-sha "
            "\"a9b21ed835d7a231088e2a3249e8cfcc42b92162dfec3dcbc870c34ee6affaad\"",
            fetch)
        # Figma source fully retired: no file key, node pins, export
        # scale, fetcher, or key reference remains anywhere.
        self.assertNotIn("FIGMA", body)
        self.assertNotIn("Figma", body)
        self.assertNotIn("figma", body)
        self.assertNotIn("fetch_bezel_assets", body)
        self.assertNotIn("--scale 2", body)

    def test_bezel_token_step_scoped(self):
        # The private-release token lives ONLY in step envs (Ubuntu
        # manifest preflight + panels fetch; `gh` reads it from the
        # environment): step-scoped bindings, never echoed, never
        # passed as a CLI flag, never exported upward.
        body = text()
        validate = body.split("\n  validate:\n")[1].split("\n  build:\n")[0]
        fetch = body.split("Fetch Apple bezel assets")[1].split(
            "Render panels")[0]
        self.assertIn("GH_TOKEN: ${{ secrets.APPLE_BEZELS_TOKEN }}",
                      validate)
        self.assertIn("GH_TOKEN: ${{ secrets.APPLE_BEZELS_TOKEN }}", fetch)
        self.assertEqual(body.count("GH_TOKEN:"), 2)
        self.assertNotIn("--token", body)
        self.assertNotIn("echo $GH_TOKEN", body)
        self.assertNotIn('echo "$GH_TOKEN"', body)

    def test_validate_preflights_bezel_manifest(self):
        # §10.4 steering: the cheap Ubuntu gate runs AFTER selection
        # validation and BEFORE any macOS work — manifest ONLY (no
        # PNGs, no uploads), pinned SHA, fail-closed, stdlib lane.
        # The panels job still verifies everything before staging;
        # this gate only fails fast on bad credentials/drift.
        body = text()
        validate = body.split("\n  validate:\n")[1].split("\n  build:\n")[0]
        self.assertLess(
            validate.index("Validate device/locale/runtime selection"),
            validate.index("Preflight private bezel manifest"),
        )
        self.assertIn("gh release download apple-bezels-v1", validate)
        self.assertIn("--repo AntonKosenkoPro/lifio-design-assets",
                      validate)
        self.assertIn('"apple-bezels-manifest.json"', validate)
        self.assertIn(
            "a9b21ed835d7a231088e2a3249e8cfcc42b92162dfec3dcbc870c34ee6affaad",
            validate)
        for png in ("iphone-17-pro-max-silver-portrait.png",
                    "iphone-17-white-portrait.png",
                    "ipad-pro-m5-13inch-silver-portrait.png"):
            self.assertNotIn(png, validate)
        self.assertNotIn("upload-artifact", validate)
        self.assertNotIn("continue-on-error", validate)
        self.assertNotIn("|| true", validate)
        self.assertIn("exit 2", validate)
        self.assertNotIn("pip install", validate)
        self.assertIn("sha256sum -c", validate)

    def test_private_bezel_no_dmg_no_public_assets(self):
        # No DMG/Sketch/design-service operations in CI, and raw bezels
        # NEVER ship in the public bundle: the Write/Upload steps carry
        # panels + build manifest + raw shots only (no bezels dir).
        body = text()
        fetch = body.split("Fetch Apple bezel assets")[1].split(
            "Render panels")[0]
        for token in (".dmg", "hdiutil", "Sketch", "sketch"):
            self.assertNotIn(token, fetch)
        write = body.split("- name: Write README and zip")[1].split(
            "- name: Upload bundle")[0]
        self.assertNotIn("bezels", write)
        upload = body.split("- name: Upload bundle")[1]
        self.assertNotIn("bezels", upload)

    def test_captions_dir_archive_fallback(self):
        # post-archive (2026-11-03): captions live under changes/archive,
        # so the bare active path fails closed on every run.
        body = text()
        seg = body.split("Render panels")[1].split("Write README and zip")[0]
        self.assertIn(
            'CAPTIONS_DIR="openspec/changes/app-store-screenshot-pilot/captions"',
            seg)
        self.assertIn(
            "openspec/changes/archive/2026-11-03-app-store-screenshot-pilot/captions",
            seg)
        self.assertIn('--captions-dir "$CAPTIONS_DIR"', seg)

    def test_island_flag_is_explicit_token(self):
        # maintainability/low: the island flag is resolved inside
        # run_device_worker from the device catalog as an explicit 1/0
        # token — the workflow never hand-rolls a bool island flag.
        body = text()
        self.assertIn("run_device_worker.py", body)
        self.assertIn("--device-key", body)
        self.assertNotIn('"island": True', body)
        self.assertNotIn('"island": False', body)

    def test_provenance_heredoc_quoted(self):
        # maintainability/low: an unquoted heredoc lets the shell
        # expand $/backticks inside the Python body before it runs.
        body = text()
        self.assertIn("python3 - <<'PY'", body)
        self.assertNotIn("python3 - <<PY", body.replace("python3 - <<'PY'", ""))

    def test_dirty_scopes_out_regeneration(self):
        # bug/low: the dirty flag was read after xcodegen generate
        # + build, so rewritten tracked schemes marked every run dirty.
        self.assertIn(":(exclude)ios/TimeOfLife/TimeOfLife.xcodeproj", text())

    def test_actionlint_config_declares_custom_runner(self):
        # The `xcode-27` capture runner is not a GitHub-hosted label, so
        # static checks need it declared — otherwise a runner-label
        # error is either missed or the file gets a blanket ignore.
        # Verified with actionlint v1.7.12 (pinned): 0 findings on this
        # workflow; no message ignores configured anywhere.
        config = (Path(__file__).resolve().parent.parent.parent.parent
                  / ".github" / "actionlint.yaml")
        cfg = config.read_text(encoding="utf-8")
        self.assertIn("xcode-27", cfg)
        self.assertNotIn("ignore:", cfg)

    def test_toolchain_explicitly_selected(self):
        # Review: selection (not just a check of whatever is active);
        # only an installed Xcode 27.1 may build/work, absence fails
        # closed with no silent fallback to a wrong toolchain.
        body = text()
        self.assertEqual(body.count("Select pinned Xcode 27.1"), 2)
        self.assertIn("DEVELOPER_DIR=$SELECTED", body)
        self.assertIn("no installed Xcode 27.1 found", body)

    def test_sdk_from_xcrun_not_simctl_runtime(self):
        # Review: sdk_build from `simctl list runtimes` was the RUNTIME
        # build, not the SDK build. SDK version/build come from
        # `xcrun --sdk`; the requested runtime version/build are
        # recorded separately and never presented as the SDK.
        body = text()
        self.assertIn('"xcrun", "--sdk", "iphonesimulator"', body)
        self.assertIn('"--show-sdk-version"', body)
        self.assertIn('"--show-sdk-build-version"', body)
        self.assertIn("sdk_version", body)
        self.assertIn("runtime_version", body)
        self.assertIn("runtime_build", body)

    def test_cache_key_uses_exact_builds(self):
        # Review: marketing Xcode + runtime string under-keyed the
        # dependency cache; exact Xcode/SDK build IDs are key inputs.
        body = text()
        seg = body.split("Compute dependency cache key")[1].split(
            "Restore dependency checkouts")[0]
        self.assertIn("parse_xcode_build", seg)
        self.assertIn("sdk_build", seg)

    def test_build_dirty_is_measured(self):
        # Review: a hardcoded dirty=False would lie in the manifest;
        # dirtiness is measured after xcodegen with the scoped pattern.
        body = text()
        seg = body.split("Inspect slices and package")[1].split(
            "Upload build artifact")[0]
        self.assertNotIn("dirty=False", seg)
        self.assertIn("dirty=dirty", seg)

    def test_backfill_unreached_statuses(self):
        # Review: pre-capture failures never enter the device worker, so
        # an always-run step derives the exact selected locales and
        # writes explicit unattempted statuses without overwriting
        # finished records or claiming complete.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertIn("Backfill unreached pair statuses", seg)
        self.assertIn("backfill_unattempted", seg)

    def test_uploads_are_single_pair_dirs(self):
        # Review: two-path uploads nested locale-inside-locale after
        # reshard. Each upload is one staged pair dir; the summary is
        # staged into the cell, not uploaded beside it.
        body = text()
        seg = body.split("\n  screenshots:\n")[1].split("\n  panels:\n")[0]
        self.assertIn("Stage pair uploads", seg)
        self.assertIn("stage_pair_upload", seg)
        uploads = seg.split("Upload ")
        locale_uploads = [u for u in uploads[1:]
                          if u.split("\n")[0].strip().endswith("captures")]
        self.assertEqual(len(locale_uploads), 5)
        for block in locale_uploads:
            self.assertNotIn("worker-summary.json", block)

    def test_bundle_zip_is_self_contained(self):
        # 8.3: the delivered ZIP carries panels plus raw captures plus
        # the verified build manifest — never panels alone.
        body = text()
        seg = body.split("Write README and zip")[1].split("Upload bundle")[0]
        self.assertIn("Download build manifest", body)
        self.assertIn("panels build/build-manifest.json", seg)
        self.assertIn(" shots)", seg)

    def test_panels_uses_validated_outputs(self):
        # Packaging renders/reads the validated selection (contract:
        # select once), never raw dispatch inputs that could disagree.
        body = text()
        seg = body.split("\n  panels:\n")[1]
        self.assertIn("needs.validate.outputs.devices", seg)
        self.assertIn("needs.validate.outputs.languages", seg)
        self.assertIn("needs.validate.outputs.runtime", seg)
        render = seg.split("Render panels")[1].split("Write README")[0]
        self.assertNotIn("${{ inputs.devices }}", render)
        self.assertNotIn("${{ inputs.languages }}", render)

    def test_catalog_from_single_helper(self):
        # Review: a hardcoded YAML device list drifts from the catalog
        # as it grows; sim names resolve from workflow_inputs instead.
        body = text()
        self.assertIn("DEVICE_CATALOG", body)
        self.assertNotIn('"iPhone 18 Pro Max"', body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
