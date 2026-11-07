# Baseline evidence — optimize-app-screenshot-workflow (tasks 1.1–1.3)

Worktree: `/Users/antonkosenko/work/timeOfLife.wt/optimize-app-screenshot-workflow`, branch `opsx/optimize-app-screenshot-workflow`.
Binaries/raw captures live OUTSIDE git under `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/shot-baseline/` and `/.../shot-run/`.

## 1.1 Rebase gate (REBASE portion owned here)

- `git fetch origin` → exit 0.
- `HEAD == origin/main == bd12666465716b3ff5cf35c937312f5d1da266d5` (`ci(screenshots): iOS runtime download fallback + xcode-27 capture image (#233)`).
- `git status --short`: only untracked `openspec/changes/optimize-app-screenshot-workflow/` (planning files, ours — never stashed/reset/deleted). No tracked dirt → rebase is a no-op.
- xcodegen pin check: `XCODEGEN_PIN="2.46.0"` in `ios/TimeOfLife/ci_scripts/ci_post_clone.sh`; local xcodegen 2.46.0 — no drift.
- Local toolchain: Xcode 27.1 (27A9275); runtimes iOS 18.6 + iOS 27.0 present.

## 1.2 Slow-workflow reproduction reconfirmed (run 41718031322, attempt 1)

