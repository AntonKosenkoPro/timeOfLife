# Scenario→evidence matrix — screenshot-capture-workflow delta (docs-owned, no code proof)

All non-baseline runtime assertions start PENDING. Existing tests do NOT prove new
code; unit-proof notes below are owner-reported (not manual passes) and stay PENDING
until combined verification audit + Swift cross-language proof land. Baseline (§1)
rows are DONE; all others PENDING at gate 4/41. Evidence links: `runner.md`
(finalizer/probe checkpoint), `helpers.md` (device worker + audit), `panels.md`
(consumer), `protocol.md` (frozen envelope).

Legend: I = iOS worker (Swift), P = Python runner, W = workflow, N = panels, M = manual/measured.

## Scheduling (device workers)

- Default 3 device workers, locales sequential, own sim → W contract tests
  (device-only matrix, max-parallel 5, fail-fast false, one sim/install) + pilot 5.4
  timing → PENDING.
- More devices / fewer slots queue without duplication; delays reported → W contract
  + 7.4 queueing proof → PENDING (>5-catalog-slots).
- Empty/unknown/duplicate/malformed/injection input rejected pre-build → W 6.1
  validation tests → PENDING.
- Build/capture/packaging share the 5-job ceiling; waits in report → W + 8.1/8.2
  timing reports → PENDING.

## Verified build (6.2–6.4)

- One arm64 Screenshot build serves all devices/locales; hashes recorded; no
  per-locale rebuild → W+I slice/provenance tests → PENDING.
- Digest/commit/config/arch/toolchain mismatch fails pre-install → W+P provenance
  tests → PENDING. Cache miss rebuilds (never stale/skip) → W 6.3 tests → PENDING.

## Session batching (3.x)

- 4 frames (Track→Insights→History top→Add entry) one fixture, counts/contents
  unchanged, Add entry never commits → I 3.1–3.3 + pilot 5.1/5.2 equivalence → PENDING.
- New locale/pass/domain = fresh process+store; ru→zh-Hans→es-419/pt-BR sequencing,
  no inherited state → I 3.5 → PENDING.

## Command binding (2.2–2.4; golden owned by P, shared with I)

- Stale ack never authorizes export; locale/clock/fixture change rejected; replay or
  ended-session replay fails closed; unchanged re-observe = no-op; cross-session or
  unsupported format fails closed → I+P golden + atomic-transport tests → PENDING
  (hash semantics: exact raw-UTF-8 SHA + volatile-only-payload projection).

## Native validation per export (3.4, 4.1)

- Unmounted/unsettled surface never exports (bounded failure); wrong geometry/totals
  fails; no headless totals/cached readiness/stretch/auto-approve; deadlines kept →
  I mount/readiness + P live-state gate → PENDING (native mount).

## Two-pass semantics (2.3)

- Fresh volatile IDs compare equal on identical semantic inputs; any locale/fixture/
  treatment/clock/frame/geometry/content change detected → I+P golden/projection
  tests → PENDING.

## Live Activity (4.5–4.6, 6.7)

- One activity ID/start anchor per real-time session; hash-bound numeric checks, 2s
  tolerance, geometry/mask rules → I+P + genuine manual registration → PENDING
  (genuine LA).
- CI without genuine pixels stays pending/blocked; job success/fast ZIP never promotes
  → finalizer/N tests → PENDING (pending honesty).
- iPad Island N/A by probe (no Island sessions/images); Lock Screen still required →
  finalizer/N tests → PENDING (N/A).

## Cleanup gates frames (4.2–4.4)

- Mid-story fail/cancel: cleanup attempted, earlier PNGs kept with dependency status,
  no complete without combined receipt; contamination stops later locales → P+I
  failure-injection tests → PENDING (cleanup failure; cancel).
- Preexisting overrides / cross-session cleanup fail closed, no foreign wipe → same
  → PENDING. Transcript-mismatched receipt finalizes nothing → same → PENDING.

## Isolation (4.7)

- Release ignores capture transport; sign-in gate intact; isolated store via normal
  migrations; no prod/network/sync touch → I negative tests → PENDING.

