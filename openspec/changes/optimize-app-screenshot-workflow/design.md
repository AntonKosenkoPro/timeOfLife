## Context

See `proposal.md` for motivation and research, and `specs/screenshot-capture-workflow/spec.md` for observable requirements. The measured base is `bd126664` and workflow run `41718031322`; its capture phase succeeded but panels failed, so no end-to-end success time has been established.

Current cost-bearing paths:

- `.github/workflows/app-screenshots.yml`: device × language jobs boot, build, and install independently, then run fourteen frame lifecycles per pair.
- `scripts/screenshots/executor.py`: a frame performs container/provenance lookup, chrome snapshot/apply, capture launch, state polling, export, cleanup launch, restoration, and termination. The default workload makes approximately 140 launches and 1,080 simulator commands per device.
- `Core/Capture/ScreenshotPreparation.swift`: each preparation recreates an isolated database, opens it normally, seeds eight categories and 55 entries plus a timer draft through `LocalStore`, and checks read-back state.
- `Core/Capture/ScreenshotCaptureFlow.swift`: validates real view models, mounts a native shell, and waits for mounting plus a 1–3-second grace period before writing ready state. `ScreenshotCleanup.swift` verifies ownership before touching session data.
- Locale chrome previously lagged by one launch. Do not reuse processes across locales, even though some app strings have an in-process override.

The archived screenshot change remains the reference for decks, visual story, genuine system evidence, and outstanding approvals. Missing screenshot baselines are an existing documentation defect, not permission to relax those contracts.

## Goals / Non-Goals

**Goals:**

- Amortize launch, fixture initialization, simulator setup, and immutable provenance while keeping frame-level proof in a single fresh automated pass per device-locale (manual reruns when needed, no automatic second pass).
- Make the number of capture workers follow the device catalog, not device × locale count, and operate correctly when the account supplies fewer than five slots.
- Make single-pass performance, incomplete output, and cleanup failure independently observable; the 20-minute budget stays aspirational (owner accepts ~22min vs 70+), while successful downloadable output with truthful status is required.

**Non-Goals:**

- No production navigation or data-flow refactor; new session control stays under `SCREENSHOT_CAPTURE` and simulator guards.
- No schema fast path, alternate fixture database format, outbox bypass, or cached replacement for real view-model validation.
- No automatic genuine Lock Screen/Island capture solution. Existing CI limitations and human handoff remain visible; this change optimizes their lifecycle, not their approval status.
- No unconditional under-20-minute promise for unlimited devices, fewer available slots, human review, runtime downloads, or queued runs. Those durations remain reported and cannot be subtracted from an observed miss. The 20-minute target is aspirational, not a hard gate; a full single-pass run must still produce successful downloadable output (per-locale artifacts + panels/ZIP with truthful status).

## Decisions

### 1. One build stage, one worker per selected device, one packaging stage

Validate input catalogs before expensive work. Defaults stay `iphone69`, `iphone63`, `ipad13` and `en`, `ru`, `zh-Hans`, `es-419`, `pt-BR`. Device selection remains configurable; do not hard-code three worker jobs. The capture matrix varies only by device, with `max-parallel: 5`, `fail-fast: false`, and sequential locales inside a worker.

```text
validated selection → shared Screenshot build
                         ├─ iphone69: boot/install → locales, single pass each
                         ├─ iphone63: boot/install → locales, single pass each
                         └─ ipad13:   boot/install → locales, single pass each
                                      ↓
                        existing macOS panels + ZIP stage
```

The build finishes before capture workers start, so it does not permanently reserve one of the five capture slots. Packaging waits for workers, uses the current macOS font environment, and preserves partial diagnostics. The five-job limit is account-wide, not a reservation; record actual queueing and competing capacity.

**Alternatives:** keep fifteen build jobs (measured redundant work); five mixed-device shards (more setup and dependence on five available slots); three independent builds (parallel but wasteful and divergent provenance). Device-affine workers match the owner's scaling and capacity preference. A single shared build is a single failure point, addressed by verifying/uploading it before dispatching workers.

