## Why

Preparing an Activity on Track currently branches across recent pills, a searchable chooser, a separate empty-catalog alert, quick creation, and an unwired management path. The duplicated interactions make the path from arriving on Track to reaching the ready timer harder to understand and maintain, especially for first-time creation.

## What Changes

- Preserve recent Activities as the one-tap shortcut that prepares an Activity without starting the timer.
- Replace the remaining Activity chooser branches with one platform-native searchable sheet. Track exposes exactly one state-specific entry point: the idle `+ Choose an activity` primary button or the ready Activity picker, never two controls that open the same sheet.
- Arrange idle Track as numeric timer, `+ Choose an activity`, then Recents. Arrange ready Track as numeric timer, Activity picker, then Recents.
- Focus the sheet's native search field when it opens. Idle activation starts with an empty query; ready activation pre-fills and focuses the selected Activity name so it can be changed directly.
- Remove the redundant navigation-bar and top-of-Track search fields.
- Use the search content area to show the complete recency-ordered catalog for an empty query, filtered existing Activities for a non-empty query, and an explicit create action when no normalized exact match exists.
- Provide an optional configure action for an unmatched name that opens the shared Activity Editor with the name prefilled; saving prepares the created Activity, while cancelling returns to the active search and preserves the query.
- Preserve the explicit ready state: selecting or creating an Activity never starts timing, and Start remains the only transition to running. Confirming a result or creation dismisses the search presentation and returns to the ready timer.
- Keep Activity names unique after trimming and case-insensitive comparison. Exact matches reuse the existing Activity and suppress creation.
- Unify first-Activity creation with the ordinary search-and-create flow instead of presenting a special alert.
- Define safe behavior for unresolved search text, cancellation, validation, creation races, duplicate-name collisions, stale prepared Activities, and local persistence failures.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `timer-capture-experience`: Replace the multi-branch Activity chooser with a searchable-sheet search presentation opened by one state-specific preparation control, and specify focus, selected-name prefill, unified existing selection, quick creation, configured creation, cancellation, matching, and ready-state behavior.

## Impact

- Affects the Track screen, the Activity search presentation (a searchable sheet opened by a search-styled affordance), Track view model state, quick-create behavior, Activity Editor presentation, local Activity lookup/creation, and related unit and UI tests.
- Requires updates to `Design/SCREENS/TimeTracking.md`, `Design/COMPONENTS.md`, relevant interaction documentation, and Activity Catalog use cases/FURPS wording where the current special empty-state and quick-add flows differ.
- Does not change timer persistence, entry persistence, sync endpoints, the backend OpenAPI shape, or the explicit Start/Stop state machine contract.
- Introduces no new runtime dependency; the interaction uses native SwiftUI search and navigation behavior available for the supported iOS versions.
