## Context

See `proposal.md` for motivation and `specs/timer-capture-experience/spec.md` for the behavior contract.

The current search sheet owns configured creation: its unmatched-name row has quick-create and trailing configuration targets, `ActivitySearchState` carries editor and collision presentations, and `ActivitySearchSheet` presents `ActivityEditorView`. The editor only implements create-or-resolve behavior, initializes notes and Categories empty, and reports save success back to the search coordinator.

Track already renders a state-specific Activity control for every timer state. Ready and saved use an interactive search picker; running, saving, and recoverable error use a non-interactive label. The selected `Activity` is also embedded in each non-idle `TrackState`, so a successful edit must refresh that associated value without changing the state case, running start time, elapsed value, saved duration, or ticker.

`LocalStore` is the only mutation chokepoint. It already has a generic LWW `updateActivity`, but refinement additionally needs deterministic normalized-name collision handling, draft preservation, Category replacement, and one transactional state-plus-outbox write. No schema or backend contract change is required.

## Goals / Non-Goals

**Goals:**

- Keep Activity search responsible only for browse, selection, restoration, and quick creation.
- Place a minimum-size Refine action immediately beside the selected Activity in every non-idle Track state.
- Reuse one editor surface for persisted Activity values and local-first updates.
- Preserve the selected Activity identity and exact timer state across save, cancel, collision, and failure.
- Make update collision handling atomic and testable at the LocalStore boundary.

**Non-Goals:**

- Adding Activity refinement to search results, Recents, History, or Manage Activities.
- Changing Activity deletion, undo, timer, entry, sync, or backend behavior.
- Introducing Category metadata into Activity search or Track's selected-Activity row.
- Persisting an unsaved refinement draft across app termination.

## Decisions

### 1. Render one selected-Activity row with separate Search and Refine targets

`TrackView` will replace the full-width selected picker/label with an `HStack`: the existing Activity picker or non-interactive label takes flexible width, and a trailing Refine button uses a visible text label, a minimum 44-point interaction area, and stable `TimerActivityRefineButton` identifier. Idle continues to render only `TimerChooseActivityButton`.

Refine is visible whenever `TrackState.activity` is non-nil, including running and recoverable error states. It remains interactive while a timer runs because editing Activity metadata does not alter the timer row's `activity_id`; the ticker and start time continue behind the sheet. It is disabled only during the transient saving state to avoid overlapping a stop transaction with an Activity update.

The search picker remains disabled outside ready/saved states, preserving the rule that the Activity associated with a running timer cannot be replaced. This gives the adjacent controls distinct meanings: tapping the name chooses/replaces; tapping Refine edits the same identity.

Alternative considered: make the entire row open the editor and move Activity replacement elsewhere. Rejected because it changes the established selected-Activity search entry point and makes the two intentions less explicit.

Alternative considered: hide Refine while running. Rejected because the requirement ties availability to having a selected Activity and refinement is identity-preserving and safe during timing.

### 2. Own refinement presentation at Track level, outside search state

`TrackViewModel` will hold an optional refinement presentation containing the selected Activity snapshot. `TrackView` presents `ActivityEditorView` from that state using a sibling sheet to Activity search. Search state will lose its editor and configured-creation collision fields and methods; `ActivitySearchSheet` will no longer know about the editor.

This keeps temporary search query state independent from edit state and prevents refinement dismissal from invoking `cancelSearch()`. Activating Refine first resolves the selected identifier from `LocalStore`; if it no longer exists, Track follows the existing stale-preparation behavior instead of opening an editor with obsolete data.

Alternative considered: reuse `ActivitySearchState.editor` and activate search invisibly before presenting refinement. Rejected because it couples a post-selection edit to an unrelated search lifecycle and risks native Cancel or sheet dismissal clearing the wrong state.

### 3. Change the editor from create-from-search input to existing-Activity edit input

`ActivityEditorView` and `ActivityEditorViewModel` will accept the selected `Activity`, initialize name, notes, and selected Category identifiers from it, and show the edit title. The editor retains the current validation, loading, keyboard, localization, and pinned Save behavior. Save will submit an `ActivityDraft` against the original identifier rather than call create-or-resolve.

