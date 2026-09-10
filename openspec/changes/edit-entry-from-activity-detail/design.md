## Context

See proposal.md (Why) for motivation. Current state constraining the approach:

- `HistoryView` (tab root inside the History `NavigationView`) presents `ActivityDetailView` via `.sheet(item:)`; detail rows (`ActivityEntryRow`) are inert by spec. `ActivityDetailView` owns its own `NavigationView` and stacks `ActivityEditorView` and `LogTimeView` as sheets, each with its own `NavigationView`.
- `LogTimeView` + `LogTimeViewModel` implement the Calendar-grammar form (Activity row via shared `ActivitySearchHosting` picker + quick-create, Starts/Ends pills with inline single-open pickers, `isAddEnabled` validity gate, Start-push duration preservation) saving through `TimerService.store.createEntry` (`source:"manual"`).
- Store layer is complete: `LocalStore.entry(id)`, `entries(activityID:)`, `updateEntry` (LWW, `false` when stale), `undoBufferEnter/Restore/CommitExpired`, plus `UndoBufferStore` (`enter`/`undo`/`commitExpired`, 30 s wall-clock) and global foreground reconciliation in `RootView`. `ManageCategoriesViewModel` is the precedent for `performUndo` + `registerSystemUndo(with:)` + `.onShake` / `ShakeHostingController` wiring (D3, U7).
- Invariants (S7, `docs/project-context.md`): `LocalStore` is the single mutation chokepoint (no raw GRDB writes outside it); iOS 15+ floor (`NavigationStack` unavailable, `NavigationView(.stack)` only); `Theme` semantic colors only; EN+RU strings + `L10n` (U4); no on-disk backward compat (pre-release — no migration needed); OpenAPI untouched (no backend change).

## Goals / Non-Goals

**Goals:**

- One entry form (CREATE/EDIT/LOCKED) with a single Calendar-grammar layout, gate, and picker, so create and edit can never visually diverge.
- Entry correction and entry deletion end-to-end (ActivityDetail row → form → save/delete → refreshed lists) with undoable-delete semantics from day one, minus the toast UI.
- Presentation that adds exactly one modal boundary (full-screen cover over the detail sheet) instead of a third stacked sheet.

**Non-Goals:**

- UndoToast UI (deferred to history-roadmap §8 — this change ships the buffer semantics it will sit on).
- History swipe-to-delete, History filtering, dirty-draft protection, activity-scope deletion, running-session surfaces.
- Any change to sync protocol, outbox shape, or backend (D2/D4–D6 untouched).

## Decisions

### 1. Grow `LogTimeView`/`LogTimeViewModel` into the unified form (over a new `EntryEditor` + read-only `EntryDetail`)

The roadmap's original read-first `EntryDetail` assumed "looking vs changing" separation, but an entry is three fields — a prefilled form *is* the review surface, and Cancel discards, so accidental mutation is impossible. Reuse (over a parallel form) keeps the Calendar grammar, validity gate, duration-preservation, and `ActivitySearchHosting` picker in one place; `LogTimeViewModel` gains an edit draft (`initialEntry`: prefilled activity/starts/ends, `save()` branching to `updateEntry`, mode enum driving titles/actions) rather than a forked VM. Alternative (separate detail + editor) was rejected in exploration: two surfaces to keep in sync for a three-field object.

### 2. Full-screen cover for EDIT/LOCKED (over stacking a third sheet, pushing inside the sheet, or full push)

Stacking a third sheet (detail → form → picker) was rejected as rickety. Full push (History → detail → form via `NavigationLink`) was rejected: it loses the detail sheet's medium-detent peek, collides with the shell's deliberately single-scope `ShellToolbar` on iOS 15, and `NavigationLink` in `ScrollView`/`LazyVStack` on iOS 15 `NavigationView` carries known reliability quirks the sheet bindings avoid. Push-inside-sheet keeps peek but imports the same iOS 15 link risk plus sheet-dismiss/edge-pop gesture coexistence. `fullScreenCover` keeps modal Cancel/Save semantics (and future dirty-guard via `interactiveDismissDisabled`), hides the tab bar for a focused task, is iOS 15-safe, and reads as "new screen" rather than "another card" — one presentation-line change class with the smallest spec delta. CREATE keeps its sheet presentation (spec-pinned).

