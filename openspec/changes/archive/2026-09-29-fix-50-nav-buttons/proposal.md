## Why

Follow-up on #50 (reopened): `fix-entry-form-gestures` gave the pushed EDIT form a real back stack, but the form kept its own text `Cancel` button next to the system Back (`<`) button, and `Save`/`Add` stayed text buttons. The issue prescribes Apple Calendar's nav-bar grammar instead: on the pushed entry-editing page the Back button stays, `Cancel` is retired, and `Save` becomes a checkmark (`✓`) with the same action and gating; on the `Log Time` sheet `Cancel` becomes a cross (`X`) and `Add` becomes `✓` with unchanged actions/gating. Reference: `gh issue view 50` comment screenshots (Calendar `Edit Event` sheet: `X` leading, `✓` trailing).

## What Changes

- `LogTimeView.chrome()` toolbar only (the single shared chrome for CREATE sheet + pushed EDIT/LOCKED — both modes live in `LogTimeView.swift`):
  - Pushed presentation (`embeddedInNavigationStack`, i.e. EDIT + LOCKED via History): **no** leading dismiss item — the system Back button owns dismissal. EDIT confirm becomes `✓` (`checkmark` symbol), same `save()` action, same `isAddEnabled` gate, same `EntryEditSaveButton` identifier. LOCKED keeps Back only (no confirm, as today).
  - CREATE sheet: leading `Cancel` text becomes `X` (`xmark` symbol, same `dismiss()` action, new `LogTimeDismissButton` identifier); trailing `Add` text becomes `✓`, same `save()` action, same gate, same `LogTimeAddButton` identifier.
  - Placements (`.cancellationAction` / `.confirmationAction`) and default toolbar tint are unchanged — that is the Calendar grammar (leading/trailing, `X`/`✓`, accent tint).
  - Three new `L10n` accessibility labels (EN + RU) for the icon buttons; visible copy otherwise unchanged.
- Non-goals: name/notes field internals (#42's agent), picker layout (#51's agent), `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackContent.swift`. No view-model, store, sync, or backend change.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `entry-editor`: pushed EDIT/LOCKED nav-bar chrome (Back-only dismissal; `✓` confirm in EDIT).
- `manual-entry`: CREATE sheet nav-bar chrome (`X` dismiss, `✓` confirm).

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift` (`chrome()` toolbar region only).
- `ios/TimeOfLife/TimeOfLife/Localization/String+Localized.swift` + `en`/`ru` `Localizable.strings` (3 new a11y labels) + `TimeOfLifeTests/LocalizationTests.swift` (count 140 → 143).
- Repro evidence (pre-fix build on iPhone 17 sim): pushed EDIT shows `<` + `Cancel` + `Save`; CREATE shows `Cancel` + `Add` — screenshots in PR body.
- No ctx7 fetch needed (repo-internal SwiftUI toolbar; no external-dep behavior involved).
- No migration (pre-release policy); rollback is revert-only.
