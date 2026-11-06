---
name: lifio-local-screenshots
description: Capture Lifio App Store screenshots locally (genuine Live Activity pixels + review-only panels). Use when the user asks to capture screenshots, run the screenshot bundle, register genuine Live Activity frames, render panels, or produce the App Store panel set. Local-only by owner decision — there is no CI capture path.
---

## 1. What this produces

Genuine device-pixel captures (7 frames per device-locale: 4 pinned-clock app
frames + 3 live Live Activity states) plus review-only panels
(`<locale>/<device>` matrix + manifest). Everything lands under an out root
outside git (default `/tmp/lifio-bundle`). Renders are REVIEW SETS until the
owner explicitly approves the template and captions — never present them as
approved or complete beyond the matrix manifest's own counts.

## 2. Prerequisites (fail closed, never work around)

- macOS with Xcode 27.1 + iOS 27.0 runtime, `xcodegen`, `swiftlint`.
- `argent` CLI on PATH (`npm install -g @swmansion/argent@0.28.0` — pinned;
  no update without owner approval). Without it the consent phase records
  `failed-blocker` and Live Activities stay pending; never synthesize pixels.
- `gh` authenticated (only for the private bezel download; values never read).
- `LIFIO_CAPTURE_LEASE=1` held for every session verb (the driver sets it).
- Serialization: ONE simulator at a time, ONE `xcodebuild` at a time. Never
  touch the shared sim `C18365F5-AE32-47DE-9744-324605B0506E`. Never erase a
  preinstalled sim. No binaries in git (screenshots, panels, IPAs outside git).

## 3. Full bundle (one command)

```bash
scripts/screenshots/run_local_bundle.sh [--out DIR] [--devices k1,k2,...] [--locales JSON] [--skip-build] [--jobs N]
```

Defaults: all 3 devices (`iphone69,iphone63,ipad13`) × 5 locales
(`en,ru,zh-Hans,es-419,pt-BR`), `--jobs 1` (strictly sequential — the only
mode that reliably delivers panels). `--jobs 2..5` overlaps devices but is
proven flaky for genuine capture (cold tool-server starts + activity
liveness under contention); use it for app-frame smoke only, never when
panels are expected. `--keep-sims` reuses owned `local-bundle-*` sims
across runs (erase + reboot; clean state, no create/delete churn); without
it sims are created and deleted per run. The
driver: verify devtypes → build Screenshot app → create/boot/install owned
sim (`local-bundle-<key>`) → Live Activities pre-grant setup (once per
device: same realtime root envelope, launch, lock, shared grant — auth
before any activity starts, so banners tick; non-fatal, worker grant
stays as fallback) → `run_device_worker.py` (pinned + realtime
hold-open sessions: argent describe-backed consent grant, compact/expanded
island staging) → `register_genuine.py` (genuine registration, NO observation
flag — owner visual check governs) → `finalize-run` → shutdown/delete sim.
Fail-fast NEVER: every cell records ok/failed/unattempted and the run
continues. Then bezel staging (exact manifest-hash verification) + panels
`render-matrix` (blocked cells stay blocked, never fabricated).

## 4. Single cell (smoke / rerun)

```bash
scripts/screenshots/run_local_bundle.sh --out /tmp/smoke --devices iphone69 --locales '["en"]'
```

~3 min. Same pipeline, one owned sim, deleted after. Use for reruns (fresh
run identity per rerun — never reuse run IDs) and for proving driver changes.

## 5. Manual steps (when not using the driver)

- Build: `xcodebuild build -scheme TimeOfLife -configuration Screenshot
  -destination "generic/platform=iOS Simulator" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO
  -derivedDataPath <OUT>/dd` (from `ios/TimeOfLife`, after `xcodegen generate`).
- Worker: `python3 scripts/screenshots/run_device_worker.py --device-key KEY
  --device UDID --locales JSON --out SHOTSROOT --provenance PROV`
  (`--out` is the shots ROOT: per-locale `shots/<dev>/<locale>`).
- Register: `python3 scripts/screenshots/register_genuine.py --device-key KEY
  --udid UDID --shots SHOTSROOT --provenance PROV --locales JSON
  --log-dir LOGDIR`.
- Panels: `python3 scripts/panels/panels.py --render-matrix --shots-dir SHOTS
  --bezels-dir BEZELS --out PANELS --captions-dir <archived-captions>
  --devices JSON --languages JSON` (non-en without a captions dir BLOCK;
  never substituted copy).

## 6. Reading the result (never overclaim)

- Per-cell truth: `shots/<dev>/<locale>/runs/*/run-manifest.json`
  (`status: complete` + empty `pending_evidence`, or the exact pending line).
- Matrix truth: `panels/matrix-manifest.json` (`counts`, per-cell reasons).
- Genuine pixels live in `frames/` ONLY after registration; `staging/` holds
  pre-registration captures (never present those as final).
- Pending/N-A/blocked is the honest output for missing pieces (ungranted
  consent, no-card holds, caption misfit, missing bezels). Fix the cause and
  rerun; never weaken a guard to turn red green.
- iPad island states are N/A by design (probed, never filed).

## 7. After the run

Report per-cell manifest statuses + genuine counts + panel rendered/blocked
with reasons + wall time. Commit code changes with the agent footer
(`Co-Authored-By: opencode/<role> (<model>, ses_<id>) <opencode@local>`);
binaries stay out of git. Handed-off review sets need owner template + caption
approval before anything is called publish-ready.
