## Context

See `proposal.md` for motivation and `specs/timer-capture-experience/spec.md` for the behavior contract.

Track currently presents `ActivityChooserView` as a sheet. The chooser owns four overlapping branches: a recency list, filtered results, unmatched-name creation, and an empty-catalog screen that opens a separate naming alert. `TrackViewModel` stores the chooser query beside the committed `TrackState`, but the query is not modeled as a distinct interaction state. The chooser's Manage Activities row is not wired to a destination.

The app supports iOS 15+, uses SwiftUI navigation, and must let the operating system determine native search placement and animation across OS versions. SwiftUI exposes active-search state and dismissal through the search environment, while search-suggestion placement can vary by platform and context. Therefore the system search field can be native without delegating the entire results surface to the suggestion API.

Simulator verification of the first implementation exposed three problems that drive this revision:

1. **Redundant affordances.** The navigation-bar search field (`.searchable`) and the `TimerActivityPicker` button both open the same search; on the newest runtime both are visible side by side.
2. **Hidden entry on iOS 18 and lower.** The navigation-bar search field is hidden by default on those runtimes, so the picker button is the only entry — but it does not look like search, so first-time users do not discover it.
3. **Commit does not leave search.** Tapping a result marks it with the prepared-Activity checkmark but the OS-owned search field stays active, so the body keeps showing search content instead of returning to the ready timer. Dismissing the OS-owned field on commit is version-fragile.

The full Activity Editor is specified in `Design/SCREENS/ActivityEditor.md` but is not implemented. Configured creation in this change must establish its create-from-Track mode. Activity persistence is local-first through `LocalStore`; the relay already enforces a case-insensitive unique Activity name per user, but the local schema currently has no equivalent unique index and `ensureActivity(named:)` performs lookup and insertion as separate operations.

## Goals / Non-Goals

**Goals:**

- Make native search the single interaction boundary for full-catalog browse, filtering, first creation, quick creation, and configured creation.
- Keep recent shortcuts and committed ready state outside the temporary search draft.
- Let iOS own search placement, focus, keyboard, activation, and Cancel behavior.
- Make local create-or-reuse atomic and consistent with the relay's case-insensitive identity rule.
- Preserve user input and the prior committed timer state across cancellation and recoverable failures.
- Provide deterministic handling for configured-creation collisions and pending-deletion identities.

**Non-Goals:**

- Removing the ready state or starting timing as a side effect of selection or creation.
- Allowing duplicate normalized Activity names.
- Adding fuzzy, diacritic-insensitive, or internal-whitespace normalization beyond the existing contract.
- Editing existing Activities directly from search results; Manage Activities remains the editing surface.
- Persisting an unstarted ready selection or active search draft across process termination.
- Changing backend endpoints, payloads, timer persistence, entry persistence, or sync policy.

## Decisions

### 1. Present Activity search from one state-specific preparation control

Track will not attach `.searchable` to the navigation-owned content or render a permanent search field above the timer. Instead, it renders exactly one preparation control below the numeric timer and above Recents: `+ Choose an activity` while idle, and an Activity picker showing the prepared name while ready. Each opens the full-height searchable sheet containing unified search content: full-catalog browse, filtered matches, the prepared-Activity checkmark, the split quick-create/configure row, restore, empty-catalog guidance, and validation/error states.

The sheet's search field is always visible and becomes first responder on every supported iOS version. Idle activation uses an empty query. Ready activation initializes the draft with the prepared Activity name and focuses it, so the user can replace the name without an additional tap. The operating system still owns keyboard and Cancel affordances inside the sheet. Selecting an existing result, completing quick creation, restoring a pending deletion, or saving configured creation is a commit boundary: the view model prepares the Activity and the sheet dismisses (`dismiss()`), which is reliable on all supported versions — the "mark but not select" failure mode cannot occur because the sheet is dismissed by the app, not by the OS-owned search environment.

The result list is ordinary screen content rather than content supplied solely through the search-suggestions closure. This preserves control over sections, errors, empty states, split create/configure actions, and full-height layout while the operating system still owns the search field itself.