### 2. Share a small verified app artifact, not a DerivedData handoff

Use `xcode-27` and an explicitly selected installed Xcode 27.x toolchain, recording its build and the requested iOS runtime. Build the existing Screenshot configuration with simulator architecture explicitly constrained to arm64. A generic simulator destination does not make `ONLY_ACTIVE_ARCH=YES` sufficient; inspect app and extension slices. Preserve Release-class optimization, compile gates, bundle identities, entitlements, and device/archive rejection.

Tar the `.app` with embedded extension and resources to preserve executable bits and symlinks. Pair it with a text build manifest: source commit, dirty status, configuration, Xcode/build/SDK, architecture, app/extension identifiers, bundle and executable hashes, archive digest, and build/cache timings. Workers verify the archive and extracted binaries against the current checkout and toolchain before installing. Never accept an artifact merely because its filename matches.

Use dependency caches keyed by package lockfiles, toolchain/SDK, host architecture, and Screenshot configuration. Compatible build intermediates can be cached only with measured benefit and correct source invalidation; invoke the normal build after restore. A cache miss rebuilds. The final app artifact is always the authoritative product of the current build, not a loose cache entry. Avoid transferring all DerivedData to every worker.

**Research:** `/websites/github_en_actions` artifact passing, immutable artifacts, cache-hit/miss behavior, and matrix max-parallel; `/websites/developer_apple_xcode` build-settings query cited in the proposal. Keep artifact action v4 and existing pinned tooling unless a separately justified update is needed.

### 3. Use two process domains within each fresh locale (single pass)

For each locale, run a SINGLE automated pass (owner decision 2026-11-04; no automatic r2 — a manual rerun re-invokes the same single-pass workflow with a new run identity when needed). Each pass comprises:

1. **Pinned app session:** apply locale before mounting, open/migrate and seed one isolated store, then present Track → Insights → History top → Add entry sequentially.
2. Clean the pinned session, restore its settings, and terminate it with verified receipts.
3. **Real-time Live Activity session:** fresh process/store, real start anchor, one activity identity reused across the applicable system states; then end that activity and clean the session.

Use a distinct session identity for each process domain, nested within the stable device-locale run identity. Never change locale, reference clock, deck/treatment, geometry, or clock domain in an active process. No store crosses locales or manual reruns. Default upper-bound session counts become 10 per device (five pinned and five real-time for five locales), versus 70 frame sessions; with one launch and one cleanup launch per session, 20 launches replace 140. These are structural counts, not promised elapsed-time savings.

All initialization still uses normal `LocalStore` opening/migrations and existing mutation methods. Within the four pinned frames, preserve the store but reconstruct/reset capture navigation and presentation state for the target frame. Re-read real Track/History/Insights inputs and independently validate totals on every transition. Add entry remains an uncommitted form; compare entry contents/counts and totals before/after it. Reuse the fixture, not stale view models or ready acknowledgements.

**Alternative:** keep per-frame processes and only shorten polling. It retains almost all launch, seeding, and simulator-command cost. Sharing one process across all locales is rejected because native localization was already proven launch-sensitive. Combining pinned and real-time sessions would conflate clock domains. A second automatic pass is rejected per owner decision 2026-11-04 — manual reruns reuse the existing run/session identity machinery with a new run identity, no new pass selector, no legacy on-disk branches.

### 4. Extend the existing atomic-file transport with ordered session commands

Use capture-owned files under the app's Documents directory, not new sockets, URL schemes, or entitlements. The initial request declares a fresh session nonce, run/pass identity, immutable inputs, and the initial command. Later frame commands are written atomically to the active session's next-command file. Only one command is in flight. Restrict session identifiers and relative command paths to the owned namespace, rejecting traversal and symlink escape. Atomically claim/consume each published command before execution; re-observing its unchanged consumed record is a no-op, whereas a new publication of that same sequence is an explicit replay and fails closed.

