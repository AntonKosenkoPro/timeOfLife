## 1. Local Activity Identity

- [x] 1.1 Add shared Activity-name validation and normalization for surrounding-whitespace trim, non-empty input, and the 60-character limit, with focused unit tests.
- [x] 1.2 Add the case-insensitive unique Activity-name index to the local v1 schema and update LocalStore fixtures for the pre-release reset policy.
- [x] 1.3 Implement a transactional LocalStore create-or-resolve operation that returns typed created, existing, restorable-deletion, validation, and persistence outcomes while writing state plus outbox atomically.
- [x] 1.4 Add LocalStore support for finding a non-expired pending-deletion Activity by normalized name and explicitly restoring that snapshot without creating an outbox row.
- [x] 1.5 Replace Track's lookup-then-insert creation path with the atomic LocalStore operation and translate uniqueness races into deterministic existing/collision outcomes.
- [x] 1.6 Add LocalStore and TimerService tests for case/whitespace reuse, unique-index enforcement, concurrent collision resolution, pending-deletion restoration, outbox behavior, and offline operation.

## 2. Search Interaction State

- [x] Introduce a temporary Activity-search state that keeps query, validation, errors, editor presentation, and collision presentation separate from committed `TrackState`.
- [x] Implement the deterministic result model for empty-query browse, recency-ordered partial matches, exact-match priority, invalid input, quick creation, configured creation, and restorable deletion.
- [x] Implement search activation, sheet dismissal, result confirmation, query reset, and prior ready/idle restoration without changing timer state for unresolved input.
- [x] Revalidate the committed Activity identifier before Start and return to idle with a localized error instead of recreating a deleted Activity.
- [x] Add Track view-model tests covering draft-versus-commit behavior, search cancellation, prepared-result marking, all result-model branches, creation failures, and stale prepared Activities.

## 3. Searchable Sheet And Track UI

- [x] Build the searchable sheet presentation opened by a search-styled affordance on Track (the single entry point, showing the prepared Activity name when ready), leaving the existing timer state machine and recent shortcuts intact.
- [x] Run the searchable sheet on the minimum supported iOS runtime and newest available runtime to verify presentation, field visibility, focus, keyboard, Cancel, and content-area behavior before completing visual wiring.
- [x] Render the complete catalog for an empty query, filtered Activity-only rows for non-empty queries, the prepared-Activity checkmark, empty-catalog guidance, and localized validation/error states inside the sheet.
- [x] Add the unmatched-name create row with distinct minimum-size quick-create and configure targets, stable accessibility identifiers, localized VoiceOver labels, and no Category metadata in results.
- [x] Wire existing selection, quick creation, pending-deletion restoration, success dismissal, and failure preservation to the search coordinator while keeping Start explicit; confirming a result or creation dismisses the sheet and returns to the ready timer.
- [x] Disable the Activity search affordance while running without destabilizing the activity label, numeric readout, or Start/Stop control geometry.
- [x] Remove the inline search shell, the navigation-bar search field, the first-Activity alert, obsolete `isChoosingActivity`/chooser-only state, and unwired Manage Activities row after every preparation path uses the sheet.

## 4. Configured Creation

- [x] Implement the shared Activity Editor create-from-Track draft and view model with name, optional notes, optional Categories, field validation, and local-first save outcomes.
- [x] Implement the native editor sheet UI from `Design/SCREENS/ActivityEditor.md`, including focused name input, notes counter, optional category selector, pinned Save, Cancel, loading, errors, and accessibility identifiers.
- [x] Open configured creation from the search candidate with the trimmed query prefilled; preserve active search and query on Cancel, and prepare the saved Activity without starting timing on success.
- [x] Handle configured-save name collisions with explicit Use Existing and Keep Editing choices, never applying draft notes or Categories to the existing Activity implicitly.
- [x] 4.5 Add editor and integration tests for validation, optional metadata, offline save, Cancel restoration, successful preparation, retryable failure, and collision choices.

## 5. Localization And Product Documentation

- [x] 5.1 Add all native-search, empty-state, create/configure, restore, collision, validation, and stale-preparation strings to English and Russian localization and update `L10n` coverage.
- [x] 5.2 Update `Design/SCREENS/TimeTracking.md`, `Design/COMPONENTS.md`, `Design/SCREENS/ActivityEditor.md`, and `Design/INTERACTIONS.md` to describe the searchable-sheet presentation and remove the obsolete inline-search/chooser/alert behavior.
- [x] 5.3 Update Activity Catalog FURPS and use-case narratives to align first creation, quick creation, configured creation, normalized reuse, and explicit ready-state semantics.
- [x] 5.4 Review `README.md` and `AGENTS.md` against the completed implementation and update only architecture, workflow, or repository guidance that actually changed; confirm the OpenAPI contract remains unchanged.

## 6. Verification

- [x] 6.1 Add or update SwiftUI previews for idle, ready, active empty search, filtered results, unmatched creation, empty catalog, validation, collision, and editor states in light/dark and English/Russian.
- [x] 6.2 Add a reusable simulator flow covering affordance activation, sheet dismissal, existing selection, quick creation, configured creation, ready state, explicit Start, and Stop.
- [x] 6.3 Manually verify VoiceOver, Dynamic Type, Reduce Motion, keyboard behavior, split-target hit areas, light/dark appearance, English/Russian, offline creation, and oldest/newest supported iOS behavior.
- [x] 6.4 Run `xcodegen generate` and `swiftlint lint --strict`, fixing every finding.
- [x] 6.5 Run the warning-as-error iOS build and inspect/fix every build warning.
- [x] 6.6 Run the complete iOS test suite, including LocalStore, TimerService, Track, editor, localization, and integration coverage, and leave all tests green.
- [x] 6.7 Re-read the modified OpenSpec delta, FURPS rows, use cases, and design contracts; reconcile any behavioral discrepancy before marking the change complete.

## 7. State-Specific Preparation Layout Follow-up

- [x] 7.1 Replace the permanent top-of-Track search affordance with the state-specific control below the numeric timer: `+ Choose an activity` while idle and the prepared-Activity picker while ready; keep Recents below it.
- [x] 7.2 Make idle activation present an empty, focused native search field and ready activation pre-fill and focus the selected Activity name without mutating committed preparation.
- [x] 7.3 Update Track and search-coordinator tests for state-specific visibility, focus/prefill behavior, cancellation restoration, and the absence of duplicate preparation controls.
- [x] 7.4 Update previews, reusable simulator flow, English/Russian visual checks, and the minimum/newest runtime verification for the revised layout and keyboard-on-presentation behavior.
