## 1. Never-synthesize conflict recovery (GUID corruption)

- [x] 1.1 Remove both stub paths in `SyncController.remapReferences` (activity stub + category fallback stub): winner-fetch failure rethrows, keeping the outbox row queued for retry; local records keep their real names until the real winner arrives.
- [x] 1.2 SwiftTesting coverage in `SyncControllerTests` (established fakes + temp store): `category_exists` with failing winner-fetch merges nothing, keeps the outbox row, and leaves the local name intact; same for `activity_exists`; successful fetch still remaps + clears as before.
- [x] 1.3 Verify the rename-heal on a temp store mirroring the poisoned shape (UUID-named local row carrying the winner id): renaming bumps `updated_at` and the LWW push adopts the real name — document the user-facing repair (rename in Manage Categories; never delete) in the change summary.

## 2. Single syncing indicator (duplicate status)

- [x] 2.1 Keep the Sync Now button titled "Sync now" (still disabled) while syncing; the status row stays the only "Syncing…" surface.
- [x] 2.2 Simulator pass while running: exactly one "Syncing…" row on Profile.

## 3. Failure transparency (message + logging)

- [x] 3.1 Surface `SyncStatus.error(message)` in Profile's error row (generic title stays primary, message as secondary line with generic fallback); log cycle start/finish/failure-with-code via `Logger` (`sync` category; secret-free strings only — no tokens, bodies, or emails).
- [x] 3.2 SwiftTesting coverage: failed cycle exposes its message through `status`; no test asserts secret content (tokens/bodies never enter the logged/surfaced strings — verify by construction review).

## 4. Verification and docs

- [x] 4.1 `swiftlint lint --strict` clean; `xcodebuild -scheme TimeOfLife -destination '<available simulator>'` warning-free build; `xcodebuild test` green; backend untouched (`go build`/`go test` not required — no backend changes).
- [x] 4.2 Re-check `Requirements/FURPS/Timetracking.md` F5–F8 rows + `Common.md` for conflicts; fix or reconcile (expected: none — same protocol, stricter recovery).
- [x] 4.3 Update `docs/project-context.md` only if architecture/contract/run steps changed (expected: sync-plane bullet gains the never-synthesize rule in one line); no OpenAPI changes.

## 5. SE-sim follow-ups (user-reported 2026-09-16: frozen "Syncing…", Sync-now looks enabled)

- [x] 5.1 Observe `SyncController`/`SessionStore` directly in `ProfileView` (separate environment objects from `TimeOfLifeApp`, mirroring `session`/`navigation`): nested reads through `AppContainer` never invalidate the view. Same latent fix for `ManageCategoriesView.reload-on-idle` (`.onChange(of: sync.status)`). Dim Sync-now with `.opacity(0.6)` while syncing (`.disabled` alone does not restyle custom labels; WelcomeView precedent).
- [x] 5.2 Decode relay categories/entries as RFC 3339 via `CategoryWireDTO`/`EntryWireDTO` (`WireDate` container helpers): the local models' default `Double` decoding broke every non-empty pull (`typeMismatch` on `created_at`), which the frozen UI then hid as eternal "Syncing…". Repository tests with OpenAPI-shaped fixtures (plain + fractional seconds, nullables, envelope).
- [x] 5.3 Verify on iPhone SE (1st gen, iOS 15.5) sim: launch-triggered sync reaches "Last synced" in pixels with no manual refresh; manual Sync-now completes; Manage Categories lists the 7 pulled categories. Lint strict clean; 516/516 tests green.
