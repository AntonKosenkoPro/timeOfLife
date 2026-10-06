## Context

See `proposal.md` for motivation. Current state: `LogTimeView.notesCard` is a live-bound inline `TextEditor` (3-line reserve, top-trailing ×, Return=newline, tap-away/scroll-away dismiss) after `multiline-notes-field` + `fix-67-notes-clear-keeps-keyboard`; `TrackContent` locked-name row (`lockedNameLabel`) has no notes affordance; `TrackState.Draft` + `RunningTimerDraft` + `timer_state` carry `(text, category_ids, started_at, status)` only and `TimerService.stopTimerDraft` saves `notes: ""`.

Constraints from `docs/project-context.md`: `LocalStore` is the single mutation chokepoint (all draft writes go through it); `Theme` semantic colors only; user-facing strings via `L10n` + both locales (U4); XcodeGen-managed (`project.yml`, never hand-edit `.pbxproj`); iOS 18+ with no availability guards; pre-release — no on-disk migration branches (edit the `timer_state` shape in place); OpenAPI is authoritative but untouched (notes stays a plain string); Track D10 main-action geometry must not move.

External docs (ctx7, fetched during proposal): library `/websites/developer_apple_swiftui`, queries `Text lineLimit multiline truncation` (closed-range `lineLimit(1...5)` truncates `Text`, vertical fields scroll) + `TextEditor newline input` (binding/initializer contract); version pin iOS 18+ (repo floor).

## Goals / Non-Goals

**Goals:**
- One shared Notes editor page serving both callers (entry form + running Track) with copy-on-open commit semantics (X discards, ✓ writes back).
- Form Notes row becomes a stable read-only presenter (no live editing, no focus race on the card).
- Running notes ride the existing draft crash-safety (persisted snapshot, carried through `Stop`).
- Zero movement of the Track main action; zero change outside the Notes row interior + locked-name trailing slot + draft notes plumbing.

