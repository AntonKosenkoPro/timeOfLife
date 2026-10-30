# Screenshot pilot — runner evidence (scripts/screenshots owner)

Scope: tasks 4.1/4.2/4.4/4.5 + text pilot manifest 1.4. Pure Python stdlib.
No iOS/xcodegen/xcodebuild/Argent/device operations performed here; all
device work waits for the iOS lease (main relays). ctx7 budget exhausted
globally (research.md: 3/3) — no further ctx7 calls made.

## Files

- `capture.py` — CLI (validate-request, write-request, preflight,
  check-state, verify-la, verify-picker, check-approval, plan-run,
  prepare-frame, capture-app-frame, record-external-frame, finalize-run,
  finalize-two-runs, teardown-frame, run-frame).
- `executor.py` — lease-gated verbs with injectable subprocess/sleeper
  (fake-tested; production wires subprocess.run).
- `request_schema.py` — pilot pins + fail-closed validation (arbitrary JSON
  never crashes) + canonical bytes + semantic hash (run_id-excluded).
- `output_guard.py` — external-root guard (symlink-resolving, repo reject)
  + device-global cross-process lock (shared tmpdir, exact owner match).
- `preflight.py` — simctl argv planning only (no device I/O in planners).
- `state_check.py` — capture-state.json validation incl. pinned-totals
  comparison and strict numerics (bool/NaN/inf rejected).
- `inspection.py` — human-observation gates (LA timer ±2s hash-bound, picker
  keyboard hash+language-bound, aware timestamps only).
- `approval.py` — hash/file-verified 5.4 gate with real output-guard checks
  and retained-manifest content binding; validates only, never approves.
- `run_manifest.py` — run assembly + semantic two-run comparison
  (errors vs unreviewed pixel variance; never byte-equal PNG promises).
- `pilot_manifest.json` — task 1.4 input pin (totals pinned from
  `ios/.../Core/Capture/ScreenshotFixture.swift`, en-austin-1).
- `expected_totals.json` — standalone pin file for `--pinned-totals`.
- `tests/` — stdlib unittest suite (fake adapter; tmp dirs only).

## Per-locale pins + expansion gates (task 6.x runner slice)

- Canonical pinned totals live in
  `openspec/changes/app-store-screenshot-pilot/decks/totals-<locale>.json`
  (5 locales; `totals-en.json` matches `expected_totals.json`). All five
  pin all 198600 s / today 4500 s / 27 texts / 7 categories; only the
  locale-native week total differs: ru/Moscow 12300 s, every other deck
  23100 s. `capture.py locale-totals --locale <loc>` prints the canonical
  pin; `request_schema.load_pinned_totals_for_locale()` resolves it.
- Schema validation is locale-aware but approval-neutral: keyboard language
  must match the request locale (`en-US`, `ru-RU`, `zh-Hans-CN`, `es-MX`,
  `pt-BR`), geometry must be a matrix size (1320x2868, 1242x2688,
  2064x2752). Passing validation never authorizes expansion.
- Expansion authorization lives at the CLI via `approval.gates_for_request`:
  non-English locale → `non-english` gate, non-pilot geometry → `ipad`
  device-matrix gate (covers 6.5-inch iPhone + 13-inch iPad). Wired into
  `plan-run`, `prepare-frame`, `run-frame`, `check-state`,
  `capture-app-frame` (geometry only), and `record-external-frame` as
  `--approval/--retained-dir`; without a valid 5.4 approval file they exit
  2 with `blocked:`. `validate-request` stays pure schema (no gate).
- Executor/planner accept all matrix geometries truthfully (`finalize-run`
  records native size, never stretches); the approval gate decides whether
  a non-pilot size may be captured.

## Confirmed interface (core iOS worker owns app side)

- App BID `com.antonkosenko.timeoflifeapp.screenshots`, config `Screenshot`.
- Runner copies ONLY `Documents/capture-request.json` via
  `simctl get_app_container <UDID> <BID> data`; launch argv is
  `SCREENSHOT_REQUEST capture-request.json` (no leading dash).
- Per-frame request: snake_case schema_version 1 + deck/locale/region/
  timezone/calendar/week_rule/reference_local_iso/app_elapsed_s/appearance/
  dynamic_type/keyboard/status_bar/treatment/frames[7 ordered]/frame/mode;
  run_id optional `[A-Za-z0-9_-]{1,64}`. Modes: app-clock-pinned (first 4:
  track-running, insights, history, add-entry),
  live-activity-realtime (last 3: la-lock, la-compact, la-expanded).
  File bytes = canonical JSON + `\n`;
  sha256 is over exact file bytes — app must hash raw bytes, not re-serialize.