A manual rerun is a fresh worker invocation carrying a fresh invocation/run identity — not a new pass selector and not a continuation of the prior run. Every status record carries the actual run identity it belongs to. Resolving the valid manifest/status for a run identity must select the unique record bound to that identity; falling back arbitrarily to another run's record (for example one prior pass versus another) is rejected. A manual rerun starts fresh output, and any ambiguity about which output belongs to the active run identity fails closed rather than merging or reusing stale results.

Each command/ack carries session nonce, run identity, monotonic sequence, frame, mode, and exact canonical request hash. Hash the canonical request payload; carry its digest in the outer command/ack envelope, avoiding a self-referential hash. Keep semantic frame hashes (excluding volatile session nonce/sequence/run identifiers) to support human comparison across manual reruns — there is NO automatic r1/r2 comparison. Tests must prove that different volatile identities do not disguise a changed locale, deck, clock, geometry, or frame input.

The app accepts only the next expected sequence and allowed story transition for that domain. It publishes preparing state before presenting a new frame. Invalid session inputs, duplicate/out-of-order commands, stale commands after cleanup, and mode changes fail closed; do not silently accept a previous ready file. The command watcher runs only during the owned capture session and is cancelled on cleanup/failure. Start with bounded short file polling and instrument its latency; preserve the existing failure deadlines.

Represent the lifecycle explicitly:

```text
new → preparing → presenting → ready(frame, sequence, hash)
                     ↑             │
                     └─ next frame ┘
          any state → cleaning → cleaned | cleanup-failed
          invalid command → failed → cleaning
```

Tag native root mounting callbacks with the command revision; ignore callbacks from an old root. Rebuild the capture root's identity and reset paths, blank search, selected tab/lens/period, scroll target, and sheet state before proving mounting for that revision. Immediately before screenshot export, the runner re-reads current state and checks the full command binding plus totals.

**Schema choice:** edit ephemeral capture Codable/JSON shapes in place, update every producer/consumer/test together, and reject unsupported shapes. No legacy branches; retained historical artifacts are not silently upgraded or claimed compatible.

> Implementation clarification (frozen v2 envelope, planning-only — not implemented): see `evidence/protocol.md`. It pins the exact outer keys, `sha256(request_json.utf8)` rule, atomic consume-before-execute, replay-vs-reobserve, transcript-in-every-ack, cleanup tokens, `run-session` CLI shape, and `session_evidence.py` verifier within this §4 contract.

### 5. Amortize device/chrome work without weakening cleanup

The device worker uses one owned simulator and serializes its sessions. The per-device lease covers the entire active session, not individual frame calls. Resolve app container paths and verify immutable binary provenance once after installation; invalidate on reinstall or container change. Each frame still records the verified binary identity and its own request/output hashes.

Snapshot clean chrome once at session entry; reject preexisting overrides. Apply light appearance, required content size, and 9:41/full cellular/full Wi-Fi/100% non-charging battery once, preserving existing device-specific disclosure rules. Track ownership explicitly so a worker can recognize its own overrides without treating another session's settings as disposable. Verify required presentation before each export; a drift fails the session rather than clearing unknown settings.

Keep one identity-checked cleanup invocation per session initially. Its receipt binds the session nonce, accepted final command, and command transcript; the runner verifies activity termination, named store/files/preferences removal, chrome restoration, process termination, and lease release. App-side cleanup cannot attest to host chrome restoration: the final runner receipt combines both outcomes. Close database handles and cancel active tasks before deleting the store. On error, timeout, or cancellation, attempt cleanup in `finally`/workflow cleanup paths; forced cancellation or host loss leaves a missing receipt and therefore incomplete evidence.

Every frame records a dependency on its session receipt. Finalization checks the receipt and its covered command transcript; it cannot infer success from the existence of earlier PNGs. A partial cleanup contaminates the worker: stop later locales, emit unattempted statuses, and never erase or repair unrelated simulator state. Preserve diagnostics and earlier exports. No background activity ending or machine-wide teardown.