### 3. Delete into the durable buffer with confirm, no toast, shake-to-undo (over immediate hard delete)

`deleteEntry`-immediate would make a later toast a semantic migration; routing through `UndoBufferStore.enter` now means §8 adds only UI. Needs a small entry-snapshot restore helper mirroring `undoCategoryDeletion` (payload = serialized `TimeEntry`; restore re-inserts + drops the buffer row, no outbox). `ActivityDetailViewModel` gains `performUndo` + `registerSystemUndo(with:)` mirroring categories; the detail surface gets the existing `.onShake` modifier; foreground `commitExpired` is already global so no lifecycle wiring. Confirm copy names the activity; U7 supersession (including cross-surface vs category deletes) is specified, not hidden.

### 4. LOCKED mode for imported entries (over editable-with-warning)

Local LWW edits to imported intervals would fight the external source on every re-pull (`UNIQUE(user_id, source, source_ref)`, server-wins merge) — silent divergence or clobbered edits. Disabled-dimmed controls + no Save + provenance note makes the rule structural instead of advisory, while Delete stays available (local-first: the user owns their device data; relay hard-deletes on commit).

### 5. Committed-only ActivityDetail filter in the VM (over a query change)

`totalDuration` already excludes NULL durations via `COALESCE`, so totals need no store change — only a restatement + test. Filtering `endedAt == nil` rows in `ActivityDetailViewModel.load()` (one predicate, unit-tested) is smaller than touching the shared `entries(activityID:)` query and keeps History's in-progress display (owned by `HistoryViewModel`) untouched. Side benefit: the form never receives an in-progress entry (no entry point lists one), so the gate needs no nil-end branch.

### 6. Reload chain reuses existing flags (over new coordination)

Save/delete dismissals ride `needsReloadAfterSheet` (detail) → `invalidate`/`loadIfNeeded` (history), the same path Log Time saves use today; reassignment-away and delete-last-entry are list states, not navigation events (sheet stays open). No new coordinator.

## Risks / Trade-offs

- [Risk] Shake-to-undo without a toast is undiscoverable → Mitigation: confirm-alert copy hints at shake-undo; release note; toast arrives in §8 onto ready semantics.
- [Risk] Reassignment moves the entry out from under the open detail sheet (total drops, row vanishes) → Mitigation: specified as stay-open + refresh (less disorienting than auto-dismiss); scenario-pinned.
- [Risk] Deleting an imported entry may be resurrected by the next pull from its source system → Mitigation: flagged as known unknown (Open Questions); out of scope, relay hard-deletes on commit.
- [Risk] Cover + sheet + picker is still three modal layers at max depth (detail → cover → picker sheet) → Mitigation: picker is transient and self-dismissing; accepted as consistent with today's stacking (detail → editor/picker), strictly shallower in feel than sheet-on-sheet-on-sheet.
- [Risk] `updateEntry` stale-`false` UX is a new error path with no precedent in Log Time → Mitigation: localized error, draft preserved, form stays open (mirrors the existing save-failure pattern); scenario-pinned.
- [Trade-off] No read-only entry surface: every entry tap lands in an editable (or locked) form → Accepted: Cancel-discard makes review safe; entries are too small to justify two surfaces.

## Migration Plan

None — pre-release policy (no on-disk backward compat): no schema change, no migration. Rollback is revert-only.

## Open Questions

- Q1: Should a confirmed delete of an imported entry suppress re-import of the same `source_ref` on the next pull (tombstone-by-`source_ref`), or is relay hard-delete sufficient? Deferrable: answer changes sync-client behavior later, not this change's specs or tasks.
- Q2: Exact confirm-alert and locked-note copy (EN/RU) — drafted in implementation against `L10n` conventions; no spec impact beyond the localized strings already required.