- App writes `Documents/capture-state.json`: status
  preparing|ready|invalid|failure + request_sha256/deck_version/frame +
  counts.entries 55 + expected_totals{all_seconds,today_seconds,
  week_seconds,category_seconds,text_seconds} + error{code,detail} iff
  failure + build{configuration Screenshot,bundle_id,...}. `ready` means the
  correct native view is settled (core attests). la-* ready also
  requires live_activity{activity_id,started_at,request_acknowledged_at}
  (canonical keys — no `_iso` suffix, no legacy variants).
- Prompt-failure attribution: `invalid`/`failure` states SHOULD carry the
  current request_sha256+frame so the runner fails fast instead of polling
  to timeout (unattributed refusals are treated as stale, fail-closed).
- Ready additionally requires the runner-side pinned totals dictionary to
  match exactly (key-by-key diff on drift); no pin -> ready refused. The pin
  lives in `expected_totals.json` (also embedded in pilot_manifest.json),
  sourced from `ios/.../Core/Capture/ScreenshotFixture.swift`; the runtime
  app must still compute+compare — the pin never replaces app validation.
- Fresh session per frame from the same base request
  (`--terminate-running-process` in launch plan); unaccepted figures fail.

## End-to-end CLI (repeatable, no fabricated UI)

```bash
# 0. plan only, no device
python3 scripts/screenshots/capture.py plan-run --request scripts/screenshots/pilot_manifest.json --device <UDID> --out <ext-root> --run-id pilot --runs 2
# 1. per frame (lease-gated, one device lock): stage -> snapshot -> apply -> launch -> poll ready
python3 scripts/screenshots/capture.py prepare-frame --device <UDID> --request scripts/screenshots/pilot_manifest.json --frame track-running --out <ext-root> --run-id pilot-r1 --pinned-totals <pin.json>
# 1b. composite alternative holding one lock across prepare/capture/teardown (app-clock frames)
python3 scripts/screenshots/capture.py run-frame --device <UDID> --request scripts/screenshots/pilot_manifest.json --frame track-running --out <ext-root> --run-id pilot-r1 --pinned-totals <pin.json>
# 2. native export, first 4 frames only, after live revalidation (lease-gated)
python3 scripts/screenshots/capture.py capture-app-frame --device <UDID> --out <ext-root> --run-id pilot-r1 --frame track-running
# 2b. explicit teardown from the frame's own session (lease-gated; LA after observation)
python3 scripts/screenshots/capture.py teardown-frame --device <UDID> --out <ext-root> --run-id pilot-r1 --frame track-running
# 3. la-* frames: genuine Lock Screen / Island PNGs produced externally
#    (authored Argent flow after handoff), each registered with capture
#    window + observation (no OCR); repeat per la-lock, la-compact, la-expanded
python3 scripts/screenshots/capture.py record-external-frame --out <ext-root> --run-id pilot-r1 --frame la-lock --png <lock.png> --captured-at <aware-ISO> --observation <obs.json> --state <state.json> --request <frame-request.json> --pinned-totals <pin.json> --device <UDID>
# 4. assemble + evidence re-check (complete | needs-inspection); provenance required
python3 scripts/screenshots/capture.py finalize-run --out <ext-root> --run-id pilot-r1 --provenance <prov.json>
python3 scripts/screenshots/capture.py finalize-two-runs --out <ext-root> --run-id-base pilot [--variance-review <review.json>]
```
Provenance (`prov.json`): `{"commit_base": "c3e5911", "dirty": true}` —
declared by main (repo base + dirty flag); manifest adds the compiled-app
Mach-O sha and an explicit "HEAD not implied" note.

Observation (`obs.json`): `{"observed_elapsed_s": <finite non-neg, no bool>,
"screenshot_sha256": <actual PNG hash>}` — binding mandatory, validated
|capture − started_at − observed| ≤ 2s; missing stays needs-inspection.
Picker inspection: keyboard_visible + docked + observed language equal to the
request's keyboard.language + non-empty evidence artifact; returns
screenshot/artifact hashes for the manifest. Timestamps must be
timezone-aware (naive refused, never assumed UTC).

## Preflight: supported commands + waiver

