## 1. Backend device-sessions foundation [P after kickoff; single change, reviewable alone]

- [x] 1.1 Thread `X-Device-Id` through verify/apple/refresh/logout into `issueTokens` (stop passing `""`); persist `device_id` on every refresh row (sqlite + postgres).
- [x] 1.2 Scope reuse-detection and logout per-device (`user_id + device_id` revoke; stale token kills only its family); add per-family revoke query to both stores + optional `(user_id, device_id)` index.
- [x] 1.3 Enforce refresh TTL against `created_at` (currently computed but unenforced); rejected families return unauthorized with lock-not-wipe semantics.
- [x] 1.4 Backend tests: per-device rotation stays in family; reuse kills only its family; logout revokes only caller; expired TTL rejected; Apple path stores `device_id`. `go test ./...` green.

## 2. iOS auth gate (root) [P vs group 1; touches RootView/Auth only]

- [x] 2.1 Gate `RootView` on `SessionStore`: signed-out renders auth flow full-screen (never Track/shell); signed-in renders `AppShellView`. Move seed + `commitAll` + first sync trigger to post-sign-in/restored-session path.
- [x] 2.2 Retire `EnableSyncPresenter`/`EnableSyncSheet`, Profile "Enable Sync" row, History signed-out/offline notice branches; keep `OfflineBanner` (offline signed-in stays in app).
- [x] 2.3 Reword Welcome/OTP/Apple copy to required voice ("Log in to start tracking") in code + `L10n`.
- [x] 2.4 Auth-gate tests: signed-out shows gate (never shell); restore-then-gate transitions; logout returns to gate with files intact.

## 3. iOS per-account store [P vs groups 1–2; single writer: LocalStore.swift]

- [x] 3.1 Per-user DB URL (`lifio_<userId>.db` in App Group) + active `user_id` marker; `AppContainer` builds `LocalStore` lazily/swaps on sign-in (incl. `UndoBufferStore`, UITesting harness).
- [x] 3.2 First login adopts/creates file + per-account starter seeding; re-login reopens/resumes (no re-pull); logout closes and keeps all files with dirty outbox + timer draft intact.
- [x] 3.3 Per-account Erase deletes only the active file (+ its session artifacts); never a side effect of logout/switch/revoke.
- [x] 3.4 Store tests: per-user isolation, resume-after-relogin, logout-keeps, erase-active-only, seed-per-file; update single-DB helpers (`temporaryStoreURL` call sites) to user-keyed URLs.

## 4. Sync same-account guard + Controls [P vs groups 1–3 after 3.1 lands]

- [x] 4.1 `SyncController` records bound `userId`; skips/refuses cycles on mismatch (never pushes A's outbox under B's token; mid-cycle account change aborts); cursors ride the per-user file.
- [x] 4.2 Controls/widgets read the active account file only; signed-out shows locked/empty state, never anon or dormant-account data.
- [x] 4.3 Sync/controls tests: mismatch-guard, resume-drain on re-login, control locked-state with no active file.

## 5. Localization (single writer: strings files) [after 2.3 copy freeze]

- [x] 5.1 Add new strings to both `en.lproj` and `ru.lproj` + `L10n` (`allCases` in `LocalizationTests`); remove orphaned Enable-Sync strings.

## 6. API contract + docs (single-writer files serialize: openapi.yaml, project-context.md) [P vs code groups once semantics freeze]

- [x] 6.1 `backend/api/openapi.yaml`: `X-Device-Id` on auth endpoints, per-device refresh/logout semantics and error codes; explicitly NO `device_limit` (deferred to #46). Backend contract gate green.
- [x] 6.2 `docs/project-context.md` (Architecture/Auth/Incomplete/Routing) + `README.md` (launch + smoke checklist) + `Requirements/FURPS` rows (anonymous-use removal, per-account seeding, lock-not-wipe).

## 7. Verification (serial: one xcodebuild at a time, one simulator per run)

- [x] 7.1 Linters + builds green: `golangci-lint run`, `gofmt -l .` empty, `go vet ./...`; `swiftlint lint --strict`, warning-as-errors `xcodebuild` build (see `docs/ios-test-loop.md`: booted-sim-by-ID, `-only-testing` filters, log-file polling).
- [x] 7.2 Both suites green: `go test ./... -cover`; `xcodebuild test -scheme TimeOfLife -destination '<available simulator>'`.
- [x] 7.3 `openspec validate --all --strict` green; FURPS re-check per S5; dead code (presenter/sheet/signed-out branches, `""` device id) removed.

## 8. iOS device identity (gap found in Wave 3 verification; blocks sign-in vs new backend)

- [x] 8.1 Mint stable device UUID on first need, persist in Keychain (survives reinstall; restore-on-new-phone re-mints on fingerprint change or documents reuse). — `DeviceIdentityStore` (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` items never travel in backups, so a new phone has no stored id and mints fresh; documented in code, #46 untouched).
- [x] 8.2 Send `X-Device-Id` on verify/apple/refresh/logout (APIClient/APIEndpoint plumbing); missing-header path never triggers client-side. — `deviceIdProvider` on `APIClient`, wired from `DeviceIdentityStore` in `AppContainer.makeAuthClient`.
- [x] 8.3 Tests: UUID stability across launches, header present on auth requests, reinstall-restore behavior documented. — `DeviceIdentityStoreTests`, `APIClientDeviceIdHeaderTests` (header on verify/apple/refresh/logout), no-provider omission test; xcodebuild left to the verifier.

## Parallel execution plan (fan-out 6 default, ceiling 9)

- Wave 1 (no deps between waves): Group 1 (backend agent) ‖ Group 2 (iOS-auth agent) ‖ Group 3 (iOS-store agent) ‖ Group 6.1 draft (contract agent, semantics-frozen assumption) — 4 agents.
- Wave 2 (after 3.1): Group 4 (sync agent) ‖ Group 5 (l10n agent after 2.3) ‖ Group 6.2 (docs agent) — 3 agents.
- Wave 3 (serial): Group 7 verification, single runner.
- Serialize single-writer resources always: one `xcodebuild` at a time; `openapi.yaml`, `project-context.md`, `Localizable.strings` one writer each; never concurrent `xcodegen generate` with project edits.