### 6. Keep real-time evidence and iPad N/A separate from performance

Start/re-anchor the real activity once in a real-time session. All applicable states share its activity ID and start instant, with separate capture times and hash-bound numeric observations (tolerance remains two seconds). Keep native geometry and Island mask rules. The app session identity must not be confused with the activity identity.

CI currently cannot export genuine Lock Screen/Island system surfaces via its existing path. Preserve explicit pending evidence and independent frame records; grouping cannot invent genuine pixels or make that pass complete. On iPad, capability probes establish Island N/A without launching separate Island frame sessions or fabricating images; Lock Screen remains required. Keep probe evidence and the reason in the single-pass manifest (historical two-pass manifests retain both passes' records unchanged — do not rewrite them). Update finalization to understand N/A as explicitly scoped availability, not a generic skip.

Do not change panel approval policy to get a fast green job. A pending-evidence CI handoff/debug ZIP is distinct from a complete panel ZIP. If a panel cell is blocked by source status, retain that blocked cell and explain it in the manifest/README. Genuine automation and owner gates 5.4/6.6/9.4 remain outside this change; their wall time is not an automated-workflow benchmark.

### 7. Profile before trimming render waits or storage work

Add monotonic runner timings around each simulator subprocess, file poll, session/command transition, screenshot, and cleanup phase; collect app-side request/seed/validation/mount/settle durations separately. Do not subtract timestamps from different clock domains. Use the Xcode App Launch/signpost guidance fetched during exploration if app startup remains dominant; signposts must not expose user data or secrets.

Retain the current mount and settling guard in the initial batching implementation. Replace the validation-duration-derived grace only after a reliable command-specific settled-presentation check has a documented criterion, visual regression evidence, and equivalent timeout behavior. Faster polling detects completion earlier but does not make the underlying work complete earlier: do not multiply old poll counts by a shorter interval and call that a measured saving.

If profiling still identifies fixture I/O as material, batch existing storage operations inside `LocalStore` and preserve the real validation path. Do not skip migrations, fork the schema, omit normal storage semantics, or bypass native view models. These are gated refinements, not assumed prerequisites for the first pilot.

### 8. Preserve per-locale artifacts and truthful runtime accounting

Keep separate `shots-<device>-<locale>` artifacts with the single pass, session receipts, frame records, and timing data. Use supported-locale upload steps inside the device job (not new locale jobs), conditioned on selection and available diagnostics and executed on failure as well. The worker writes failed/unattempted status records before exit. The packaging stage retains the current locale/device layout, tool/runtime/timestamp README, source hashes, approved-versus-captured status, and missing matrix cells. Preserve the repository-secret Figma access and verified bezel export behavior; do not reintroduce environment scoping.

Measure dispatch-to-final-CI-ZIP time, not cumulative job minutes or the interval between workflow attempts. Include queueing and artifact availability. Record exact Xcode/runtime/image, cache hits, selected workload, active capacity, and whether the ZIP is a handoff/debug bundle or a complete panel bundle. No new render-only dispatch is required here; existing same-commit failed-job reruns remain distinct attempts and cannot pick up new workflow code. A manual rerun is a fresh invocation of the same single-pass workflow with a new run identity — never an in-workflow automatic retry, never a legacy protocol branch.

Acceptance defaults to three devices × five locales × single pass, with capacity for one build, then those three overlapping device workers, then one packaging job within the shared five-job ceiling. Record observed overlap and known competing jobs, or explicitly state when competitor visibility is unavailable. Acceptance requires successful downloadable output (per-locale artifacts + panels/ZIP with truthful pending/N-A/blocked status); record full phase timings against the aspirational 20-minute budget. Prior cold-cache + warm-cache <1,200s hard gates are SUPERSEDED (old runs failed; no fabricated cold/warm/final-ZIP acceptance) — historical evidence counts stay valid and are not rewritten. Expanded matrices get their own measured budget, never a silently reduced selection.

| Planning allocation | Target, not a measurement (aspirational; owner accepts ~22min vs 70+) |
| --- | ---: |
| Shared build and distribution | ≤4 minutes |
| Slowest device worker including boot/install and all locales, single pass | ≤6 minutes |
| Panels/manifest/ZIP/upload | ≤1 minute |
| Queueing/other margin | 2 minutes |
| Total | ≤13 minutes single-pass planning guide, preserving margin below the aspirational 20 (NOT a hard gate) |

First benchmark one locale single-pass on a dedicated device. Aim for ~1–1.5 capture minutes per locale (half the prior 2–2.5 two-pass guide; aspirational, not a gate), then test all three device shapes and locale sequencing. If the pilot misses the aspirational budget, profile, report actuals, and revise the implementation before expanding; do not weaken evidence, shorten deadlines, or mark the runtime task done without successful downloadable output. Human visual inspection governs; manual reruns replace automatic comparison. Do not mark the runtime task done based on a warm subset.

## Risks / Trade-offs

- **State leakage between frames** → fresh capture root revision, real per-frame reads/checks, immutable fixture fingerprint, Add-entry no-write test, and fresh process/store for each locale/pass/domain.
- **A stale file authorizes the next export** → nonce + sequence + exact request hash binding, one in-flight command, atomic writes, and replay/late-callback tests.
- **Cleanup failure affects multiple frames/locales** → session receipt dependencies, immediate stop on contamination, partial-artifact upload, and failure injection at every lifecycle phase.
- **A fast native screenshot is taken before presentation settles** → retain existing guard for initial batching, verify root revision/mounting, and require visual evidence before changing settlement.
- **Fewer workers or more devices miss the aspirational budget** → device-affine topology remains correct; publish actual queueing/capacity and record the aspiration as unmet rather than changing scope. Successful downloadable output is still required.
- **Cold build remains too slow** → arm64-only verification, normal package caching, and measured phase diagnostics; cold/warm hard gates are superseded — report actuals against the aspirational budget instead.
- **Missing genuine LA evidence produces an empty/partial panel matrix** → explicit handoff/debug designation and blocked-cell list; neither job success nor elapsed time grants approval.
- **One shared build or a device failure has a larger failure domain** → verify the build before capture, retain each completed locale's artifact, and use existing same-commit job retry semantics without a new recovery service.

## Migration Plan

1. Rebase before implementation, reconfirm research, preserve the linked baseline measurements, and add timing/counter instrumentation plus negative regression tests before lifecycle changes.
2. Evolve capture-only request/state/cleanup shapes, implement session command handling and the runner together, and update finalization/consumer tests. Preserve ordinary Release rejection and all storage/network isolation guards.
3. Prove one-locale single-pass batching and failure cleanup against the existing independent frame path (historical two-pass proof stays valid, superseded as acceptance). Keep legacy code only temporarily during implementation comparison, not as a shipped protocol compatibility branch.
4. Wire shared arm64 build transfer and single-pass device workers, update artifacts/panel consumers, and run single-pass acceptance (successful downloadable output + truthful status; record timings against the aspirational 20min). Diagnose misses instead of increasing a timeout or relaxing a contract.
5. Update operator/design/CI docs and the context's screenshot status, including the missing-baseline caveat and still-open approvals; remove obsolete per-frame CI orchestration and reconcile tasks honestly.

Rollback is a normal source revert of the app/runner/workflow protocol change together, followed by rebuilding the Screenshot artifact. Do not replay new requests against old binaries, overwrite external evidence, reset user work, or roll back production data; shipping storage and APIs do not migrate in this change.

## Open Questions

- The exact post-batching bottleneck and resulting single-pass elapsed time are intentionally measured in the pilot, not assumed. This affects tuning, not the chosen topology or evidence contract.
- The concrete settled-presentation probe remains a gated refinement: retain the existing guard unless its replacement is proven. This does not block initial session batching or justify weaker ready semantics.
