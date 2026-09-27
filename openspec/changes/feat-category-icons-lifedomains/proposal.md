## Why

Category icons are missing whole life domains users log — pet-related and housekeeping-related at minimum (#38). The picker reads as incomplete for anyone tracking those parts of life.

## What Changes

- Expand the closed icon set (Option B, life-domains, as decided): ~14–16 SF Symbols grouped Pets / Home+Housekeeping / People+Family / Body+Rest, e.g. `pawprint, dog, cat, fish, bird, turtle` (pets), `washer, dryer, dishwasher, refrigerator, lamp, sofa, shower` (home — each verified), plus small family/body gap-fillers.
- Every candidate must pass the `canRender` check on iOS 18 (`UIImage(systemName:) != nil`); non-rendering symbols are dropped from the final list, never force-included.
- Parity updates in lockstep (enforced by tests): `CatalogIcon.swift` + `backend/api/openapi.yaml` `CategoryIcon`/`validIcons` + `Design/TOKENS.md` + `L10n.catalogIconName` in en+ru. `IconPickerGrid` picks up new symbols automatically via `renderableSymbols`.
- Non-goals: renaming or removing existing symbols (stored raw values sync — no renames in this change), full taxonomy pass.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `category-management`: the closed catalog icon set grows to cover pets + housekeeping (+ small domain gap-fillers).

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/Catalog/Models/CatalogIcon.swift`, `IconPickerGrid.swift` (automatic), `L10n` + both `Localizable.strings`.
- `backend/api/openapi.yaml` (`CategoryIcon` + `validIcons`) + backend validation + parity tests.
- `Design/TOKENS.md`. No ctx7 fetch needed (Apple system symbols verified at runtime by `canRender`, pinned to iOS 18 floor).