Alternative considered: retain a permanent search-styled affordance on Track. It was rejected because idle Track would expose it alongside `+ Choose an activity`, giving two controls the same purpose and placing the first action above the timer rather than in the capture flow.

Alternative considered: animate a custom `TextField` between Track and a results screen. This could mimic a particular iOS release but would require custom focus, keyboard, Cancel, placement, accessibility, and transition behavior. It is rejected because platform-native variation is a requirement.

### 2. Keep committed preparation separate from the search draft

`TrackState` remains the source of committed timer preparation. Search activation creates a temporary interaction state containing the query, errors, and optional editor/collision presentation; it does not copy query text into `TrackState`.

Idle search begins with an empty query. Ready search begins with the prepared Activity name in the focused draft field while preserving that Activity as the committed fallback. Query edits do not clear or replace the selection. Dismissing the sheet without confirmation (native Cancel or swipe-down) restores the prior timer content unchanged.

Selecting an existing result, completing quick creation, restoring a pending deletion, or saving configured creation is a commit boundary. Only then does the view model call the existing selection transition, clear search state, and dismiss the sheet.

Alternative considered: clear the prepared Activity when the user begins typing. This makes Cancel destructive and creates a period where the visible draft can diverge from the Activity identifier used by Start. Keeping the prior commit until replacement avoids both problems.

### 3. Derive one deterministic result model from query and catalog

The search content uses these rules:

1. Empty query: show the complete catalog in existing recency order.
2. Non-empty query: show case-insensitive containment matches in recency order.
3. Exact normalized match: identify it first and suppress all creation actions.
4. Valid unmatched query: show quick-create and configure-create actions after existing partial matches.
5. Invalid query: keep existing search results available, suppress creation, and show localized validation guidance.

Normalization for identity remains surrounding-whitespace trim plus case-insensitive comparison. Search containment may remain user-friendly and localized, but creation confirmation must ask the store to resolve identity authoritatively.

The empty catalog is a presentation state of the same result model, not a separate alert. With no query it explains what to type; after valid input it exposes the ordinary creation actions.

### 4. Use one create row with two explicit targets

For a valid unmatched query, the main row action quick-creates the categoryless Activity. A separate trailing configuration target opens create-from-Track Activity Editor mode with the trimmed name prefilled. Both targets meet the minimum tap area and expose distinct localized accessibility labels and stable identifiers.

The configuration target appears only for an unmatched creation candidate. It does not become an edit button for exact existing results, so its meaning remains stable.

Alternative considered: make every creation open the full editor. This removes the quick path and adds a Save step to the most frequent first-use case.

Alternative considered: show two full creation rows. This is easier to implement but visually overstates what is one candidate with an optional configuration branch.

### 5. Implement the shared Activity Editor's create-from-Track contract

Configured creation requires the specified shared editor in create mode with name, optional notes, and optional Categories. It saves through `LocalStore` and returns the created Activity to the Track search coordinator.

Cancel returns to active search without clearing its query. Save success commits the Activity selection and closes both editor and search. Save failure leaves the editor draft intact. Existing-Activity edit mode and Manage Activities navigation may share the same editor architecture later, but wiring those management flows is outside this change.

If configured save collides with an existing normalized name, the editor presents two explicit outcomes: use the existing Activity without applying the draft metadata, or keep editing and choose a distinct name. The collision never silently updates the existing record.

### 6. Enforce create-or-reuse atomically in LocalStore

The local `activities` table will enforce a unique index on `lower(name)`, mirroring the relay's per-user index for the single local catalog. Activity creation from Track will become one transactional LocalStore operation that:

1. Trims and validates the candidate name.
2. Resolves an existing row using the database's case-insensitive comparison.
3. Restores a matching non-expired pending-deletion Activity when the user confirms the explicit restore action.
4. Inserts the Activity and its outbox row only when no active or restorable identity exists.
5. Returns a typed outcome: created, existing, restorable deletion, or validation/persistence failure.

