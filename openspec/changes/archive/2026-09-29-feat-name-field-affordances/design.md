## Context

See proposal.md (Why) for motivation. Current state constraining the approach:

- Track (`Features/TimeTracking/Views/TrackContent.swift` `nameField` + `Features/TimeTracking/ViewModels/TrackViewModel.swift`): a bare `TextField` bound to `vm.nameDraft` (idle/ready/saved; a locked label while running), with exact-text Recents chips (cap 6, newest-first, case-sensitive identity) below the Start button. `syncReadyFromDraft()` derives `.ready`/`.idle` from the draft (inheriting the exact recents match's categories); `select(_:)` fills text + full ordered categories without starting. No clear button, no suggestions.
- Entry form (`Features/ManualEntry/Views/LogTimeView.swift` `nameCard` + `LogTimeViewModel`): a bare `TextField` bound to `vm.name`; no recents source at all (the VM loads only the category catalog). The validity gate (`isAddEnabled`) must not change.
- Recents source: `LocalStore.recents(limit:)` returns the shared `RecentEntry` (`CatalogModels.swift`: `activityText` + ordered `categoryIDs` + `startedAt`, one per distinct exact text, newest-first, capped). `TrackViewModel` maps it to its nested `RecentEntry` (`text` + `categoryIDs` + `firstCategoryID`).
- Base is the gestures change (`fix-entry-form-gestures`): `nameCard` internals and the toolbar were explicitly left untouched for these successors; card order and cover/push presentation belong to open PR #54 and are out of scope.
- Scope guards: NO card order or cover/push presentation changes, NO touches to `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackView.swift` beyond reading.

## Goals / Non-Goals

**Goals:**

- Trailing clear (`×`) button on the name fields that need it: Track `TimerNameField`, entry-form `EntryNameRow` (#42). One custom SwiftUI button component shared by both.
- Autocomplete suggestions from recent/committed entry texts on both fields, with Recents-tap-contract inheritance (#43). Suggestions never mutate history.
- Layout stability on Track: suggestions must not move the Start/Stop action (D10 stationary main action).

**Non-Goals:**

- Duration subtitle (sibling `feat-entry-duration-subtitle`, stacked on the same branch — the two changes touch different regions of `LogTimeView.swift`: toolbar principal vs `nameCard`).
- Icon work (`feat-category-icons-lifedomains`).
- New history queries or store changes: both suggestion sources read the existing `recents(limit: 6)` path.
- UndoToast, "via <Source>" labels beyond today's rows, lock-screen ControlWidget, device quota/picker (#46) — unchanged, still deferred per `docs/project-context.md`.

## Decisions

### 1. One shared `ClearTextButton` component (over per-view inline buttons)

Both fields need the same affordance: `xmark.circle.fill`, `Theme.textSecondary`, 44 pt minimum tap target, localized `Clear name` accessibility label, caller-supplied accessibility identifier (`TimerNameClearButton` / `EntryNameClearButton`). A tiny shared view in `Core/Design/Components` (next to `ErrorBanner`) keeps the two presentations identical and gives one place for the hit-target/padding rules. Visibility rule lives with the caller: shown only when the field is non-empty AND editable (Track: idle/ready/saved states; entry form: `!vm.isLocked`).

### 2. Suggestions filter: case-insensitive prefix over loaded recents, exact match excluded (over contains-match or a new query)

Rule (pinned in both delta specs): trimmed input non-empty → loaded recents (cap 6, newest-first) filtered to `candidate.lowercased().hasPrefix(input.lowercased())`, excluding only the case-sensitive exact match (`candidate != input`). Rationale:

- Prefix (not contains) keeps the list short and predictable on a 6-item source; contains-match on short names (`un` matching `Running`) suggests confusingly.
- Case-insensitive matching is forgiving while typing, but the exclusion and the fill stay case-sensitive so `Gym` ≠ `GYM` identity is preserved end to end (typing exact `Gym` excludes only `Gym`; `GYM` still suggests).
- No new store query: Track reuses `vm.recents`; the entry form loads the same `recents(limit: 6)` once per open (`loadNameRecentsIfNeeded`, beside the catalog load). A larger limit would widen the source beyond the Recents contract the specs quote — rejected.

Both VMs expose a pure `nameSuggestions()` over already-loaded data, so the filter is unit-testable without a store.

### 3. Pick = Recents tap contract (over text-only fill)

Picking a suggestion calls the same path as tapping a Recents chip — Track reuses `select(_:)` directly; the entry form gains `applySuggestion(text:categoryIDs:)` setting name + ordered categories. The draft text and categories update together, nothing is saved, and no committed entry is touched (suggestions never mutate history). On Track the ready timer appears without starting, exactly like a chip tap.

### 4. Track suggestions render as an overlay (over inline layout)

Track's main action must not move (D10 stationary action; the ready→running swap is pixel-stable by design). An inline list between the name field and Start would push the action down with every keystroke. The suggestion card therefore renders in an `.overlay` anchored below the field (`zIndex` above the action), affecting no layout geometry — appearing/disappearing changes zero frames. The entry form has no stationary-action constraint (scrollable cards), so its suggestions render inline inside `nameCard`, absorbed by the scroll view.

### 5. Clear semantics per surface (over a shared clear behavior)

- Track `clearNameDraft()`: empties `nameDraft` and re-syncs (`syncReadyFromDraft` → `.idle`, cancels a deferred start). Clearing is a draft reset, matching "Empty text → idle".
- Entry form `clearName()`: empties `name` only — categories, notes, and Start/End stay untouched; the validity gate re-evaluates (Add disables on empty name). Clearing must not destroy the rest of the draft.

### 6. No suggestion-dismiss state (over explicit open/close tracking)

The list is a pure function of draft + recents: it shows while matches exist and closes itself when the input clears, matches exactly, or a pick fills an exact text. No `@State` open flag, no tap-away handling, no keyboard interplay — one less state machine to desync, and the behavior is fully covered by VM unit tests.

## Risks / Trade-offs

- [Risk] Overlay suggestions on Track can cover the Start button while open → Mitigation: accepted and intended (standard autocomplete behavior); one tap on a suggestion or the clear button resolves it; Start stays tappable beside/below the card; manual checklist covers small screens.
- [Risk] Entry-form recents load adds one store read per open → Mitigation: same cheap indexed query as Track's (`index_entries_on_user_activity_text_started_at`), once per open, failure → empty suggestions (never blocks the form).
- [Risk] Two `nameSuggestions()` implementations (nested vs shared `RecentEntry` field names) duplicate ~5 lines → Mitigation: accepted; unifying would couple `ManualEntry` to `TimeTracking`'s nested type or force a shared protocol for one predicate. Each stays pure and tested.
- [Risk] Autocomplete UX is device-sensitive (keyboard, Dynamic Type, overlay anchoring) → Mitigation: flagged as a manual-checklist item in the PR body per the task brief.
- [Trade-off] Suggestion rows show text only (no category icons) → Accepted: keeps rows one-line and avoids resolving the category map in the entry form; icons already exist on the Track Recents chips one glance away.

## Migration Plan

None — pre-release policy (no on-disk backward compat): no schema change, no migration. Rollback is revert-only. FURPS `Timetracking.md` F13 comment gains the affordances sentence in the same iteration.

## Open Questions

None. New `L10n` strings (`name.clear`, `name.suggestions`) ship in EN + RU; `LocalizationTests` count grows accordingly. No ctx7 fetch: stable SwiftUI (`TextField`, `Button`, `overlay`) plus repo-internal store/VM wiring only — no external version-specific behavior involved.