## Artifacts/bundle (6.6–6.7, 8.3)

- Per-locale artifacts (both passes, receipts, timings, failed/unattempted statuses);
  handoff/debug vs complete bundle labeling; blocked cells retained → W+N + M bundle
  check → PENDING (failed locale; subset dispatch).

## Full acceptance (7.4, 8.1–8.3)

- Cold AND warm full default runs <1200s dispatch-to-ZIP with queue/cache/download/
  boot/session/frame/package timings + overlap/competitor disclosure → measured CI
  → PENDING (cold/warm). Miss = reported unmet, scope never narrowed → PENDING.
- 7.4: subset dispatch, failed locale, cancelled session, >5-device catalog queue
  correctly → W contract + M → PENDING (subset; cancel; >5 slots).

## 7.4 verification mapping 2026-11-04 (docs-owned; every delta scenario)

Status key: PROVEN-U = unit/structural executable proof (no real-CI claim);
PROVEN-N = native artifact evidence (audited hashes); OPEN = gap specified.
No approval/genuine-LA gates invented (performance change preserves status only).

Scheduling: default 3 workers → PROVEN-U (`test_device_matrix_capped`,
`test_no_locale_matrix`, `test_worker_uses_run_device_worker`) + PROVEN-N
(6-pair expansion). Unsupported/duplicate input → PROVEN-U (workflow_inputs 20
+ `test_inputs_via_env`). Shared ceiling + queue note → PROVEN-U (YAML `needs`
chains + `describe_capacity` labeling) / actual-queue observed-only (8.x).
Build: one binary + provenance + mismatch + cache-miss-rebuild → PROVEN-U
(`test_build_once_arm64`, slice/manifest/provenance/cache tests) + PROVEN-N
(a4f0d8d5/appex hashes in 12 manifests).
Session batching: fixture reuse + freshness + locale sequencing → PROVEN-U
(ResetTests, 3.1–3.3 marked) + PROVEN-N (3.5 marked, 8/8 headers).
Command binding: stale/replay/cross-session/unsupported/no-op → PROVEN-U
(2.2–2.4 marked, golden both languages).
Native validation: unmounted/late-callback/geometry/totals → PROVEN-U
(3.4 marked + live-state gate) + PROVEN-N (native geometries per frame).
Two-pass semantics: volatile-vs-semantic → PROVEN-U (2.3 marked).
Live Activity: one anchor + pending/N/A/failed/genuine paths + 2s tolerance +
masks → PROVEN-U (4.5/4.6 marked; genuine pixels out of scope).
Cleanup: fail/cancel injects + receipt gating + preserved PNGs + locale-stop →
PROVEN-U (4.3/4.4 marked) + PROVEN-N (24 receipts/24 sessions).
Isolation: shipping ignores transport → PROVEN-U (4.7 marked).
Artifacts/bundle: per-locale uploads + failed/unattempted + handoff-vs-complete
labels → PROVEN-U (6.6/6.7 marked, panels 89/89) + PROVEN-N (real manifests).
Runtime 8.1/8.2: OPEN (no cold/warm CI runs measured).

7.4 oversubscription gap CLOSED as PROVEN-U, independently reviewed 2026-11-04:
`test_oversubscribed_workflow.py` passes 8/8 tests. Six selected devices flow
through real `validate_selection` and `run_device_worker.execute`, with injected
fake child responses, under modeled two/three-slot pools. Capacity is bounded
by the live YAML max-parallel ceiling. Exact-once 24-session assertions,
event-ledger bounds, failed-device retention, pre-start/mid-run cancellation,
explicit remaining statuses, and a five-of-six truncation oracle prove no-drop
behavior within this model. Catalog patches are restored and temporary artifacts
are isolated. Mid-run cancellation is tested serially, not as a threaded race;
actual overlap peaks are not asserted. No real GHA scheduling/contention or
queue-time claim follows from these tests; those observations remain 8.x work.
Subset/failed-locale/cancel/drop paths remain PROVEN-U (device-worker tests +
contract tests + failed-status records). Runtime scenarios 8.1/8.2 remain OPEN.
