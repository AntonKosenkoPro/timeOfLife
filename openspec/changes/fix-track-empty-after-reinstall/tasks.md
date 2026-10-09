## 1. Reproduce on current tree

- [x] 1.1 Record the reinstall repro on the unmodified tree: fresh simulator install → sign in → observe (a) login-screen duration before shell, (b) Track recents/categories emptiness on first paint, (c) name-picker list emptiness, (d) Track state after tab switch and back. Save evidence (screen recording + timestamps) with the change.
- [x] 1.2 Encode the ordering race as a failing test: bind-then-sign-in harness asserting the shell cannot mount before `categoryStartersSeeded()` is true for the account file; assert Track's first `load()` snapshot is non-empty for categories after a seeded sign-in.

## 2. Seed-before-reveal ordering

- [x] 2.1 Reorder `RootView.beginSignIn` to open → `commitAll` → `seedStarterCategoriesIfNeeded` → set `boundUserID` (reveal) → `syncController.activate`; keep both cancellation/session-match guards before the reveal line and keep `activate` fire-and-forget after it.
- [x] 2.2 Extend `AuthGateTests`/`ComplexitySliceTests`: failed seed keeps the bind-failure gate (no shell mount, sign-out escape works); rapid sign-out mid-bind still cancels without revealing or activating sync for the stale account.

## 3. Track sync-exit reload

- [x] 3.1 Observe `SyncController.status` in the Track scope (environment object, History/Insights precedent) and reload `trackVM` once on exit from `.syncing` (`.idle`/`.error`); guard against concurrent loads and never blank the last good snapshot on failure.
- [x] 3.2 Add Track reload tests: sync-exit after a seeded pull fills recents/allNames/categories without tab switch; error-after-partial-merge still reloads; typing draft (`nameDraft`) survives the reload.

## 4. Restoring splash

- [x] 4.1 Add a restoring flag around `restoreSession()` in `RootView`: splash (spinner, `Theme` colors, existing L10n only) while unresolved; auth flow only on resolved signed-out; flag always clears (`defer`), offline-with-cache resolves signed-in.
- [x] 4.2 Add gate tests: cached-session launch never renders `AuthFlowView` before resolution; no-session launch renders auth without splash hang; slow/offline restore cannot stick the splash.

## 5. Verify and close out

- [x] 5.1 Re-run the identical 1.1 repro on the fixed tree and record evidence: no login flash on restorable launch, starter categories on first Track paint, recents converge after first sync without tab switch.
- [x] 5.2 Run `swiftlint lint --strict`, warning-as-error `xcodebuild build`, and the iOS suite per `docs/ios-test-loop.md` (one `xcodebuild` at a time); re-check `Requirements/FURPS/` rows for auth/launch/Track.
- [x] 5.3 Update `docs/project-context.md` if the lifecycle description changed; confirm no OpenAPI, `project.yml`, strings, or migration changes are needed.