This removes the lookup-then-insert race in `TimerService.ensureActivity(named:)`. The unique-index error remains a final race guard and is translated into an existing/collision outcome rather than a generic error.

Because the app is unreleased, the local schema definition can be updated in place under the repository's pre-release policy. Development installations and fixtures may start with a fresh database; no legacy migration branch is added.

Alternative considered: rely only on the backend collision response. This violates local-first identity while offline and allows duplicate names to exist until optional sync occurs.

### 7. Treat pending deletion as a restorable identity

The undo snapshot already contains the complete deleted Activity. Search creation resolution will inspect non-expired snapshots for a normalized name match. The result model exposes a restore action instead of Create. Confirming it restores the buffered snapshot transactionally, prepares the restored Activity, and creates no outbox operation.

This preserves history and the original identifier. Automatically restoring on typing is rejected because it would reverse a deletion without explicit user confirmation.

### 8. Revalidate the prepared Activity before Start

Start will resolve the committed Activity identifier in LocalStore before entering running state. If it no longer exists, Track clears preparation and returns to idle with a localized error. It will not call an ensure-by-id path that recreates a deleted Activity.

This check protects deletion or sync changes that occur after preparation. It is local and does not add network latency.

### 9. Test semantics rather than search coordinates

Unit tests will cover result derivation, committed-versus-draft state, normalization, atomic outcomes, collision choices, failure recovery, pending deletion restoration, and stale preparation. UI tests will verify affordance activation, sheet dismissal, result selection, quick creation, configured creation, empty catalog, ready state, and explicit Start.

The sheet presentation is version-consistent, so tests may assert sheet-level behavior (presentation, dismissal, field focus) without depending on OS placement. Manual simulator checks will cover the minimum supported iOS runtime and the newest available runtime, light/dark appearance, English/Russian, keyboard behavior, Dynamic Type, VoiceOver, and Reduce Motion.

## Risks / Trade-offs

- [The sheet adds a presentation layer over Track] -> One state-specific control is placed in the capture flow below the timer, so the extra layer is one tap, has no duplicate idle control, and opens with its search field focused.
- [Active-search environment is read at the wrong hierarchy level] -> Keep the search modifier on the sheet's navigation-owned content and observe search state in a descendant content view.
- [The shared Activity Editor expands this focused change] -> Implement only the create-from-Track mode and reusable seams needed by its existing design contract; defer management wiring.
- [Split create/configure row is hard to discover or operate] -> Use two distinct 44-point targets, explicit labels, VoiceOver actions, and UI tests.
- [Local and relay case folding differ for uncommon Unicode] -> Keep the existing documented case-insensitive contract, use database comparison as local authority, and let existing sync collision reconciliation handle relay disagreements; do not add unplanned fuzzy normalization.
- [Adding a local unique index exposes existing development duplicates] -> Follow the pre-release reset policy and add fixture coverage; do not add legacy deduplication code.
- [Catalog refresh changes results while typing] -> Recompute from stable Activity identifiers and recency order without mutating the committed selection.
- [A prepared Activity disappears before Start] -> Revalidate by identifier and fail back to idle rather than resurrecting deleted data.

## Migration Plan

1. Update the local v1 schema and tests for normalized uniqueness and atomic create-or-reuse outcomes.
2. Introduce search interaction state and result derivation without changing the timer state machine.
3. Present Activity search as a searchable sheet opened by the state-specific preparation control below the timer; retain recent shortcuts.
4. Add the create-from-Track Activity Editor path and collision handling.
5. Remove the inline search shell, the navigation-bar search field, the special empty-catalog alert, and obsolete chooser-only state after every preparation path uses the sheet.
6. Update localization, design documentation, requirements/use cases, accessibility coverage, and previews.
7. Run the complete iOS lint/build/test suite and simulator matrix required by the repository.

Rollback restores the prior chooser UI and service call sites. The local uniqueness index is compatible with the prior create path and does not require rollback; development databases can be reset under the pre-release policy.
