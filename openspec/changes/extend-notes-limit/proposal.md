## Why

The 280-rune notes bound now blocks real usage: the multiline editor and the dedicated Notes page removed the friction that used to keep notes short, but nothing client-side counts — a long note saves locally and only detonates at sync-push time, where a notes `validation_error` additionally wedges the ordered outbox behind the doomed row. Raising the bound to 2000 runes fits genuine journaling while keeping relay hygiene; the client gets a live counter so the limit is visible at typing time instead of at sync time.

## What Changes

- Relay notes bound 280 → **2000 trimmed runes** (`maxNotesLen`; counting rule unchanged). The 422 message keeps its wording pattern with the bumped number ("Notes must be 2000 characters or fewer").
- OpenAPI `notes.maxLength` 280 → 2000 in all three schemas (EntryCreate, EntryUpdate, Entry read).
- iOS `NotesEditorPage` gains a live subtitle: `<entry name> • <count>/2000` (name omitted when empty), counting every rune so each keystroke moves the counter by one. The counter turns red past the bound; ✓ stays enabled and an over-limit save attempt shakes the subtitle and plays the error haptic (no save, no pop).
- Both editor call sites (entry form, running Track) pass the entry name into the page.
- Rows already stuck over 280 self-heal: they drain on the next cycle after the raise, no user action needed.

Non-goals (explicit):
- No sync-drain behavior change: a notes `validation_error` keeps aborting the cycle with the row queued (user decision).
- No message rewording beyond the number ("characters" stays); no name-limit change (60 stays).
- No storage change: `TEXT` columns on both sides already unbounded; no migration.
- No OpenAPI version bump (widening only; no client enforces the old bound).

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `entry-editor`: Notes editor page gains the localized counter subtitle, red over-limit state, and shake-the-subtitle + error-haptic on over-limit save (✓ never gates).
- `local-first-store`: entry `notes` bound max 280 → 2000 runes.

## Impact

- Backend: `internal/handlers/catalog_validators.go` (const + message), `backend/api/openapi.yaml` (×3), `internal/handlers/entries_test.go` (gate + boundary tests). `go test ./...` incl. the `internal/contract` gate stays green.
- iOS: `Core/Design/Components/NotesEditorPage.swift` (subtitle, counter, subtitle shake + haptic, `entryName` param), `LogTimeView` + `TrackContent` call sites, new `L10n` keys in both locales (+ `allCases` coverage). Pure `NotesCounter` helper (untrimmed scalars + over-limit) for unit tests. `Theme` colors only. Reuses the existing `Haptics` helper.
- Authoritative docs: `openspec/specs/entry-editor/spec.md`, `openspec/specs/local-first-store/spec.md`; FURPS `Activity_Catalog_and_Categories.md` U1 + Limits row; `Design/BACKEND/Entry_Catalog_API.md` (×2).
- Stacking: `separate-notes-editor` is implemented but unarchived — archive it FIRST so its presenter baseline folds in; this change's entry-editor delta is written as a superset (presenter + counter) so it validates now and archives cleanly after, in that order.
- External behavior (ctx7): SwiftUI library `/websites/developer_apple_swiftui`, query `keyframeAnimator shake animation validation` (trigger-keyed `keyframeAnimator` + `KeyframeTrack`, iOS 17+ API); version pin iOS 18+ (repo floor, no availability guards).