**Non-Goals:**
- No new navigation pattern (standard push on the caller's `NavigationStack`, `EditorToolbar` X/✓ chrome reused — no custom container).
- No keyboard toolbar Done, no inline × retained on the presenter, no width-reserve for missing affordances.
- No History/Insights/widget/Control rendering of notes; no sync-protocol work.

## Decisions

1. **Shared `NotesEditor` page over two per-caller editors.** Both callers need identical grammar (prefill → edit copy → X/✓). One view beside `NamePicker`/`EditorChrome` with `initialText` + `onSave(String)`; callers own the write-back (`LogTimeViewModel.notes` vs running-draft notes + persist). Rejected: duplicating the editor per caller (divergent grammar within one release).
2. **`EditorToolbar` X/✓ chrome, not `NamePicker` Back/Done, with the system Back hidden.** The issue asks for explicit cancel/save in the navbar; `EditorToolbar` (cancellationAction X + confirmationAction ✓) is the Calendar grammar both forms already use. Spike review locked two refinements: the page hides the system Back button (X is the sole cancel path; swipe-back still pops and discards), and the presenter chrome is variant B (chevron on the caption row with balanced corner margins — caption-row top inset equals the card's trailing inset). `NamePicker`'s chromeless Back + row-tap/Done fits suggestion-picking, not free-text commit. All copy reuses existing `L10n` keys (title, placeholder, X/✓ labels) — no new strings.
3. **Presenter is `Text` with `lineLimit(1...5)`.** Per the fetched `lineLimit` contract, a closed range caps `Text` with truncation (vs scrolling a field) — exactly the 1-min/5-max window. Empty draft shows the existing `entryNotesPlaceholder` copy (reused, no new strings); full text lives only on the editor page. Rejected: keeping a 3-line reserve + inner scroll on the card (that was the inline-editor solution this change retires).
4. **Editor keeps `TextEditor` Return=newline, no Done key.** Carries over `multiline-notes-field` Decisions 1–2 (native newline grammar; dismissal via X/✓ + push-pop, not a toolbar Done). Placeholder overlay and transparent chrome (`scrollContentBackground(.hidden)`, `.font(.body)`) move with it.
5. **Running notes persist in `timer_state` (crash-safe), not memory-only.** Adds a `notes` column to the singleton + `RunningTimerDraft`; `saveTimerDraft` writes it at Start, a focused update rewrites only notes mid-run, `stopTimerDraft` creates the entry from it. Rejected: view-model-memory notes (lost on crash, violating the D8 survive-crash spirit the specs now extend to notes). Widgets/Controls ignore the column (spec-pinned).
6. **Track button is a standalone control OUTSIDE the locked-name `FieldCard`, recording-only (spike-approved, spacing refined in review).** Layout: `HStack[FieldCard(timer-icon + locked text), 44 pt note.text button]` at the screen's trailing padding — no row-local inset. The glyph renders larger than body (`title2`) inside the 44 pt target. The button tint signals presence (accent when the draft has notes, secondary when empty); no preview/readout on Track. Row height matches `lockedNameLabel`, D10-safe. Rejected: a separate notes row under the name (adds height, moves the main action against D10), the 1–5 line presenter on Track (issue asks for a button only), and the earlier inside-the-card placement (spike review: button belongs outside the field).
7. **Commit touches nothing but notes; validity gate re-evaluates.** Notes never gate confirm (unlike name/interval), so ✓ is always enabled (even when unchanged — a no-op save pops). LOCKED mode gets the presenter with no `NavigationLink` (disabled + dimmed, provenance note unchanged).

8. **Form spacing polish is user-directed and point-level (no normative spec).** The Name-row chevron move (value row → caption row, unifying Name with the Notes presenter grammar above) is specced (caption-row chevron requirement); the `Spacer()` insertions in the Categories and Start/End cards and the Track button's `title2` glyph size live in code/`Theme` tokens only, per the repo convention that specs never pin points.

## Risks / Trade-offs

- [Risk] Same files the just-archived `multiline-notes-field` + `fix-67` touched (`notesCard`, `FormCard` resign topology) churn again → Mitigation: this design retires the inline-editor interior but keeps the #118 plain-tap-away baseline and the `TextEditor` newline/placeholder decisions; rebase onto `main` post-archive, no parallel branch.
- [Risk] `timer_state` shape edit touches widget/Control readers → Mitigation: additive nullable `notes` column, readers select explicitly and ignore it; pre-release, no migration branch; covered by store round-trip tests.
- [Risk] Copy-on-open vs live-bound: user edits on the page, then edits Start/End on the form before saving notes (form case) → Mitigation: page holds its own `@State` copy; only ✓ writes back, so interleaved form edits can't half-merge — last ✓ wins for notes only.
- [Risk] Push-from-Track while the second ticker/timer fires (elapsed updates during edit) → Mitigation: notes page reads no ticker state; draft text/tags continue underneath; ✓ writes notes field only.
- [Risk] VoiceOver order on presenter (label → value → edit hint) and on the page (editor → X/✓) → Mitigation: keep `EntryNotesField`-family identifiers distinct per surface; verify rotor order in the sim battery + physical-device pass.
- [Risk] 5-line presenter at large Dynamic Type grows the form card → Mitigation: form already scrolls (`ScrollView` + `scrollDismissesKeyboard`); card order and Start/End collapsed full-width rules unchanged.

## Migration Plan

iOS-only, no data migration, no API/contract change. Land as one change (form presenter + shared page + Track button + draft plumbing) since the page is shared; rollback is a straight revert of the presenter interior + button + `timer_state` column (spec deltas revert with it). Archive folds the three delta specs (`entry-editor`, `timer-capture-experience`, `local-first-store`) into the baselines per the normal flow.

## Open Questions

- Final trailing-button glyph (note vs pencil vs plus-bubble) — visual only, spec pins placement/visibility, not the SF Symbol.
- Editor page title copy (e.g. reuse "Notes" caption vs dedicated title) — localized either way, spec pins X/✓ behavior, not the exact title string.
