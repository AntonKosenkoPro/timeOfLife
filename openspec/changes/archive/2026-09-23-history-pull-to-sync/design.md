## Context

See `proposal.md` for motivation. Current state shaping this design (see `docs/project-context.md` for the canonical architecture):

- `HistoryView` is `ScrollView + LazyVStack(pinnedViews:)` (not `List`), with a `HistoryViewModel` snapshot (`dayGroups` + `needsReload` guard) and an existing `.onChange(of: sync.status)` reload on cycle exit (`.idle`/`.error`). That observer stays the sole reload path.
- `SyncController` (`@MainActor`) is session-gated (`activate` on `.signedIn`, `deactivate` on `.signedOut`) and connectivity-gated (`runCycle` fails `offline` when disconnected). `trigger()` has a single-flight guard (`cycleTask != nil → return`, fire-and-forget); `syncNow()` has none (awaits `runCycle` directly, allowing overlap).
- Enable Sync sheet ownership lives in `ProfileView` (`EnableSyncPresenter` + `EnableSyncSheet` wrapping `AuthFlowView`). History has no presenter and no auth entry point.
- `.refreshable` is available on the iOS 15+ floor and works on `ScrollView`; its spinner lifetime equals the closure's await duration and its content slot is system-owned (custom banners render below the nav bar, not inside the spinner).

## Goals / Non-Goals

**Goals:**

- Pull becomes the fourth sync trigger with join-instead-of-fork semantics shared with Profile "Sync now".
- Signed-out/offline pulls give immediate inline verdicts without burning cycles or touching Profile status.
- Pull-initiated failures surface once (dialog), background failures stay silent on History.

**Non-Goals:**

- No explicit local reload in the pull path; no GRDB observation publisher; no empty-state pull; no dialog Retry; no History "Last synced" caption; no cross-process or midnight-rollover handling (see live-History follow-up).

## Decisions

### D1 — `.refreshable` on the populated-list branch only; no explicit reload

Attach `.refreshable` to `historyList` (the non-empty branch), not the `ZStack` root or `EmptyState`. The closure contains only the sync verdict flow (signed-out banner / offline banner / await cycle); it never calls `vm.load()` — the existing `sync.status` observer performs the only reload. Alternatives considered: explicit reload after `syncNow()` — rejected (double-load with the observer, and contradicts the sync-only scope); attaching to the root so empty pulls work — rejected per spec (explicit non-goal).

### D2 — Join lives in `SyncController.syncNow`, not in the view

`syncNow` awaits the in-flight `cycleTask`'s result when present instead of starting `runCycle` concurrently; `trigger()` keeps its early-return guard. Rationale: one rule for all callers (pull + Profile button both fixed), atomic-ish check-and-attach on `@MainActor` (the boundary race — cycle ending between check and attach — degrades to a cheap no-op fresh cycle since cursors just advanced). Alternatives considered: view-side `guard status == .syncing → return` — rejected (spinner would flash with no wait, violating the join requirement); view-side await-a-published-handle — rejected (exposes internals; the controller owns the task).

### D3 — Verdicts render below the nav bar; spinner is never customized

Banners are a History-scoped inline notice (same visual slot for signed-out and offline, one at a time, newest pull wins); the dialog is `.alert` (house precedent: Profile erase-confirm, LogTime alerts). Rationale: the spinner slot is system-owned and cannot host custom content or links. Alternatives considered: custom `UIRefreshControl` via introspection — rejected (fragile, fights pinned-header geometry tracking).

### D4 — Pre-check session + connectivity; mid-cycle flap routes to dialog

Order in the closure: signed-out → signed-out banner; `!isConnected` → offline banner; else await (fresh or joined) cycle and map `.error` → dialog. Rationale: avoids burning cycles and polluting Profile status for known-in-advance verdicts. A flap after start is genuinely a cycle failure, so the dialog owns it. Connectivity read from the existing `Connectivity` object (same source as `OfflineBanner`).

### D5 — Pull-in-flight flag gates the dialog

A History-local flag set on pull entry and cleared on resolution; the `.error` → dialog mapping fires only when the flag is set. Rationale: `sync.status` is global — background foreground/connectivity cycles fail through the same property while History is visible. Without the flag every background failure would modal-pop. Alternatives considered: presenting on every `.error` — rejected (hostile).

### D6 — Enable Sync sheet reused via shared presenter ownership

Move (or hoist to the shell and pass down) the `EnableSyncPresenter` + `EnableSyncSheet(AuthFlowView)` pattern so History's banner link opens the identical sheet as Profile's row (silent restore first, sheet iff still signed out, dismiss on sign-in flip). Rationale: exactly one auth entry flow (no second implementation to drift). Banner link is the only new caller of the existing `enableSync()` path.

### D7 — Banner lifetime: 5s Task with reset + cancel + early-dismiss

One cancellable dismiss task: re-pull cancels and restarts it; tab leave / view disappear cancels it; successful sign-in (session flips) dismisses the banner immediately since first-sync takes over. Copy is short with a single link (`Sign in to sync. [Sign in]` shape; offline has no link) and goes through `L10n` EN+RU (U4), `Theme` colors only.

## Risks / Trade-offs

- [Risk] Sync burst (N `mergeEntry` writes per pull) re-renders repeatedly via the status-exit reload only once — safe today, but a future live publisher would need coalescing → Mitigation: this change keeps the single cycle-exit reload; note the coalescing requirement in the live-History follow-up.
- [Risk] `Task.sleep(5)` dismissal races re-pull, disappear, and sign-in → Mitigation: single stored handle, cancel-before-replace discipline, cancel on disappear.
- [Risk] Server error text is English-only pass-through in the dialog body → Mitigation: localized title + pass-through body (accepted; secret-free convention already holds).
- [Risk] Joined-cycle error shows the dialog to a user who only waited, not started, the work → Mitigation: accepted by spec (they asked via pull); background-only failures stay silent via D5.
- [Risk] VoiceOver users mid-read when the banner auto-dismisses → Mitigation: accepted for v1; named as polish (persist while accessibility focus is inside).

## Migration Plan

No migration: additive UI + one controller semantic change (join). Rollback is revert of the change. No schema, outbox, or OpenAPI touch.

## Open Questions

None — copy finalization (exact banner/dialog strings EN+RU) happens at implementation within the `L10n` step.
