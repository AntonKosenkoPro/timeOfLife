## 1. Docs-contract sync (wording-only, no behavior)

- [x] 1.1 Fix routing pointers: `AGENTS.md` active-change + baseline count, `openspec/config.yaml` optional-relay + baseline list, `openspec/README.md` 13→19 list + "active changes", `docs/project-context.md` 18→19 + archive list + active-change wording, `README.md` optional-relay + active-change note
- [x] 1.2 Sync `Requirements/`: rewrite `Usecases/Activity_Catalog_and_Categories.md` (no activities, mandatory gate, entry-grouped Recents, restart-persistent undo), fix FURPS `Activity_Catalog_and_Categories.md` F2 signed-out line, fix `Timetracking.md` S3 stale filename pointer
- [x] 1.3 Sync `Design/`: AppShell/Auth/INTERACTIONS mandatory-gate + no-Enable-Sync, COMPONENTS activity sheets/rows/dialogs + UndoToast body, ManageCategories/CategoryEditor entry wording + RU 30s→restart, TimeTracking iOS-15 checklist + namePlaceholder voice, rename `Activity_Catalog_API.md`→`Entry_Catalog_API.md` + fix citations, TOKENS management-icons note
- [x] 1.4 Sync `docs/history-roadmap.md` vs `docs/project-context.md` incomplete list (fold or mark archived; resolve via-labels done-vs-deferred contradiction)
- [x] 1.5 Sync `backend/api/openapi.yaml` prose: header recents sentence, document `GET /entries/recents`, document `modified_since` on `GET /categories` (or align handler+FURPS+Design first), resolve create-422-vs-merge-prune contradiction, 30s-window→restart-persistent wording
- [x] 1.6 Run `openspec validate --all --strict` green

## 2. Backend simplicity (no behavior change)

- [x] 2.1 Migrations: sequential renumber (kill duplicate `004`), squash create-then-drop chain, add `schema_migrations` table, keep `adaptToSQLite` minimal + named consts
- [x] 2.2 Config threading: `maxAttempts`/access-TTL/refresh-TTL/HTTP timeouts via `config`; unify `Pool()`/`DB()` naming; drop `configError.field` / trivial getters or inline
- [x] 2.3 Handler helpers: collapse `decodeJSON` nil-writer hack, `versionDetails/idNameDetails` any-switch, `parseRFC3339` fallback, `optTime`-vs-`validateTimestamp` split, per-handler limit re-validation → shared clamp; normalize `""`→nil in validator
- [x] 2.4 Hygiene: remove committed `backend/coverage.out` + gitignore, verify `.env` untracked, fix `emailRegex` vs `net/mail`, `flexibleBool` unknown-shape, `uuidV7` rand error, CORS reflect-all, SES-console fallback, TRUSTED_PROXIES silent-continue, swallowed `Execute`/`parseTime` errors (log or return)
- [x] 2.5 Verify: `gofmt -l .` empty, `go vet ./...`, `golangci-lint run`, `go test ./... -cover` green

## 3. iOS simplicity + dead-code retirement (no behavior change)

- [x] 3.1 Types: unify `RecentEntry`×4 → one `ExactName` + single mapper; fold `AuthValidator` raw keys into `L10n`
- [x] 3.2 Components: extract `FieldCard` / `EditorToolbar` / `DestructiveBottomButton`; centralize duration formatters + `DynamicTypeMetrics` + `FocusDelay`/ticker idiom; tokenize magic opacities
- [x] 3.3 Retire: deferred-start prod path, `waitForSyncShutdown` poll → publisher, `TrackLayoutSpike` out of app target, dead `undoBuffer` param / unused Theme tokens / `(legacy)` comment, double seeding → gate-only
- [x] 3.4 Safety/lint: replace `fatalError`/`try!` crash paths with surfaced errors, fix `Theme`/`L10n` bypasses + preview hardcoded strings, resolve contradictory `swiftlint` entries, scope ATS exception to Debug
- [x] 3.5 Verify: `swiftlint lint --strict`, `xcodebuild build` warnings-clean, `xcodebuild test` green (one run at a time)

## 4. Test coverage (pin refactored behavior)

- [x] 4.1 Backend units: `config.Load` branches, `embed` surgery + ordering + idempotency, `middleware` spoofed-proxy/X-Real-IP/IPv6, `uuidV7` + cursor round-trip/malformed, OTP expiry-boundary + store-vs-handler reachability, refresh reuse/TTL-boundary/concurrency, burst-429 isolation, email HTML-absent/global-mutation, cursor + `to<from` + tombstone/409/404 mapping
- [x] 4.2 iOS units: `RootView` gate ordering + rapid re-login + shutdown deadline + `localStoreOpenError`, `AppContainer` open/close/erase, Track cancel/keyboard/external-stop/ticker races, `HistoryViewModel.loadIfNeeded` + pull mid-cycle loss, `SyncController` merge-convergence matrix, `LocalStore` seeding/LWW/remap guards, standalone `UndoBuffer` cold-launch, session/connectivity/resolver edges, `LogTime` EDIT/LOCKED routing, Insights empty-state + lens switch
- [x] 4.3 Contract: openapi pins for `/entries/recents`, `modified_since` on categories, create-422-vs-prune; replace `allCasesCount == 148` with sorted-keys snapshot
- [x] 4.4 Full verify: both linters + `gofmt -l` empty, `go test ./...` + `xcodebuild test` green, FURPS re-check, `docs/project-context.md` + `README.md` updated; note any real bugs found as follow-up behavior changes (do not smuggle fixes here)
