## Why

Two full exploration sweeps (backend / iOS / specs-docs, then a fresh re-sweep with missing-tests coverage) show the same picture: the code is ahead of the paper trail after the `activities` removal and the mandatory account gate, while internal duplication (Postgres⇄SQLite mirror, 4× RecentEntry shapes, triple timers, twin editor chromes) and untested load-bearing paths (RootView gate ordering, AppContainer open/close, config/migrations/middleware, SyncController merge matrix) keep growing the cost of every future change. This umbrella change pays that down in one reviewable arc without changing any user-visible behavior.

## What Changes

- **Backend simplicity (no behavior change):** squash the create-then-drop migration chain (`003` creates `activities` only for `007` to drop; duplicate `004` numbers), extract the shared `listMigrationFiles()` loop, harden `adaptToSQLite` (named consts + tests, no silent string-surgery), add a `schema_migrations` tracking table, thread `maxAttempts`/TTLs/timeouts through `config` (kill hardcoded `5`/`15m`/`7d`/`30s`), unify `Pool()`/`DB()` accessors, collapse `decodeJSON`/`versionDetails`/`parseRFC3339`-fallback/`optTime`-split helpers, centralize limit clamping, remove committed `coverage.out`, verify `.env` is gitignored.
  Explicitly **out of scope**: unifying the Postgres/SQLite dual-engine into one query layer (separate spike decision — Docker-free tests + time-precision skew need their own trade analysis).
- **iOS simplicity + dead-code retirement (no behavior change):** unify `RecentEntry`×4 into one `ExactName` type + single mapper, extract `FieldCard` / `EditorToolbar` / `DestructiveBottomButton` / shared duration-formatter + `DynamicTypeMetrics` helpers, centralize `FocusDelay`/ticker idioms, remove the deferred-start machine prod path (keep test coverage), replace `waitForSyncShutdown` busy-poll with a state publisher, move `TrackLayoutSpike` out of the DEBUG app target, delete dead params/tokens (`HistoryViewModel(undoBuffer:)`, `shadowSmall`/`cornerRadiusLarge`/`transparent` or wire them), fix `Theme`/`L10n` bypasses (`.secondary`, `.white`, `OtpCodeField` strings, `AuthValidator` raw keys), resolve the contradictory `swiftlint` disabled-vs-opt-in entries, remove `fatalError`/`try!` crash paths in favor of surfaced errors.
  Explicitly **out of scope**: the `LogTimeView` #57 file split and `SyncController` stage extraction as standalone refactors (they are pre-requisites tracked as tasks here only insofar as needed for testability).
- **Docs revive (wording-only, behavior unchanged):** bring `AGENTS.md`, `openspec/config.yaml`, `openspec/README.md`, `docs/project-context.md`, `README.md`, `Requirements/` (esp. `Activity_Catalog_and_Categories` usecase + FURPS `F2` signed-out wording), `Design/` (AppShell/Auth/INTERACTIONS/COMPONENTS-touchpoints/ManageCategories/CategoryEditor/TimeTracking checklist/`Activity_Catalog_API` filename), `docs/history-roadmap.md` overlap, and `backend/api/openapi.yaml` header + `GET /entries/recents` + `GET /categories?modified_since=` + create-422-vs-merge-prune + 30s-window prose strictly in line with shipped behavior (mandatory gate, entries own text/categories/notes, restart-persistent undo buffer, `By text` lens, no Enable Sync, no activities table).
- **Test coverage (no behavior change):** add missing unit tests for `config.Load` branches, `migrations/embed` surgery + ordering + idempotency, `middleware` spoofed-proxy/X-Real-IP/IPv6 paths, `uuidV7`/cursor round-trip + malformed input, OTP exactly-at-expiry + handler-vs-store expiry reachability, refresh reuse/TTL-boundary/concurrency ordering, burst-429 with isolated buckets, email template/HTML-absent/global-mutation paths, `ListEntries` cursor/`to<from` edges, tombstone/409/404 handler mapping; iOS `RootView` gate ordering + rapid re-login guard + shutdown deadline + `localStoreOpenError` path, `AppContainer` open/close/erase scope, Track deferred-start cancel/hardware-keyboard/external-stop/ticker races, `HistoryViewModel.loadIfNeeded` gate, pull-model mid-cycle loss, `SyncController` merge-convergence matrix, `LocalStore` seeding idempotency/LWW/remap guards, standalone `UndoBufferStore` cold-launch commit, `SessionCache`/`Connectivity`/device-identity/resolver edges, `LogTime` EDIT/LOCKED routing, Insights empty-state + lens switch; replace brittle `LocalizationTests allCasesCount == 148` with a sorted-keys snapshot; add openapi contract pins for `/entries/recents`, `modified_since` on categories, and create-422-vs-prune.

## Capabilities

### New Capabilities

None — no new user-visible behavior is introduced.

### Modified Capabilities

Wording-only sync (no behavior change — delta specs correct stale text to match shipped behavior):

- `local-first-store`: remove `activity` resource/wording + 30s wall-clock window (restart-persistent buffer, commit-on-cold-launch only).
- `entry-editor`: same undo-window correction + name/text (not activity) wording.
- `timer-capture-experience`: plain-text + Recents + name-picker wording (no "Choose/Select activity").
- `manual-entry`: name/text wording + resolve "No activity chosen" contradiction.
- `category-management`: entry-tag (not activity) assignments + restart-persistent undo wording.
- `insights-breakdown`: `By category | By text` lens wording (not `By activity`).
- `sync-client`: drop "like activities do" + align create-422-vs-merge-prune + tombstone wording.
- `app-shell`: remove Enable-Sync sheet scenarios (signed-in-only gate).
- `entry-provenance`: entry (not activity) wording.
- `history-entry-list`: entry-text (not activity identity) wording.
- `account-bound-store`: timer draft/name wording (not "activity").
- `lock-screen-controls`: clarify signed-out/locked-state wording vs no-signed-out-features rule.

## Impact

- Code: `backend/internal/{migrations,db,handlers,config,email,server}`, `backend/api/openapi.yaml` (prose + missing paths), `ios/TimeOfLife/{Features/TimeTracking,Features/ManualEntry,Features/Catalog,Features/AppShell,Features/Auth,Features/Sync,Core/{Theme,Design/Components,DI,Storage,Utilities,Localization}}`, `project.yml`, `.swiftlint.yml`.
- Docs/specs: `AGENTS.md`, `openspec/config.yaml`, `openspec/README.md`, `docs/project-context.md`, `README.md`, `Requirements/`, `Design/`, `docs/history-roadmap.md`, delta specs listed above.
- Tests: new `config_test.go`, `embed_test.go`, `middleware_test.go`, `uuid/shared-cursor` tests, handler/DB edge tests, `AppContainer`/`RootView`-gate/`Track`-race/`SyncController`-matrix/`UndoBuffer`/resolver/connectivity tests, contract tests; linters + both suites must stay green (`golangci-lint`, `swiftlint --strict`, `gofmt -l` empty, `go test ./...`, `xcodebuild test`).
- Non-goals: no Postgres/SQLite engine unification; no new endpoints or behavior; no on-disk migration for shipped users (pre-release — edit shapes in place); no new dependencies without justification (S1); no hand-edited `.pbxproj`.
