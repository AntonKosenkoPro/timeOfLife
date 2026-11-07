# Research gate — optimize-app-screenshot-workflow (2026-11-04 refresh)

Scope: task 1.1 RESEARCH portion + task 1.4 requirements re-check.
Owner: research worker (sole `tasks.md` writer until parent reassigns).
Parent: main / gpt-6.1-sol / ses_e879ace1.
Constraints honored: no build/test/simulator runs, no git writes, no code/docs/PR/commits
beyond `evidence/research.md` + `tasks.md` evidence notes.

## 1. ctx7 refresh (max 3 commands per question — 6 total, 3+3)

### Q1 — GitHub Actions artifact / cache / matrix

1. `npx ctx7@latest library "GitHub Actions" "Share built application artifact between build job and device matrix jobs with strategy max-parallel and cache"`
   - Top hit: `/websites/github_en_actions` (High, 4799 snippets, benchmark 75.35).
   - Also surfaced: `/actions/cache` (v5.0.3), `/actions/upload-artifact` (v7.0.1, v4).
2. `npx ctx7@latest docs "/websites/github_en_actions" "Share built application artifact between build job and device matrix jobs with strategy max-parallel and cache"`
   - Confirms: artifacts = pass files between jobs / post-run viewing; caching = reuse
     dependencies/intermediate outputs. Job-to-job transfer via
     `upload-artifact@v4` + `download-artifact` with `needs` sequencing; artifacts
     immutable in v4 (job 2 re-uploads under a new name). Matrix-via-`needs` output
     pattern (`define-matrix` → `fromJSON(...)` consumers) documented.
   - Supports design §2 (one verified build artifact, device-only matrix, packaging
     `needs: screenshots`, `max-parallel: 5`, `fail-fast: false`).
3. `npx ctx7@latest docs "/actions/cache" "cache miss rebuild and cache key invalidation"`
   - Confirms: default `fail-on-cache-miss: false` → job must rebuild on miss;
     `fail-on-cache-miss: true` / explicit `cache-hit != 'true'` exit are opt-in
     restrictions. Supports design §2 rule: cache miss rebuilds correctly, never
     substitutes stale output or skips work.

Pins retained: `actions/upload-artifact@v4`, `actions/download-artifact@v4`,
`xcode-27` capture image, repository-pinned XcodeGen + Pillow 13.0.0.
Prior proposal cites reconfirmed: tar preserves executable permissions
(upload-artifact permission-loss doc), cache misses must remain rebuildable
(dependency-caching doc).

### Q2 — Apple Xcode architecture / launch

1. `npx ctx7@latest library "Xcode" "Build settings ARCHS ONLY_ACTIVE_ARCH simulator arm64 and launch performance Instruments"`
   - Pick: `/websites/developer_apple_xcode` (4350 snippets, benchmark 62.37).
2. `npx ctx7@latest docs "/websites/developer_apple_xcode" "Build settings ARCHS ONLY_ACTIVE_ARCH build only arm64 simulator while retaining release compiler optimization"`
   - Confirms proposal/design warning verbatim: `ONLY_ACTIVE_ARCH=YES` "will be
     ignored when building with a run destination which does not define a specific
     architecture, such as a 'Generic Device' run destination". Hence a generic
     simulator destination does NOT make `ONLY_ACTIVE_ARCH=YES` sufficient for an
     arm64-only fleet — must explicitly constrain arch AND inspect app/extension
     slices. Release default optimization `Fastest, Smallest [-Os]` retained.
3. `npx ctx7@latest docs "/websites/developer_apple_xcode" "Measure application launch performance with Instruments App Launch and signposts"`
   - Confirms: App Launch template (time profile + thread-state trace), `os_signpost`
     / `OSSignposter` points-of-interest intervals, main-thread-first-frame rule.
     Supports design §7: use this guidance only if startup dominates; signposts must
     not expose user data/secrets; do not subtract cross-clock timestamps.

Pin: exact selected Xcode 27.x toolchain + iOS runtime recorded in build provenance;
baseline used Xcode 27.1 + iOS 27.0.

## 2. Waivers (with reasons, not silence)

- HIG waived for planning: no screen layout, interaction, or visual design is being
  redesigned. Capture must still prove the existing native Track / Insights / History
  top / Add-entry surfaces per `Design/SCREENSHOTS.md` + `SCREENS/{TimeTracking,
  Insights, History, EntryForm}.md`. No new HIG query needed unless a capture surface
  changes.
- New ActivityKit / GRDB API research waived for planning: reuse existing Live Activity
  lifecycle and `LocalStore` mutation/opening/migration methods, no new SDK or database
  APIs. Fetch applicable docs before any implementation that changes those calls
  (design §§3–4, 7 gated refinements).

## 3. Task 1.4 — requirements vs design (proved 2026-11-04, current tree read-only)

Checked against `Requirements/FURPS/Common.md`, `Timetracking.md`,
`Activity_Catalog_and_Categories.md` + `Design/SCREENSHOTS.md`,
`SCREENS/TimeTracking.md`, `Insights.md`, `History.md`, `EntryForm.md`,
`.github/workflows/app-screenshots.yml`, `docs/screenshot-capture.md`,
`docs/project-context.md`, change proposal/design/spec:

- Common U1 (minimalistic): PASS — no UI changed; exercises existing native screens.
- Common U2 (dark/light): PASS — pins existing `light-v1` treatment; no theme change.
- Common U4 (5 locales): PASS — covers en/ru/zh-Hans/es-419/pt-BR; no new app strings
  (else all five locales + L10n required per AGENTS.md).
