## 1. Store: entry undo restore helper

- [ ] 1.1 Add an entry-snapshot restore helper to `LocalStore` mirroring `undoCategoryDeletion` (re-insert the `TimeEntry` from the buffer payload + delete the buffer row in one transaction, no outbox row); unit-test round-trip (enter → restore → entry back, no outbox; commitExpired → outbox delete row).
- [ ] 1.2 Filter committed entries in `ActivityDetailViewModel.load()` (`endedAt != nil`); add tests (in-progress excluded from day groups; totals exclude NULL durations; empty-after-filter state).

## 2. Unified entry form (CREATE / EDIT / LOCKED)

- [ ] 2.1 Extend `LogTimeViewModel` with a mode enum + `initialEntry` draft: prefilled activity/starts/ends in EDIT, `save()` branching to `updateEntry` (bump `updatedAt`; stale-`false` → localized error, draft intact, form stays open); LOCKED mode exposes entry values read-only with no confirm path.
- [ ] 2.2 Extend `LogTimeView` with mode-specific chrome: "Edit entry" title + Cancel/Save (EDIT), imported title + Cancel only (LOCKED), disabled-dimmed Activity/Starts/Ends + provenance note (LOCKED), bottom-of-page destructive Delete button (EDIT + LOCKED, `Theme` colors only).
- [ ] 2.3 SwiftTesting coverage for the VM: EDIT prefill, validity gate in EDIT (Save disabled when end ≤ start), Start-push duration preservation in EDIT, save payload shape (`updateEntry` path, `updated_at` bump), stale-save error path, LOCKED rules (no confirm, values exposed read-only).
- [ ] 2.4 Add EN + RU `L10n` strings (Edit entry title, Save, Delete entry, delete confirm title/message/actions, stale-write error, locked provenance note, shake-undo hint); update `LocalizationTests` counts.

## 3. Delete with confirm → buffer → shake-to-undo (no toast)

- [ ] 3.1 Wire Delete button → destructive confirm alert (names the activity) → `UndoBufferStore.enter` → dismiss form; add `performUndo` + `registerSystemUndo(with:)` to `ActivityDetailViewModel` mirroring `ManageCategoriesViewModel`.
- [ ] 3.2 Wire `.onShake` / `ShakeHostingController` path on the detail surface to `performUndo()`; verify foreground `commitExpired` covers entries via the existing global reconciliation (no new lifecycle code).
- [ ] 3.3 Tests: confirm deletes into buffer (lists update, no outbox row); alert-dismiss keeps entry + draft; shake within window restores (nothing synced); expiry commits on foreground; supersession (newest buffer row only, incl. cross-surface ordering).

## 4. ActivityDetail tappable rows + cover presentation + reload chain

- [ ] 4.1 Make `ActivityEntryRow` rows tappable (button traits + `accessibilityIdentifier("ActivityEntryRow(\(id))")`-stable) opening the entry form as a `fullScreenCover` (EDIT for `manual`, LOCKED otherwise); CREATE entry points keep sheet presentation.
- [ ] 4.2 Reload identity/categories/entries/total after the cover's Save/Delete dismisses via the existing `needsReloadAfterSheet` flag; cover reassignment-away and delete-last-entry states (sheet stays open, list/total recomputed).
- [ ] 4.3 Propagate to History via the existing `invalidate()`/`loadIfNeeded` chain (edited values in day groups; deleted entries gone; empty day groups removed); keep History rows swipe/long-press-free.
- [ ] 4.4 UI tests: row tap opens cover in the right mode (manual EDIT / imported LOCKED); save/delete refresh detail totals and History groups; reassigned entry leaves the old activity's list.

## 5. Verification + docs (S5)

- [ ] 5.1 `xcodegen generate` + `swiftlint lint --strict` clean; `xcodebuild` build warning-free; `xcodebuild test` green (incl. new tests); manual smoke on iOS 15 + 26 simulators (cover presentation, picker stacking over cover, locked-mode dimming), light/dark, EN/RU, Dynamic Type.
- [ ] 5.2 Re-check `Requirements/FURPS/Timetracking.md` + `Common.md` rows (U4 locales, Theme-only, R1/R3 undo semantics); fix conflicts if any.
- [ ] 5.3 Update `docs/history-roadmap.md` (§1–2 resolved/superseded by this change: unified form instead of separate EntryDetail) and `docs/project-context.md` (entry edit/delete shipped; UndoToast still deferred; ActivityDetail committed-only + tappable rows).
- [ ] 5.4 `openspec validate --change edit-entry-from-activity-detail` passes.
