## Context

See proposal.md (Why). Current state constraining the approach:

- `LogTimeView.chrome()` (`Features/ManualEntry/Views/LogTimeView.swift:123-158`) builds one shared toolbar for both presentations: a `cancellationAction` text `Button(L10n.logTimeCancel.text) { dismiss() }` (no identifier) plus a `confirmationAction` text button (`entrySave` in EDIT with id `EntryEditSaveButton`, `logTimeAdd` otherwise with id `LogTimeAddButton`), gated by `.disabled(!vm.isAddEnabled)`, hidden in LOCKED.
- `HistoryView` pushes EDIT/LOCKED via `.navigationDestination(item:)` with `embeddedInNavigationStack: true` (real back stack: system Back + edge-back, per `fix-entry-form-gestures`), and presents CREATE via `.sheet` (no back stack). Repro on the pre-fix build (iPhone 17 sim, `com.antonkosenko.timeoflifeapp` Debug): pushed EDIT shows `<` + `Cancel` + `Save`; CREATE shows `Cancel` + `Add` (screenshots: PR body, `/tmp/fix50/before-*.png` during development).
- Issue grammar (Calendar `Edit Event` reference): pushed form = Back + `✓`; sheet = `X` + `✓`. Same actions, same gating — a pure chrome swap.
- Scope guards (parallel agents on neighboring regions of the same file): NO name/notes internals (#42), NO picker layout (#51), NO `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackContent.swift`. No `LogTimeViewModel`/store/sync/backend change.

## Goals / Non-Goals

**Goals:**

- Calendar nav-bar grammar in both modes with zero behavior change: same dismiss, same save, same validity gate, stable confirm identifiers.
- Icon buttons accessible: dedicated EN + RU VoiceOver labels (new `L10n` keys, pinned by `LocalizationTests`).
- Red→green automated evidence despite no SwiftUI view-test infra (precedent: `fix-entry-form-gestures` §3.1): the new `L10n` keys fail `LocalizationTests` before the strings land and pass after; AX-tree + screenshots verify the chrome per mode.

**Non-Goals:**

- Calendar's circular filled-button *styling*: the reference screenshots show custom sheet chrome; our form uses a standard `NavigationStack` toolbar, so "tint" means the default toolbar accent — not custom circle backgrounds.
- Any change to titles, cards, pickers, gates, save/delete, undo, sync, or copy beyond the three new a11y labels.
- UndoToast, "via `<Source>`" labels, lock-screen ControlWidget, device quota/picker (#46) — unchanged, still deferred per `docs/project-context.md`.

## Decisions

### 1. Drop the leading item when pushed; icon-swap in the sheet (over hiding Cancel everywhere)

`embeddedInNavigationStack` already distinguishes the presentations, so the chrome branches on it: pushed ⇒ no `cancellationAction` item at all (system Back owns dismissal in EDIT *and* LOCKED — retiring `Cancel` on the pushed page as the issue demands, with LOCKED consistently Back-only); sheet ⇒ `X` leading + `✓` trailing. Alternatives rejected: keeping a redundant dismiss next to Back (the reported bug); hiding Back in favor of Cancel (would kill the edge-back gesture #50 just restored).

### 2. `xmark` / `checkmark` SF Symbols in the existing placements (over custom buttons)

Keep `.cancellationAction` / `.confirmationAction` placements and the default toolbar tint — the system puts them leading/trailing with the accent tint, which *is* the Calendar placement/symbol/tint grammar for a standard nav bar. Plain `Button { action } label: { Image(systemName:) }`; `.disabled(!vm.isAddEnabled)` stays on the confirm so the disabled rendering is also system-standard. No custom circle backgrounds (see Non-Goals).

### 3. Confirm identifiers stable; dismiss gains `LogTimeDismissButton` (over renaming)

`EntryEditSaveButton` (EDIT `✓`) and `LogTimeAddButton` (CREATE `✓`) stay on the confirm buttons — no test or UI hook references them today (verified by repo grep), but stability costs nothing and keeps external hooks working. The dismiss `X` (previously identifier-less `Cancel`) gains `LogTimeDismissButton` so the new chrome is hookable per mode. Deliberate, documented here.

### 4. Three dedicated a11y-label keys (over reusing visible copy)

New keys: `entry.dismissLabel` ("Close" / "Закрыть") for the sheet `X`; `entry.confirmAddLabel` ("Add entry" / "Добавить запись") for the CREATE `✓`; `entry.confirmSaveLabel` ("Save entry" / "Сохранить запись") for the EDIT `✓`. Dedicated keys (rather than reusing `logTime.cancel`/`logTime.add`/`entry.save`) because VoiceOver on an icon button should name the *action*, and the names stay correct if visible copy ever changes. `L10n` count 140 → 143 with the test comment updated.

## Risks / Trade-offs

- [Risk] No unit test can assert SwiftUI toolbar contents (no view-test infra) → Mitigation: `L10n` red→green tests + simulator AX-tree verification per mode (`BackButton` + `EntryEditSaveButton`, no `Cancel`; `LogTimeDismissButton` + `LogTimeAddButton`) + before/after screenshots, all in the PR body.
- [Risk] `✓`/`X` glyphs under large Dynamic Type → Mitigation: single-glyph SF Symbols don't truncate (they scale as images); covered by the manual checklist (§4) on a large-text pass.
- [Risk] Parallel agents editing `LogTimeView.swift` regions (#42 name/notes, #51 pickers) → Mitigation: this diff is confined to `chrome()` lines ~120-158 plus 3 `L10n` keys; rebase conflicts, if any, stay mechanical.
- [Trade-off] LOCKED pushed loses its `Cancel` text button (Back only) — beyond the issue's letter but required by its rule ("Cancel retired" on the pushed page); Back + edge-back dismiss identically. Noted as a corner case in the PR.
- [Trade-off] `logTime.cancel` / `logTime.add` / `entry.save` strings stay for the delete-confirm alert (`Cancel`) and any other users — verified by grep before removing anything (nothing removed).

## Migration Plan

None — pre-release policy (no on-disk backward compat): no schema change, no migration. Rollback is revert-only. FURPS rows and Design docs naming the old text buttons are updated in the same iteration if they pin the grammar (tasks §5).

## Open Questions

None. Process note: `docs/bugfix-process.md` §5 asks to review the proposal with the human and wait for an explicit command before applying — the task message for this issue already orders the full pipeline (red tests → fix → re-verify → PR), which is taken as that explicit command; the deviation is noted in the PR body.