Read-only discovery 2026-10-30 (no device touched): `simctl help
status_bar|io|ui|get_app_container|launch|list|spawn`.
Emitted: `status_bar list|override --time 9:41 --batteryState charged
--batteryLevel 100 --wifiMode active --wifiBars 3 --dataNetwork wifi`
(+ `clear` only for session-owned override on a clean snapshot),
`ui appearance|content_size` query + set, `io screenshot --type=png`,
`get_app_container`, `launch --terminate-running-process`, `terminate`.
WAIVER (no ctx7 left, no guessing): no locale/timezone/keyboard simctl
commands exist in confirmed help — none are emitted. Those travel app-side
in the request; picker proof is inspection evidence, not intent flags.
Snapshot/restore is exact-or-abort: `status_bar list` must be empty or
exactly the QA-observed clean header
(`Current Status Bar Overrides:\n=============================`);
header-plus-entries aborts (never blanket-clears foreign overrides).
Execution lease: mutating verbs require LIFIO_CAPTURE_LEASE=1.

## Cleanup: verified hook integration

App hook (source-read, no invention): launch
`SCREENSHOT_CLEANUP=<run_id> SCREENSHOT_CLEANUP_SHA=<request_sha256>`
(`KEY=value` argv form) → app verifies against the last capture-state and
writes `Documents/capture-cleanup.json` with
`{status: cleaned|mismatch|failure, run_id, request_sha256,
ended_activity_ids[], removed_session, error?}`. Scope per source: ONLY
capture-owned (fixture-text) activities ended + ONLY the named run's
session dir (own SQLite/WAL/SHM — whole-directory removal) + capture prefs
domain.

- Runner `teardown-frame`: launches the hook, polls the ack for matching
  run_id+SHA (stale ignored; current mismatch/failure/unknown fails
  promptly; missing times out), validates fields — pinned frames must report
  `ended_activity_ids == []`, the LA frame must list the real activity id
  from live state, `removed_session` must be true — then restores chrome
  exactly + terminates (always, even on ack failure), preserves exports.
  Status `complete` only when everything verifies, else `partial` (stale /
  unknown / failed ack, activity not ended, session not removed).
- Per-frame requests always carry the actual run_id (injected from the run
  dir, enforced equal); semantic comparison ignores run_id across runs.
- `finalize-run` rehashes every PNG against its record (missing/tampered/
  mismatched is fatal, never needs-inspection), requires complete teardowns
  + declared provenance (`--provenance {commit_base, dirty}`) before
  complete. Manifest carries `provenance` (repo base + dirty flag + compiled
  Mach-O sha + explicit "HEAD not implied" note).
- Poll awaits the CURRENT sha/frame (stale ignored, preparing continued,
  current refusal prompt); owned stale state is cleared before each launch.
  Capture revalidates live state + UDID at export time.
- No synthetic launch args invented; unsupported capabilities
  (locale/timezone/keyboard device globals) remain explicitly incomplete,
  never silently worked around.

## No-fake-success rules

- LA timer: no OCR, no arithmetic-as-observation. Missing/unbound
  observation → needs-inspection; wall mismatch → fail.
- Picker: visible-flag alone never counts as screen proof.
- Approval: decision must be `approved` AND retained_location must resolve
  equal to the verified dir AND manifest content (deck/treatment/frames)
  must match AND hashes must verify; tests/builds never imply approval.
  iPad/non-English/montage stay blocked until 5.4.
- Two runs: semantic equality (request minus run_id, totals) is required;
  PNG byte drift is reported as unreviewed variance for human review,
  optionally cleared per-frame with reviewer+date; never auto-passed.

## Required interface adjustments (core, none blocking runner tests)

1. Launch-arg token form CONFIRMED: `SCREENSHOT_REQUEST capture-request.json`
   (no dash) — runner and app agree. Cleanup-hook exact args CONFIRMED and
   implemented: `SCREENSHOT_CLEANUP=<run_id> SCREENSHOT_CLEANUP_SHA=<sha>`
   → `capture-cleanup.json` ack (source-read from `ScreenshotCleanup.swift`
   + `ScreenshotRequest.swift`; no legacy variants added).
2. Expected totals RECEIVED and pinned (55 entries, 27 texts reviewed;
   `expected_totals.json` + pilot_manifest.json, source
   `ScreenshotFixture.swift`). Core gated tests NOT claimed passed (compile
   flag fix owned by author).
3. Confirm `status_bar --time 9:41` rendering on the pinned runtime; report
   actual Xcode/runtime/device tuple per run. (`ui appearance=light` /
   `content_size=large` tokens and the clean `status_bar list` header
   QA-confirmed; `content_size large` accepted by installed help.)
4. RESOLVED: app-side session/activity teardown hook delivered by core
   (`ScreenshotCleanup.swift`); runner integrates it above. Remaining: run
   on the fresh CAPTURE-ONLY device (QA-owned lease) and report the tuple.

## Open (not claimed)

No captures run, no run folders created under the external dir, no Argent
YAML hand-written (record at authoring per create-flow rules), no iPad /
non-English / montage work before 5.4, no approval generated.
