## Why

Activity creation currently branches inside search into quick creation and configured creation, making the preparation flow more complex than necessary and limiting refinement to new Activities. Creation should stay fast and uniform, while refinement should be available from Track for any selected Activity, whether newly created or existing.

## What Changes

- Remove configured creation and its Refine/configuration target from the unmatched-name row in Activity search; creating from search always uses the quick, name-only path.
- Add a Refine button beside the selected Activity control on Track. It appears only while an Activity is selected.
- Open the shared Activity Editor in edit mode for the selected Activity, prefilled with its current name, notes, and Categories.
- Keep the selected Activity and timer state unchanged when refinement is cancelled or fails; apply saved changes to the same Activity identity.
- Update first-use and collision behavior so search no longer offers a pre-creation refinement branch.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `timer-capture-experience`: Simplify Activity creation to quick creation only and add post-selection refinement from Track for newly created and existing Activities.

## Impact

- Affects Track layout and accessibility, Activity search result actions and state, `TrackViewModel` editor presentation, and the shared Activity Editor's existing-Activity edit mode.
- Requires updates to Track and Activity Editor design documentation, localized English and Russian strings, unit tests, UI tests, and simulator verification.
- Does not change backend endpoints, local storage schema, Activity identity, timer persistence, entry persistence, or sync policy.
