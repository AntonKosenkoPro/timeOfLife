## 1. Change artifacts

- [x] 1.1 Write delta specs (`specs/entry-editor/spec.md`: entry-form clear + autocomplete; `specs/timer-capture-experience/spec.md`: Track clear + autocomplete) + `design.md` (shared clear button, prefix-filter rule, overlay-vs-inline, pick contract) + this `tasks.md`.
- [x] 1.2 `openspec validate feat-name-field-affordances --strict` passes; fix all findings.

## 2. Implementation (name-field UI + suggestion source wiring only)

- [x] 2.1 Shared `ClearTextButton` in `Core/Design/Components` (`xmark.circle.fill`, `Theme.textSecondary`, 44 pt target, localized label, caller-supplied identifier). `Theme` colors only. Do NOT touch `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackView.swift`.
- [x] 2.2 `TrackViewModel`: pure `nameSuggestions()` over `recents` + `nameDraft` (case-insensitive prefix, exact excluded, newest-first preserved); `clearNameDraft()` (empty + re-sync to idle, cancel deferred start). Save/validation/start/stop paths untouched.
- [x] 2.3 `TrackContent.nameField`: HStack field + clear (visible when non-empty and not running); suggestions card in `.overlay` below the field (zero layout shift) with container id `TimerNameSuggestions` and indexed row ids; pick routes through existing `select(_:)`.
- [x] 2.4 `LogTimeViewModel`: `nameRecents` + `loadNameRecentsIfNeeded(store:)` (same `recents(limit: 6)` path, failure → empty); pure `nameSuggestions()`; `applySuggestion(text:categoryIDs:)` (fill + inherit, no save); `clearName()` (text only). Save/validation (`isAddEnabled`, auto-push, `save()`, `deleteConfirmed()`) untouched.
- [x] 2.5 `LogTimeView.nameCard`: HStack field + clear (visible when non-empty and `!isLocked`); inline suggestions list with container id `EntryNameSuggestions` and indexed row ids; pick routes through `applySuggestion`. Load recents in the existing `.task` beside categories. Do NOT touch card order, cover/push presentation, or the toolbar principal region (sibling change owns it).
- [x] 2.6 `L10n` en+ru: `name.clear` (`Clear name`), `name.suggestions` (`Suggestions` container label); bump `LocalizationTests` count.

## 3. Tests

- [x] 3.1 `TrackViewModelTests`: suggestions — prefix match newest-first; case-insensitive input; exact excluded but case-variant kept; empty/whitespace input → none; no recents → none. Clear — draft emptied, state returns to idle.
- [x] 3.2 `LogTimeViewModelTests`: suggestions — same filter rule over seeded `nameRecents`; `applySuggestion` fills text + ordered categories without touching notes/interval; `clearName` empties text only.
- [x] 3.3 `LocalizationTests` parity covers the new keys (count 139 → 141 combined; 139 for the subtitle change alone).
- [x] 3.4 Suggestion rendering/overlay anchoring is NOT unit-testable (no view-test infra) — covered by the manual checklist (§4).

## 4. Manual on-device checklist (autocomplete UX is device-sensitive)

- [x] 4.1 Track: type a prefix → suggestions appear without moving Start; pick → exact text + categories fill, ready timer, nothing starts; clear → field empties, idle returns. (Device pass 2026-09-29: pass except suggestions overflow the Start button in some cases — issue #69, ships as known issue for internal TestFlight.)
- [x] 4.2 Entry form (CREATE + EDIT): same clear/pick behavior inline; pick inherits categories; clear keeps categories/notes/interval. (Device pass 2026-09-29: pass.)
- [x] 4.3 `Gym` vs `GYM`: both suggest on shared prefix; exact typing excludes only the exact one. (Device pass 2026-09-29: pass.)
- [x] 4.4 No suggestions when field empty or exactly matching; LOCKED form shows no clear and no suggestions. (Device pass 2026-09-29: pass.)
- [x] 4.5 320 pt + Dynamic Type + light/dark + EN/RU spot-check; VoiceOver reads clear button + suggestion rows. (Device pass 2026-09-29: pass.)

## 5. Verification + docs (S5)

- [x] 5.1 `swiftlint lint --strict` clean (0 violations); warning-as-error `xcodebuild build-for-testing` green; full iOS suite green — 503 tests passed, 0 failed (serialized per `docs/ios-test-loop.md`, booted-sim-by-ID destination). Backend untouched (no `go` run needed).
- [x] 5.2 Re-checked `Requirements/FURPS/Timetracking.md` (F13 comment gains the affordances sentence) + `Common.md` (no conflicts).
- [x] 5.3 Stacked PR (PR #56 opened, unmerged) targeting `fix/50-51-entry-form-gestures` (retargeted to `main` after #54 merges): title "Entry duration subtitle plus name-field affordances (#36, #42, #43)", body "Fixes #36, fixes #42, fixes #43" + what changed + verification evidence + untested checklist items. DO NOT merge.

## 6. AI-review findings fix (PR #56, OpenCodeReview MEDIUM + LOW)

- [x] 6.1 `TrackContent.nameField` (MEDIUM): `.accessibilityIdentifier("TimerNameField")` / `.accessibilityLabel` moved off the HStack container onto the `TextField` itself; the wrapper is now transparent via `.accessibilityElement(children: .contain)` so VoiceOver and TextField lookups see the editable field.
- [x] 6.2 `TrackContent.nameField` (LOW): `vm.nameSuggestions()` computed once per body evaluation into `suggestions` and passed through to `nameSuggestionsCard(_:)` (now a function taking the array) — no double evaluation per render.
- [x] 6.3 `openspec validate feat-name-field-affordances --strict` passes.
