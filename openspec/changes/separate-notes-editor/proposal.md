## Why

The entry-form Notes row is a live-bound inline `TextEditor` (just reworked by `multiline-notes-field`), so long notes compete for space with Start/End/Categories cards and every keystroke mutates the form draft in place with no explicit save/cancel grammar. Separately, the running Track timer has no notes path at all — `TimerService.stopTimerDraft` always saves `notes: ""` — so thoughts captured mid-run are lost (GitHub issue #124).

## What Changes

- Entry-form Notes row becomes a read-only presenter + dedicated editor page:
  - Presenter is a multiline `Text` label with a 1–5 line window (`lineLimit(1...5)`, truncation past 5) replacing the inline `TextEditor`.
  - Tapping the presenter pushes a separate Notes editor page; the page carries X (cancel/discard) + ✓ (save/commit) in the navigation bar (`EditorToolbar` Calendar grammar).
  - Editor `TextEditor` keeps Return-inserts-newline with no keyboard Done key; dismissal/commit is X/✓ only (plus system back/push pop semantics where applicable).
- Track running screen gains an add/edit-notes button trailing the locked activity-name row, visible only while recording (running/error states); it opens the same Notes editor page bound to the running draft.
- Running draft notes persist with the draft (crash-safe like text/tags) and `Stop` saves the entry with the final notes instead of `""`.
- 280-rune notes cap unchanged; validity gate unchanged (notes never gate confirm).

Non-goals (explicit):
- No notes-limit change, no length validator addition, no OpenAPI/backend/sync change (notes stays a plain string; newlines count as runes as today).
- No History row notes rendering (`EntryRow` unchanged), no Insights change.
- No LOCKED-mode editing (imported entries stay read-only; presenter renders read-only there).
- No widget / lock-screen Control notes display (`timer_state` readers ignore the new column).
- No UndoToast / shake-to-undo change; no device quota / picker (#46).

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `entry-editor`: Notes row shifts from live-bound inline editor to presenter (1–5 lines) + pushed editor page with X/✓ commit semantics.
- `timer-capture-experience`: running Track gains a notes button (recording-only, trailing the locked name) and the running draft carries notes through to `Stop`.
- `local-first-store`: the `timer_state` singleton / running-draft persistence gains notes alongside text + category snapshot.

## Impact

- iOS only. No backend, OpenAPI, sync-protocol, or storage-engine change beyond the `timer_state` notes column (pre-release: edited in place, no migration branch).
- Affected code: `LogTimeView.notesCard` (presenter), new shared Notes editor page (near `NamePicker`/`EditorChrome`), `TrackContent` locked-name row + button, `TrackViewModel` + `TrackState.Draft`, `TimerService.start/stopTimerDraft`, `LocalStore.saveTimerDraft` / draft update / `RunningTimerDraft`, `L10n` + `en`/`ru` strings, `Theme` colors only.
- Authoritative docs: `openspec/specs/entry-editor/spec.md` (Notes row), `openspec/specs/timer-capture-experience/spec.md` (running tags + Stop saves empty notes today), `openspec/specs/local-first-store/spec.md` (timer_state singleton D8); FURPS `Timetracking.md` F13 + `Activity_Catalog_and_Categories.md` U1 (280 cap, unchanged).
- External behavior (ctx7): SwiftUI library `/websites/developer_apple_swiftui`, queries `Text lineLimit multiline truncation` (closed-range `lineLimit(1...5)` truncates `Text`, vertical fields scroll) + `TextEditor newline input` (binding/initializer contract); version pin iOS 18+ (repo floor, no availability guards).
- Systems: widgets/Controls read `timer_state` but ignore notes; sync outbox/entry payloads carry notes as today (no relay change).
