## Context

See proposal.md — Why. Current state: `HistoryView` / `InsightsView` use a guarded reload (`needsReload` + `loadIfNeeded` on `.task` / `onAppear`, `invalidate()` on `onDisappear`). `refreshSignal` only covers the running-timer save path. `SyncController` (`@MainActor`, session-gated, single-flight) merges relay state into `LocalStore` (the single mutation chokepoint, D1) and publishes `status` (`inactive` / `syncing` / `idle(Date)` / `error`). Presenting the Profile sheet over History does not fire `onDisappear`/`onAppear` on the covered view, and `AppShellView`'s Profile-sheet `onDismiss` only reloads `trackVM` — so a `syncNow` pull completes with `needsReload == false` and the list stays stale until the next tab switch.

Constraints: LocalStore stays the single mutation chokepoint; views observe `SyncController` directly (nested reads through `AppContainer` never invalidate — ProfileView precedent); no backend/OpenAPI changes; iOS 15+ (no iOS 16-only `if` in toolbar scope); `Theme` colors only; strings via `L10n` (no new strings expected).

## Goals / Non-Goals

**Goals:**
- History and Insights reflect a completed sync cycle while visible, including Profile-sheet Sync now, with no tab switch.
- Reuse the existing `invalidate()` / `loadIfNeeded()` chain — no new loading machinery.

**Non-Goals:**
- No LocalStore Combine publisher refactor; no realtime push; no background-fetch changes; no sync-cycle changes (drain/pull/LWW/tombstones untouched); no visual or copy changes.

## Decisions

- **Observe `SyncController.status` transitions in `HistoryView` and `InsightsView` (not Profile-dismiss callbacks, not a LocalStore publisher).** Both views already own a `vm.invalidate()` + `loadIfNeeded()` path; adding `.onChange(of: sync.status)` (via `@EnvironmentObject var sync: SyncController`, ProfileView precedent) that invalidates + reloads on leaving `.syncing` (to `.idle` or `.error`) fixes manual, foreground, and connectivity triggers uniformly, including auto-sync while the tab is visible. Alternatives considered: Profile-sheet `onDismiss` invalidating history — rejected (misses auto-sync while History is visible and couples the shell to the History VM it cannot reach); a GRDB observation publisher on `LocalStore` — rejected (correct long-term but scope creep: new publisher surface, threading, and test surface for a one-line invalidation bug); extending `refreshSignal` with the sync date from `AppShellViewModel` — rejected (indirect; status observation is the existing published signal).
- **Reload on both `.idle` and `.error` exits from `.syncing`, guarded by the existing `isLoading`/`needsReload` re-entrancy guard.** A failed cycle may have applied partial merges before throwing, so the list must still re-read; the guard makes redundant reloads cheap. Alternative (reload on `.idle` only) rejected — leaves partial-merge failures stale.
- **Keep `onDisappear → invalidate()` and the sheet/edit-dismiss reloads untouched.** They remain the correctness net for Track saves and entry-form edits; the sync observer is additive.

## Risks / Trade-offs

- [Risk] Reload flashes content while the user is scrolled deep → Mitigation: reuse `loadIfNeeded` (no spinner unless empty); day-group rebuild preserves scroll position in practice; no explicit animation.
- [Risk] Rapid successive cycles (foreground + connectivity + manual single-flight) trigger redundant reloads → Mitigation: existing `needsReload`/`isLoading` guard serializes; last cycle wins.
- [Risk] `onChange` firing while the Profile sheet still covers History causes a behind-sheet reload → Acceptable: load is cheap and the fresh list is visible the moment the sheet dismisses (the reported bug's desired outcome).
