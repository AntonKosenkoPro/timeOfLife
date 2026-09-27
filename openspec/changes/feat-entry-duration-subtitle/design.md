## Context

See proposal.md (Why) for motivation. Current state constraining the approach:

- `LogTimeView` (`Features/ManualEntry/Views/LogTimeView.swift`) sets its chrome via `.navigationTitle(formTitle)` + `.navigationBarTitleDisplayMode(.inline)`, with Cancel/Add (CREATE) or Cancel/Save (EDIT) bar actions and a validity gate (`LogTimeViewModel.isAddEnabled`: trimmed name non-empty AND End strictly after Start). No duration is shown anywhere — building an entry with a particular duration is guesswork (#36).
- `LogTimeViewModel` (`Features/ManualEntry/ViewModels/LogTimeViewModel.swift`) already publishes `startsAt`/`endsAt` (`@Published private(set)`); any view read re-renders live with no VM behavior change.
- `HistoryViewModel.naturalDuration(_:)` (`Features/AppShell/ViewModels/HistoryViewModel.swift`) is a pure, unit-tested (`NaturalDurationTests`) natural-language formatter (`33s`, `1m 20s`, `1h 12m`, `1d 12h`) already used by History rows and day totals.
- Base is the gestures change (`fix-entry-form-gestures`): five cards in fixed order (Name → Start → End → Categories → Notes), shared `chrome` modifier for the sheet and pushed presentations, no gesture-blocking modifiers. This change owns only the toolbar principal region.
- Scope guards: NO card-order or cover/push presentation changes (open PR #54 owns them), NO name-field internals (`feat-name-field-affordances` owns `nameCard`), NO touches to `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackView.swift`.

## Goals / Non-Goals

**Goals:**

- A live `Duration: 1h 30m` subtitle in the form nav bar (Variant 3 refined, as agreed): `ToolbarItem(.principal)` VStack with the mode title plus a footnote duration line, in all three modes.
- Live updates from the already-published `startsAt`/`endsAt` with zero VM behavior change (a pure display helper only).
- Invalid state (End ≤ Start, confirm disabled) shows explanatory text in `Theme.danger` instead of a duration.

**Non-Goals:**

- Changing the Start/End auto-push behavior (`LogTimeViewModel` save/validation untouched).
- Name-field clear/autocomplete (successor `feat-name-field-affordances`, stacked on the same branch).
- Gesture work (see `fix-entry-form-gestures`, PR #54).
- UndoToast, "via <Source>" labels beyond today's rows, lock-screen ControlWidget, device quota/picker (#46) — unchanged, still deferred per `docs/project-context.md`.
- Any store, sync, outbox, or backend change (OpenAPI untouched).

## Decisions

### 1. `ToolbarItem(.principal)` VStack (over an inline duration section or a large-title subtitle)

The decision (Variant 3 refined) pins the subtitle to the nav bar so the duration is visible without scrolling, in both the CREATE sheet and the pushed EDIT/LOCKED form. A principal item replaces the inline title, so the VStack repeats the mode title (`formTitle`, same localized strings) above the footnote line — one chrome change inside the shared `chrome` modifier, so CREATE and EDIT can never visually diverge. An inline section inside the scrollable cards was rejected: it scrolls away exactly when the pickers are open, which is when the duration matters. No new presentation logic; the gestures change's `embeddedInNavigationStack` split is untouched.

### 2. Reuse `HistoryViewModel.naturalDuration` (over a new formatter)

The History rows already render durations with this pure function, and `NaturalDurationTests` pins its grammar. Reusing it keeps one duration language across History and the form (a form-built `1h 30m` reads identically after saving). The VM exposes only a pure display helper (`durationSubtitleSeconds: Int?` — the rounded Start→End seconds, nil when ≤ 0); the view formats with `naturalDuration` + the localized `Duration: %@` label. No new formatting code, no new formatter tests — the helper gets validity/edge tests in `LogTimeViewModelTests`.

### 3. Invalid state shows explanatory text in `Theme.danger` (over silence)

The validity gate disables the confirm with no error text by spec, so an invalid interval today gives no hint *why*. The subtitle fills exactly that gap: End ≤ Start shows the localized invalid-interval text (`End must be after Start`) in `Theme.danger` where the duration would be. It is display-only — the gate logic, the auto-push behavior, and the no-error-text rule for the form body are unchanged.

### 4. Footnote single line with inline-mode truncation (over wrapping)

The principal item has narrow horizontal room (Cancel + Save/Add flank it). Both lines are `.lineLimit(1)` with tail truncation so long localized titles or durations (e.g. `1d 12h`) can never push the bar actions or wrap the nav bar taller. Title uses `.headline`, subtitle `.footnote`; valid subtitle in `Theme.textSecondary`, invalid in `Theme.danger`.

## Risks / Trade-offs

- [Risk] Principal item narrows the title space on 320 pt screens → Mitigation: single-line truncation on both lines; manual checklist covers 320 pt + Dynamic Type + EN/RU.
- [Risk] The pushed EDIT form's principal item coexists with the back button → Mitigation: system handles principal-item layout beside the back chevron; covered by the manual checklist (EDIT on device).
- [Risk] `durationSubtitleSeconds` rounding vs History's `durationSeconds` (Int-truncated at save) → Mitigation: subtitle uses the same `naturalDuration` grammar; a ±1s rounding seam at save is display-only and invisible at minute granularity.
- [Trade-off] No programmatic UI test for the nav-bar rendering → Accepted: automated tests cover the VM helper (valid/invalid/edge) + `LocalizationTests` key parity; the rendering itself is on the manual checklist.

## Migration Plan

None — pre-release policy (no on-disk backward compat): no schema change, no migration. Rollback is revert-only. FURPS `Timetracking.md` F13 comment gains the subtitle sentence in the same iteration.

## Open Questions

None. New `L10n` strings (`entry.duration`, `entry.invalidInterval`) ship in EN + RU; `LocalizationTests` count grows accordingly. No ctx7 fetch: stable SwiftUI `ToolbarItem(.principal)` API plus repo-internal wiring only — no external version-specific behavior involved.