Because configured creation is removed and no other implemented route opens create mode, the create-from-search initializer, callbacks, and collision-choice UI will be removed rather than retained as unused compatibility code. A future Manage Activities creation flow can introduce its own explicit create mode when implemented.

Alternative considered: add a create/edit mode enum and retain configured creation code behind an unused branch. Rejected because the app is unreleased, no current surface requires editor creation after this change, and repository policy favors removing dead pre-release behavior.

### 4. Add an atomic LocalStore refinement operation

`LocalStore` will expose one Activity refinement operation accepting the original Activity identifier, validated draft, and timestamp. In one write transaction it will:

1. Fetch the original Activity by identifier and return a missing outcome if absent.
2. Normalize and validate the draft name and notes.
3. Check for another active Activity with the same normalized name, excluding the original identifier.
4. Return a collision outcome without writing if another identity owns that name.
5. Update name, notes, Categories, and `updated_at` on the original row.
6. Enqueue one update outbox operation containing the complete updated Activity.
7. Return the updated Activity.

The database unique index remains the race guard; a constraint failure is translated to collision when the winning row can be resolved. The operation does not use create-or-resolve, so it can never replace the selected identifier with a different Activity or restore a pending deletion as a side effect.

Alternative considered: construct a modified `Activity` in the view model and call `updateActivity`. Rejected because preflight collision lookup and update would not be atomic, and raw constraint errors would lose the typed behavior needed by the editor.

### 5. Replace Activity values in place without transitioning TrackState

On save success, `TrackViewModel` refreshes the catalog and replaces the associated `Activity` in the current state while preserving the state case and associated timer data:

- ready remains ready;
- running preserves `startedAt` and the active ticker;
- saving preserves `startedAt`;
- saved preserves its duration and scheduled reset;
- recoverable error preserves `startedAt` and retry behavior.

The editor then dismisses. Cancel performs no mutation. Collision or persistence failure stays inside the editor with the draft intact and leaves Track's persisted Activity snapshot unchanged until save succeeds.

Alternative considered: call `select(updatedActivity)` after save. Rejected because `select` intentionally returns Track to ready, resets elapsed time, dismisses search, and emits selection feedback; all are incorrect for refinement during running, saving, saved, or error states.

### 6. Collapse unmatched creation to one ordinary row action

`ActivitySearchContentView.createRow` becomes one full-width quick-create button. The configure target, its accessibility identifier and localization key, configured editor presentation, collision alerts, and related previews/tests are removed. Quick creation still uses the existing atomic create-or-resolve operation and prepares the resulting Activity; the Refine button becomes available after the search sheet dismisses.

This preserves the shortest creation path while making optional metadata discoverable at a stable location for both new and existing Activities.

## Risks / Trade-offs

- [The Refine button compresses long Activity names] -> Give the Activity control flexible width, keep Refine's label compact and non-shrinking, enforce one-line truncation, and verify large Dynamic Type layouts.
- [Editing while running changes labels used elsewhere] -> Preserve `activity_id`, update only the Activity catalog record, and replace the in-memory state snapshot without touching the timer singleton or ticker.
- [A sync pull changes the Activity while the editor is open] -> Save uses a fresh timestamp and existing LWW/outbox policy; a missing original fails without recreation, while a normalized-name collision remains explicit.
- [The selected Activity is deleted before Refine opens or saves] -> Resolve by identifier before presentation and return a missing outcome on save; clear stale preparation only when the Activity no longer exists.
- [Removing configured creation leaves obsolete state and localization] -> Delete configured-creation state, callbacks, alerts, identifiers, tests, and unused strings in the same change; update both locales and localization coverage together.

## Migration Plan

1. Add and test the atomic LocalStore refinement outcome without changing UI call sites.
2. Convert Activity Editor to persisted-Activity edit mode with complete value prefilling and save/collision/failure tests.
3. Add Track-level refinement presentation and update every non-idle state in place after save.
4. Render the selected-Activity row and trailing Refine action, then remove configured creation from search and its state machinery.
5. Update requirements, design documentation, localization, previews, and UI coverage.
6. Run SwiftLint, warning-as-error build, the complete iOS test suite, and simulator checks for idle/ready/running/error states, long names, Dynamic Type, VoiceOver, light/dark appearance, and English/Russian.

Rollback restores the configured-create search branch and removes the Track refinement presentation. No database or API migration is involved.