- Common U5 (HIG): PASS — see waiver above; native proof retained.
- Common S2 (native UI SDK): PASS — spec requires native mounting/geometry/hash per
  frame; headless totals, cached readiness, stretched images, auto-approved variance
  explicitly forbidden.
- Common S5 (minimal/standardized + revising process): PASS — reuses LocalStore,
  existing lifecycle, atomic-file transport; removes obsolete per-frame orchestration;
  full gate (rebase, linters, both suites, FURPS re-check) owned by sibling workers.
- Common S6 (linters + mandatory checks): PASS — no check weakened; workflow contract
  tests updated; backend.yml/ios.yml/openspec.yml gates untouched.
- Common +2 (iOS 18+, all devices): PASS — iphone69/iphone63/ipad13 at native
  1320×2868 / 1206×2622 / 2064×2752; no stretched iPhone frames on iPad; Island N/A
  probed, never fabricated.
- Timetracking F4 (timer_state singleton persisted): PASS — sessions seed via existing
  LocalStore methods + normal migrations; no schema fast path or outbox bypass.
- Timetracking F15 (Live Activities): PASS — separate real-time session per
  locale/pass, one activity ID/start anchor, hash-bound numeric validation, 2 s
  tolerance retained, genuine vs pending/blocked vs N/A preserved.
- Timetracking R2 (timer survives crashes): PASS — no change to crash resume /
  re-mirror; capture stores are isolated, production files untouched.
- Catalog entry-owned text/categories/notes + Recents: PASS — fixture reused, Add
  entry is uncommitted form with before/after contents+counts+totals check; Recents
  exact-text rule (`Gym` ≠ `GYM`), ordered categories, 12-chip native presentation
  per SCREENS/TimeTracking.md unchanged.

Archive-only gap recorded (no baseline edit): `screenshot-capture`,
`store-marketing-panel`, `landing-screenshot-asset` specs exist only under
`openspec/changes/archive/2026-11-03-app-store-screenshot-pilot/`; this change adds a
distinct `screenshot-capture-workflow` capability and exercises (not modifies)
`localization`, `live-activities`, `timer-capture-experience`, `history-entry-list`,
`history-search`, `insights-breakdown`, `manual-entry`, `app-shell`.
Independent items untouched: landing montage deferred (no `web/` change), App Store
upload out of scope, owner gates 5.4/6.6/9.4 remain outside this performance change,
no backend/OpenAPI change.

Conflicts or blockers: NONE in requirements vs design. Lifecycle blockers remain the
standard gates owned elsewhere: fetch/rebase proof (1.1 remainder), slow-workflow
repro + drift record (1.2), unchanged-runner baseline (1.3), then §§2–8.

## 4. Gate status (for serialized reconciliation)

- 1.1 RESEARCH portion: DONE by this worker (this file); task checkbox stays OPEN
  until parent forwards the fetch/rebase proof — do not close on research alone.
- 1.4: PROVED above — eligible to mark done.
- 1.2 / 1.3: NOT owned here; do not mark without baseline worker proof via parent.
- Ambiguities before lifecycle implementation: none blocking. Design open questions
  stand: post-batching bottleneck is measured in the pilot (not assumed); settled-
  presentation probe is a gated refinement (retain existing grace/deadlines until a
  proven equivalent exists). Both affect tuning, not topology or evidence contract.

## 5. Post-fix Foundation refresh 2026-11-04 (TRUTHFUL TIMING: AFTER the fix)

- Auditor found NO fetch record for the owner's claimed ctx7 research behind the
  `.task(id:)` + explicit-locale fix, and a long-stable waiver is NOT allowed — so
  docs refreshed now (2 commands, within the max-3 budget; no secrets in queries):
  1. `npx ctx7@latest library "Foundation" "DateFormatter explicit locale calendar
     timezone relationship"` → `/websites/developer_apple_foundation` (High,
     44310 snippets, 67.28).
  2. `npx ctx7@latest docs "/websites/developer_apple_foundation" "DateFormatter
     explicit locale calendar timezone relationship"` → confirms locale/timeZone/
     calendar are independent formatter inputs (`verbatim(_:locale:timeZone:
     calendar:)`; nil locale falls back to system/ambient). Setting the calendar
     alone never moves the locale — exactly the carryover mechanism; the fix's
     explicit-locale + strict-timezone pairing matches documented behavior.
- Verdict: docs CONFIRM the fix pattern — no code changes needed, no block raised.
  This refresh happened AFTER implementation; it must never be cited as prior
  fetch. Date-formatting SDK use is an existing pattern, not new product scope.

## 6. Post-wiring Xcode CLI refresh 2026-11-04 (TRUTHFUL TIMING: AFTER wiring)

- Owner's 'long documented empirical' toolchain practice is NOT a waiver — docs
  refreshed now (2 commands, within max-3; no secrets):
  1. `npx ctx7@latest library "Xcode" "xcrun simctl xcodebuild SDK versus runtime
     destination flags"` → `/websites/developer_apple_xcode` (4350 snippets, 62.8).
  2. `npx ctx7@latest docs "/websites/developer_apple_xcode" "xcodebuild SDK versus
     runtime simulator destination flags"` → confirms `-destination` (not
     `-arch`/`-sdk`) drives SDK/arch selection; `xcodebuild -downloadPlatform iOS`
     fetches simulator runtimes. Matches the workflow's explicit toolchain select
     + runtime-download fallback + arm64 slice inspection. SDK pin: Xcode 27.1 /
     iOS 27.0 runtime (build log + provenance).
- Verdict: documented behavior supports the wired build stage — no changes needed.
  Refreshed AFTER wiring; never cite as prior fetch.
