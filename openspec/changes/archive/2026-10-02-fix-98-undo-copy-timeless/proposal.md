## Why

Both delete confirmations promise a bounded undo lifetime ("until it syncs") that contradicts the real buffer semantics in `UndoBufferStore.swift:4-14` — earliest-of(push success, restart-commit), no wall-clock — and contradicts the baseline spec's opposite bound (`category-management/spec.md:162-184`, "until restart"). The copy is wrong in both directions, in both languages (issue #98).

## What Changes

- Timeless copy for BOTH delete messages, EN + RU: `entry.deleteMessage` (en:168) and `delete.category.message` (en:211) drop the lifetime clause → "You can shake to undo." + RU equivalent ("Отменить можно встряской.").
- `String+Localized.swift` cases unchanged in shape (same keys); `LocalizationTests.swift:173` snapshot updated to the timeless strings.
- Delta spec syncing `category-management:164` ("…except the push-then-commit push") to the full earliest-of(push success, restart-commit) lifetime, plus a FURPS `Activity_Catalog_and_Categories.md` R3 note pointing at the spec (no behavior change — copy + spec wording only).
- No store, sync, view-model, or UI-structure changes; no new strings beyond the rewritten values (U4: both `en.lproj` + `ru.lproj` + `L10n` stay in sync).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `category-management`: undo-lifetime wording for the buffered category deletion — earliest-of(push success, restart-commit), no wall-clock; user-facing copy carries no lifetime, the spec carries the full lifetime.

## Impact

- Affected code: `en.lproj/Localizable.strings` (2 values), `ru.lproj/Localizable.strings` (2 values), `LocalizationTests.swift` snapshot; docs: `openspec/specs/category-management/spec.md:162-184` delta + `Requirements/FURPS/Activity_Catalog_and_Categories.md` R3 note.
- Authoritative docs: `UndoBufferStore.swift:4-14` (truth), `openspec/specs/category-management/spec.md:162-184` (stale bound), `openspec/specs/local-first-store/spec.md` ("Durable undo buffer"), `openspec/specs/entry-editor/spec.md` (entry delete buffer requirement).
- Non-goals: no behavior change to buffering, supersession (U7), in-flight-push guard, or the DEFAULT system Undo prompt; no new localization keys; no OpenAPI change (S10 — no endpoint touched).