Source: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/shot-run/jobs.json` (16 jobs) + `fast-capture.log` + `slow-capture.log` + `panels1.log` + `panels2.log`.

- `head_sha` on every job: `bd12666465716b3ff5cf35c937312f5d1da266d5` — IDENTICAL to current `HEAD`. No source drift; no fresh baseline required.
- 15/15 capture jobs `completed/success` (device × locale matrix: iphone69/iphone63/ipad13 × en/ru/zh-Hans/es-419/pt-BR).
- Step-minute aggregation across the 15 capture jobs (from `started_at`/`completed_at` per step):
  - Build Screenshot configuration: **203.5m** total (per-job min 8.6m, max 20.9m) — proposal says 203.4m (rounding).
  - Create and boot simulator: **31.1m** total (per-job 1.1–2.8m) — matches proposal.
  - Capture runs: **78.4m** total (per-job 3.8–7.5m) — matches proposal.
  - Everything else ≤1.3m combined (checkout, xcodegen, catalog resolve, upload, cleanup).
- Wall clock: first capture start 2026-11-03T21:03:09Z → last capture end 2026-11-03T22:20:25Z = **77.3m** created-to-last-capture (proposal: 78.4m; delta is dispatch-vs-created accounting, same order).
- Panels attempts DISTINGUISHED (both failed — no end-to-end success time exists):
  - Attempt 1 (`panels1.log`, 22:20:28Z): `FIGMA_API_KEY secret missing` (exit 2) — capture artifacts existed but no bundle.
  - Rerun (`panels2.log`, 2026-11-04T02:50:13Z, 0.3m): bezel verification failed — `bezel size drift (490, 1000) != (980, 2000)` for 6.9-node `12887:20855` (exit 2).
  - The `panels.log` file is a terminal-escape notice only, not evidence.
- Runner image pins: `xcode-27-arm64` (20261026.0314.1), macOS 27.0.1 (26A434), checkout `actions/checkout@v4` SHA `11d5960a326750d5838078e36cf38b85af677262`.
- Raw per-job timings recomputed with `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/shot-parse2.py` + `shot-parse3.py` (outside git).

## 1.3 Unchanged-runner one-device/one-locale/two-pass baseline (DONE 2026-11-04)

- Dedicated fresh simulator: `OPT-BASELINE-69` = **5AAB1397-E380-4446-AABF-270E4242BD33** (iPhone 18 Pro Max, iOS 27.0). Created + booted 03:34Z (~20s boot); **deleted after the run** (scoped cleanup mirroring CI). Shared iPhone 17 `C18365F5` left Shutdown, all pre-existing sims untouched, no foreign `xcodebuild` contention (none running at start).
- Runner: unchanged `scripts/screenshots/capture.py` at `bd126664` via `shot-baseline/run-baseline.sh` (verbatim mirror of the workflow `Capture runs` step for iphone69/en × r1/r2; `LIFIO_CAPTURE_LEASE=1`, `LIFIO_CAPTURE_CI=1` → manifest `ci_approval_bypass:true`).
- Build: `xcodegen generate` 03:34:41Z (pin 2.46.0, no drift); Screenshot `BUILD SUCCEEDED` 03:34:45Z → 03:37:07Z (**2m22s** wall, warm shared DerivedData after per-worktree SPM checkout); installed 03:37:15Z. App macho_sha256 `d42054bf…e179`, BID `com.antonkosenko.timeoflifeapp.screenshots`.
- Captures (all `native-simctl`, geometry verified 1320×2868, deck `en-austin-1`, pinned totals `all_seconds 198600`, `shot-cat-food 41400`):
  - r1: 03:37:17Z → 03:38:14Z (**57s**); r2: 03:38:14Z → 03:39:11Z (**57s**). Per-frame 8–9s (app) / 8s (LA).
  - 4/4 app frames native per pass with sha-bound records; 7/7 frames per pass have session + teardown receipts.
  - Both run manifests: **`needs-inspection`**; `pending_evidence` = all 3 LA frames (`human timer observation not registered`) — exactly current-CI semantics: simctl pixels are NOT genuine Lock/Island evidence. Do not read green jobs as genuine LA proof.
  - `finalize-two-runs` rc=3 (`needs-inspection`): `unreviewed_variance` = track-running, add-entry, la-lock, la-compact, la-expanded. insights (`4ab1c775…`) and history (`f331171e…`) PNG hashes are **byte-identical r1↔r2**; track-running differs (live timer), add-entry differs (known sub-perceptual jitter), LA differ (wall-clock pixels).
- Cleanup: every teardown receipt `status: complete` (sample track-running r1: `app_cleanup.status cleaned`, `removed_session true`, `chrome_restored true`, `app_terminated true`, `failures []`); manifest `cleanup: teardown verified per frame`.
- Provenance note: local manifests record `dirty:true` because this worktree carries the untracked `openspec/changes/optimize-app-screenshot-workflow/` dir (CI's clean checkout reports false); `repo_commit_base` is `bd126664` both passes. No source drift.
- Raw evidence (outside git): `shot-baseline/` = `build.log` + `capture.log` (RUN/FRAME markers) + `shots/iphone69/en/` (20 PNG files = 14 unique frame images in `runs/*/frames/` + 6 top-level LA copies, 2 run manifests, per-frame session + teardown receipts, provenance files).
- Full SHA inventory: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/shot-baseline/SHA256SUMS` (94 files: every PNG, manifest, session/teardown receipt, request/state JSON, both logs, run script; digest `a231ddbb2cac4ae95641fc3c206b1227aba26a2e0082c2593a9ea6175623efd9`). Abbreviated hashes in this report are short refs only — the inventory carries the full digests (spot-check: r1 track-running PNG `d076593f4134441740d312c2ff430b3b0470f767f976c71b6f60a209182cfa13` matches its manifest record).
- Verification 2026-11-04 (read-only, no new build/sim): all 14 `*.teardown.json` re-parsed `status: complete` with `chrome_restored true`, `app_terminated true`, `failures []`, `app_cleanup.status cleaned`, `removed_session true`; both run manifests re-read `needs-inspection` with 7 frames each; `xcrun simctl list devices | grep OPT-BASELINE` count 0 (dedicated sim deleted); `ps` shows no `xcodebuild` held by this unit — local xcodebuild/simulator ownership RELEASED.
- Argent/UI-tool skills: NOT loaded — no UI tools used; the existing simctl capture pipeline is reproduced unchanged (waiver: no screen-layout/API change in this baseline step).

### Results (recorded 2026-11-04 — see §1.3 above; details filled)

- [x] Build walltime + install result
- [x] Per-run/frame walltimes (RUN-START/FRAME-START markers in capture log)
- [x] 4 app frames × 2 passes: native 1320×2868 PNG hashes, run-manifest status
- [x] 3 LA frames × 2 passes: pending status exactly as current CI records them (simctl pixels → record-pending-frame human handoff; NOT genuine)
- [x] Cleanup/teardown receipts per frame
- [x] finalize-two-runs comparison rc
- [x] Sim deletion after baseline (scoped cleanup, mirroring CI)
