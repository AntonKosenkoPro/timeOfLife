## Context

See `proposal.md` for motivation. Current state: `NotesEditorPage` (`initialText` + `onSave`, `EditorToolbar` X/✓, hidden Back, Return=newline, placeholder overlay) is shared by the entry form and the running Track button; the relay gates notes at 280 trimmed runes (`maxNotesLen`, `validateNotes` on create + update) with `maxLength: 280` in three OpenAPI schemas; nothing client-side counts.

Constraints from `docs/project-context.md`: `LocalStore` is the single mutation chokepoint (untouched — no storage change); `Theme` semantic colors only; user-facing strings via `L10n` + both locales (U4); iOS 18+ with no availability guards; OpenAPI is authoritative (S10) — the three schemas move together with the validator; pre-release — no on-disk migration.

External docs (ctx7, fetched during proposal): library `/websites/developer_apple_swiftui`, query `keyframeAnimator shake animation validation` (trigger-keyed `keyframeAnimator` + `KeyframeTrack` for offset/scale/rotation); version pin iOS 18+ (repo floor — the API exists since iOS 17, no availability guards needed).

## Goals / Non-Goals

**Goals:**
- The 2000 bound is visible at typing time (live counter) with a forgiving over-limit grammar (red + shake, never a dead ✓).
- Client counting mirrors the server rule exactly where it matters (trim + code points), with the relay authoritative on disagreement.
- One implementation covers both editor callers (the page is already shared).

**Non-Goals:**
- No drain-heal for over-limit rows (user decision — the wedge stays; the counter makes it unreachable in practice).
- No new navigation, no editor layout change, no presenter change.

## Decisions

1. **2000 trimmed runes, counting rule untouched.** The product question (how long) is settled at 2000; the technical rule (trim, then count runes) is unchanged, so boundary behavior moves with the constant and every existing test keeps its shape. Below ~500 we would return within months; unlimited is rejected for relay hygiene (one client pushing MB notes taxes every full-pull).
2. **Pure `NotesCounter` helper as the testable seam.** `trimmedCount` (trim + `unicodeScalars.count`, the Swift measure closest to Go's `RuneCountInString` — identical for all valid strings except multi-scalar graphemes) plus `isOverLimit`. The page observes it; unit tests pin ASCII, trim, multibyte, and boundary behavior. The known edge (ZWJ emoji counts fewer client-side, so a boundary note can still 422) is accepted: the server stays authoritative and the kept drain behavior applies.
3. **Subtitle in the principal toolbar (LogTime `titleSubtitle` precedent).** A `ToolbarItem(.principal)` VStack keeps the page title (`Notes`) and adds the footnote counter line: `<name> • <n>/2000`, name omitted when empty. Red past the bound (`Theme.danger`); single-line truncation at large Dynamic Type (same contract as the duration subtitle).
4. **Shake via trigger-keyed `keyframeAnimator`, ✓ never disabled.** A horizontal-offset `KeyframeTrack` keyed on a failed-attempt counter (cite ctx7 above); a failed save shakes and stays (no save, no pop). A disabled ✓ would strand keyboard users with no explanation; the shake names the problem in place. Under Reduce Motion the shake is suppressed (counter still turns red).
5. **`entryName` as a static open-time snapshot.** Neither caller can retext underneath the page (form name row is its own pushed page; the running name is locked), so a plain `let` avoids observation wiring. Callers pass the draft name (form) / locked text (Track).
6. **Message number bump only; name limit untouched.** `"Notes must be 2000 characters or fewer"` keeps the established phrasing (user decision); 60-char name identity is unrelated to prose length.
7. **Archive order + rollout safety.** `separate-notes-editor` archives first (its presenter baseline folds in; this delta already contains the merged text so order is the only constraint). Stuck >280 rows self-heal on the next post-deploy drain. Mixed versions are safe: no client ever enforced the old bound, and the relay only widens acceptance. Rollback is a one-constant revert.

## Risks / Trade-offs

- [Risk] Grapheme/rune boundary mismatch (ZWJ/modifier emoji) lets a note past the client gate that the relay rejects → Mitigation: accepted edge (rare, boundary-only); the kept drain behavior surfaces the existing 422 path, and the counter is honest for all normal text.
- [Risk] Two unarchived deltas touch the same entry-editor requirement (presenter delta + this counter delta) → Mitigation: this delta carries the merged text and tasks enforce archive order (presenter first); `validate` pins scenario names on both.
- [Risk] Subtitle crowding at accessibility sizes (title + counter + X/✓) → Mitigation: single-line truncation per the duration-subtitle contract; verified in the sim battery.
- [Risk] Counter `allCases`/locale churn (new keys) → Mitigation: two keys (`notes.editorSubtitle` with name, `notes.editorCounter` bare), both locales, `LocalizationTests` extended — the standard U4 flow.

## Migration Plan

Backend-only const + OpenAPI + tests (no migration, no deploy-order constraint beyond shipping together); app-side page + keys + call sites. No data migration either side (`TEXT` throughout). Rollback is a one-constant revert on the relay; already-synced ≤2000 notes stay valid under any rollback that keeps ≥280.
