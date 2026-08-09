## 1. Local Activity Refinement

- [x] 1.1 Add an atomic `LocalStore` refinement outcome that validates the draft, preserves the Activity identifier, rejects normalized-name collisions, replaces Category joins, updates `updated_at`, and enqueues one update outbox row in the same transaction.
- [x] 1.2 Add LocalStore tests for successful name/notes/Category updates, same-name edits, normalized-name collision without partial writes, missing Activity, invalid input, unique-index race fallback, and update outbox payload.

## 2. Activity Editor Edit Mode

- [x] 2.1 Convert `ActivityEditorViewModel` from create-or-resolve input to an existing-Activity edit draft prefilled with persisted name, notes, and Category identifiers.
- [x] 2.2 Update `ActivityEditorView` to show edit copy and report the updated Activity while preserving its current validation, loading, keyboard, Cancel, error, and pinned Save behavior.
- [x] 2.3 Replace create-mode editor tests with edit-mode coverage for complete prefilling, successful same-identity save, no-change save behavior, collision, missing Activity, validation, retryable persistence failure, and Category loading/selection.

## 3. Track Refinement Flow

- [x] 3.1 Add Track-owned refinement presentation that resolves the selected Activity before opening and remains independent from Activity search state.
- [x] 3.2 On refinement save, refresh the catalog and replace the Activity associated with ready, running, saving, saved, and recoverable error states without changing elapsed time, start time, saved duration, ticker, retry behavior, or selection identity.
- [x] 3.3 Render a selected-Activity `HStack` with the existing picker or label and a trailing localized `TimerActivityRefineButton`; hide Refine while idle and disable it only during stop-save persistence.
- [x] 3.4 Add Track view-model tests for presentation from new and existing selections, stale selection handling, cancel/failure preservation, and state-preserving saves across every non-idle timer state.
- [x] 3.5 Add or update UI tests and previews for Refine visibility, adjacent placement, persisted-value prefilling, save/cancel behavior, running-timer continuity, long names, and no Refine action while idle.

## 4. Simplify Activity Search

- [x] 4.1 Replace the split unmatched-name create/configure row with one full-width quick-create action and remove the configure target and accessibility identifier.
- [x] 4.2 Remove configured-creation editor/collision fields, methods, alerts, callbacks, previews, and tests from `ActivitySearchState`, `TrackViewModel`, and `ActivitySearchSheet` while preserving quick-create, restoration, collision reuse, and search-draft behavior.
- [x] 4.3 Remove obsolete configured-creation localization and add the Refine label and accessibility copy to `L10n`, English, Russian, and localization completeness tests.

## 5. Requirements And Design Documentation

- [x] 5.1 Update `Requirements/FURPS/Activity_Catalog_and_Categories.md` and relevant use-case narratives so Track search creates by name only and selected Activities are refined afterward.
- [x] 5.2 Update `Design/SCREENS/TimeTracking.md`, `Design/SCREENS/ActivityEditor.md`, `Design/COMPONENTS.md`, and `Design/INTERACTIONS.md` for the adjacent Refine action, edit-mode prefilling, same-identity saves, and removal of configured creation.
- [x] 5.3 Update `README.md` simulator/smoke guidance and `AGENTS.md` project context where they describe the Activity preparation flow; confirm the OpenAPI contract needs no change.

## 6. Verification

- [x] 6.1 Run `xcodegen generate`, `swiftlint lint --strict`, the warning-as-error iOS simulator build, and the complete iOS test suite; fix every failure and warning.
- [x] 6.2 Run backend `gofmt -l .`, `go vet ./...`, `golangci-lint run`, and `go test ./... -cover`; confirm the iOS-only change introduces no backend regression.
- [x] 6.3 Verify on the minimum supported and newest available iOS simulators in English and Russian, light and dark appearance, Dynamic Type, VoiceOver, and Reduce Motion; confirm quick-create then Refine, existing-Activity Refine, running-timer refinement, cancellation, collision, and failure recovery.
- [x] 6.4 Re-read the changed FURPS rows and delta scenarios, run `openspec validate refine-selected-activity-from-track --strict`, and resolve every validation finding.
