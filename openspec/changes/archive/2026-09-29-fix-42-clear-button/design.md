## Context

See proposal.md (Why). Current state constraining the approach:

- `ClearTextButton` (`Core/Design/Components/ClearTextButton.swift`): `xmark.circle.fill`, `.font(.body)`, `Theme.textSecondary`, 44 pt min frame, fixed `name.clear` accessibility label. Callers own visibility: Track shows it when `!vm.nameDraft.isEmpty` (no focus check); entry-form name when `!isLocked && !name.isEmpty` (no focus check); notes has none.
- Focus sources already exist: `TrackContent` has `@FocusState nameFieldFocused`; `LogTimeView` has `@FocusState focusedField: FormField?` (`.name`, `.notes`); `CategoryEditorView` has `@FocusState isNameFocused`. No VM changes needed for focus — the views pass it.
- `TextFieldWithError` is shared by the category editor AND the email-OTP field, so any clear affordance there must be opt-in per call site, never default-on.
- Reference (issue #42 comment, Apple Calendar new-event title row): small dim-gray `×` in a circle tucked at the field's trailing edge, glyph much smaller than the 44 pt tap target.
- Scope guards (parallel agents): do NOT touch toolbar/nav buttons (#50), picker layout (#51), `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`. Diffs stay region-confined.

## Goals / Non-Goals

**Goals:**

- Focused-AND-non-empty visibility on every clear button, pinned by unit tests against a pure helper.
- Notes clear button in the entry form (CREATE + EDIT) with a `clearNotes()` VM method mirroring `clearName()`.
- Category-editor name clear via opt-in props on `TextFieldWithError`.
- Apple-standard restyle matching the reference screenshot.
- Full `TextField` audit with written exclusions.

**Non-Goals:**

- Toolbar/nav-button or picker-layout changes (#50/#51 own those regions).
- New store queries, sync, backend, or OpenAPI work.
- UndoToast, "via <Source>", lock-screen widget, device quota (#46).

## Decisions

### 1. Pure `ClearButtonVisibility.shouldShow(isFocused:text:isLocked:)` helper (over view-only conditions)

SwiftUI view conditions are not unit-testable, and the issue demands the focused-AND-non-empty rule be covered by failing-first tests. A three-line pure helper in `ClearTextButton.swift` (`isFocused && !text.isEmpty && !isLocked`) gives the red tests a seam; each call site passes its existing `@FocusState` plus draft text plus lock state. `isLocked` defaults to `false` so Track/entry-name call sites read naturally.

### 2. Notes clear mirrors the name clear (over a generic field wrapper)

The notes row is a bare `TextField` in `notesCard`, not a `TextFieldWithError`, so the smallest change is the same HStack + `ClearTextButton` pattern with a new `EntryNotesClearButton` identifier and a `clearNotes()` VM method (notes only — name, categories, interval untouched). New `notes.clear` L10n key ("Clear notes" / "Очистить заметки") instead of reusing `name.clear`, so VoiceOver names the right field.

### 3. Opt-in clear on `TextFieldWithError` (over a separate editor field or default-on button)

The component serves the category editor (needs the button) and email-OTP (must NOT have it — auth flow, email keyboard, server-side validation UX). Three optional params (`showClear: Bool = false`, `isFocused: Bool = false`, `onClear`, `clearAccessibilityId`, `clearAccessibilityLabel`) keep every existing call site compiling unchanged while the category editor opts in with `showClear: !vm.name.isEmpty`-style wiring + its `@FocusState`. Email passes nothing.

### 4. Restyle: 17 pt `.secondary` glyph, 44 pt target kept (over shrinking the tap area)

Reference glyph ≈ 16–18 pt dim gray circle. Implementation: `.font(.system(size: 17))` + `.foregroundStyle(.secondary)` (adapts light/dark like the reference) on the image; the Button keeps `minWidth/minHeight 44` + `contentShape(Rectangle())` so the accessible tap target does not shrink — only the visible glyph gets smaller and dimmer. No raw `Color` literals (Theme/system semantics only).

As-built (commit `2fa5608`): 16 pt `Theme.textSecondary.opacity(0.55)` — within the reference tolerance, verified by the §5 screenshots as-is.

### 5. Audit outcome (all `TextField` call sites)

| Field | Clear button | Why |
|---|---|---|
| Track name (`TrackContent.nameField`) | YES — add focus condition + restyle | In scope (#42 title field) |
| Entry-form name (`LogTimeView.nameCard`) | YES — add focus condition + restyle | In scope |
| Entry-form notes (`LogTimeView.notesCard`) | YES — add button + `clearNotes()` | Finding 2 explicitly names it |
| Category-editor name (`CategoryEditorView`) | YES — opt-in on `TextFieldWithError` | Plain-text name entry, same affordance gap |
| Email (`EmailEntryView` via `TextFieldWithError`) | NO | Auth flow: email keyboard + validation-error UX; a custom × would fight the keyboard's own delete and the error-label layout |
| OTP code (`OtpCodeField` hidden backing field) | NO | Not a visible text entry — per-digit boxes with their own UI; a trailing × has no anchor |
| Search fields | N/A | None exist in the app (verified by grep over `Features/`) |

## ctx7

No external-dep behavior involved (pure SwiftUI layout + repo-internal components) — no ctx7 fetch per `docs/project-context.md` (trigger: external-dep behavior; this is repo-internal UI).
