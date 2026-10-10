## Context

See proposal.md (Why) for motivation. Current state (`RootView.beginSignIn`, `RootView.swift:122-142`): `openLocalStore → boundUserID = id` (shell mounts, `TrackView.task { load() }` fires) `→ commitAll → activate → seed`. Track loads concurrently with seeding and the first-sync pull, caches the empty snapshot, and never reloads — History (`HistoryView.swift:127-134`) and Insights (`InsightsView.swift:59-67`) already observe `sync.status` and self-heal; Track does not. The gate's initial state is `.signedOut` (`SessionStore.swift:8`), so `restoreSession()` always flashes the auth flow on cold start. Constraints: LocalStore is the single mutation chokepoint; signed-in offline keeps working (no global banner); `AppContainer` publishes nothing so views must observe `SyncController` directly (ProfileView precedent); per-iteration rules (S5) apply at implementation.

## Goals / Non-Goals

**Goals:**
- Shell mounts only after bind + commitAll + seed; first-sync pull stays background.
- Track converges on pulled data without tab switch, reusing the History/Insights observer pattern.
- Restoring splash replaces the login flash while `restoreSession()` is unresolved.

**Non-Goals:**
- Gating reveal on first-sync completion; GRDB ValueObservation/live queries; offline semantics changes; storage migration; auth/Track visual redesign. No new user-facing strings beyond reusing existing L10n keys where possible (U4: any new splash copy needs en+ru + `L10n`).

## Decisions

### 1. Seed-before-reveal (move `boundUserID = userID` after commit + seed)
`beginSignIn` becomes open → commitAll → seed → reveal → activate. Local work is deterministic and fast (one file open + one marker-checked transaction + 7 idempotent inserts); the shell's first paint then carries categories. `activate()` is fire-and-forget either way, so the pull still races — but against a seeded store, not an empty one.
*Alternative (reveal immediately, seed lazily):* rejected — preserves the exact empty-paint race for categories.

### 2. Track observes `sync.status` (History precedent, not GRDB observation)
Pass `SyncController` into the Track scope as an environment object (same as History/Insights) and reload `trackVM` on exit from `.syncing` (`.idle`/`.error`), guarded against concurrent loads. Reuses the proven pattern; no new observation machinery, no extra DB traffic while syncing.
*Alternative (GRDB ValueObservation on entries/categories):* rejected — heavier, new pattern, no precedent in the codebase; the coarse cycle-exit reload already converges.

### 3. Restoring splash via an explicit restoring flag (not a SessionStore third state if avoidable)
Gate order becomes restoring? → splash : signedOut? → auth : signedIn? → spinner/shell. The flag is set before `restoreSession()` starts and cleared when it resolves; a failed/slow restore falls back to the auth flow (never a stuck splash). Keeps `SessionState` binary if the flag can live in `RootView`; promote to `SessionStore` only if tests need it.
*Alternative (optimistic-only fix in `AuthService`):* rejected — cache-miss reinstalls (App Group defaults wiped, Keychain surviving) have no optimistic path; the flash is structural.

### 4. Keep `activate()` after reveal, keep deactivate→wait→close discipline
No change to `beginSignOut` / `waitForSyncShutdown` / same-account guard. The reorder only moves local synchronous work earlier; sync lifecycle stages are untouched.

## Risks / Trade-offs

- [Risk] Seeding throws (invalid names, disk error) → shell never reveals → Mitigation: failed seed keeps the existing bind-failure gate (`localStoreOpenError` branch) with its sign-out escape hatch; seed failure is surfaced, not silent.
- [Risk] Sync-exit reload fires while user is typing a name draft → Mitigation: `load()` only replaces recents/allNames/categories + reconciles running state; it never touches `nameDraft` except restoring a persisted running draft (existing behavior).
- [Risk] Rapid sign-out mid-bind still races → Mitigation: existing `lifecycleTask` cancellation + session-match guards stay; the moved reveal line keeps both guards before it.
- [Risk] Splash stuck on offline restore → Mitigation: `restoreSession` keeps cached session on transport failure (existing catch-all); the restoring flag clears in a `defer`, and offline-with-cache resolves to signed-in, offline-without-cache to auth — never an indefinite spinner.
- [Trade-off] First paint waits for seed (~ms) instead of mounting instantly — accepted: deterministic local work in exchange for no empty flash. Network pull never blocks.

## Migration Plan

No migration (pre-release, no backward-compat rule). Rollback: revert the three file groups independently (ordering, observer, splash are orthogonal). No OpenAPI/backend change.

## Open Questions

None blocking — the reinstall storage-survival question (does the App Group DB survive reinstall on device vs simulator?) is answered empirically by the repro task, not by design.
