## Context

See `proposal.md` for motivation (issue #38: pet + housekeeping life domains missing from the picker) and `specs/category-management/spec.md` for the behavioral delta. This is a closed-set expansion only: 16 additive SF Symbols, no renames, no removals (stored raw values sync across devices — renaming would orphan synchronized values).

No ctx7 fetch was needed (proposal-recorded decision): Apple system-symbol availability is verified at runtime by `CatalogIcon.canRender` (`UIImage(systemName:) != nil`), pinned to the iOS 18 floor, not by external docs.

## Final symbol table (runtime-verified on iOS 18 simulator, 2026-09-27)

Every candidate below passed the `canRender` check in a throwaway `IconCandidateProbeTests` run (same `UIImage(systemName:)` logic as production; probe file deleted afterwards, never shipped). Dropped candidates are listed after the table.

### Pets (5)

| SF Symbol | Swift case | EN VoiceOver | RU VoiceOver | Usage |
|---|---|---|---|---|
| `pawprint` | `pawprint` | Paw print | След лапы | Pets / animals |
| `dog` | `dog` | Dog | Собака | Pets / dog |
| `cat` | `cat` | Cat | Кошка | Pets / cat |
| `fish` | `fish` | Fish | Рыба | Pets / fish |
| `bird` | `bird` | Bird | Птица | Pets / bird |

### Home + housekeeping (7)

| SF Symbol | Swift case | EN VoiceOver | RU VoiceOver | Usage |
|---|---|---|---|---|
| `washer` | `washer` | Washer | Стиральная машина | Home / laundry |
| `dryer` | `dryer` | Dryer | Сушильная машина | Home / laundry |
| `dishwasher` | `dishwasher` | Dishwasher | Посудомоечная машина | Home / kitchen |
| `refrigerator` | `refrigerator` | Refrigerator | Холодильник | Home / kitchen |
| `sofa` | `sofa` | Sofa | Диван | Home / living room |
| `shower` | `shower` | Shower | Душ | Home / bathroom |
| `lamp.table` | `lampTable` | Table lamp | Настольная лампа | Home / lighting |

### People + family (2)

| SF Symbol | Swift case | EN VoiceOver | RU VoiceOver | Usage |
|---|---|---|---|---|
| `person.2` | `person2` | People | Люди | Family / people |
| `figure.and.child.holdinghands` | `figureAndChildHoldinghands` | Family | Семья | Family / parenting |

### Body + rest (2)

| SF Symbol | Swift case | EN VoiceOver | RU VoiceOver | Usage |
|---|---|---|---|---|
| `stethoscope` | `stethoscope` | Stethoscope | Стетоскоп | Body / health |
| `pill` | `pill` | Pill | Таблетка | Body / medication |

### Dropped candidates (failed `canRender`, never force-included)

| Candidate | Reason |
|---|---|
| `turtle` | `UIImage(systemName: "turtle")` returns nil on the iOS 18 runtime — dropped |
| `lamp` (bare) | No such symbol on the iOS 18 runtime (only qualified variants render) — replaced by `lamp.table` |
| `person.3` | Renders, but cut to hold the set at 16 (a count variant of `person.2`, not a new domain) |
| `lamp.floor`, `lamp.ceiling`, `oven`, `cooktop`, `microwave` | All render; held as verified spares for a future expansion, not included now |

## Parity plan (lockstep, enforced by tests)

All six mirrors change in the same PR; order is irrelevant, completeness is not:

1. `ios/TimeOfLife/TimeOfLife/Features/Catalog/Models/CatalogIcon.swift` — 16 new cases (raw values above; `person2`, `lampTable`, `figureAndChildHoldinghands` follow the existing camelCase convention, e.g. `carFill`, `bedDouble`).
2. `backend/api/openapi.yaml` — 16 new `CategoryIcon` enum entries (authoritative contract; existing order untouched, new entries grouped by domain before `tag`).
3. `backend/internal/handlers/catalog_validators.go` — 16 new `validIcons` entries.
4. `Design/TOKENS.md` — 16 new catalog-icon table rows.
5. `en.lproj` + `ru.lproj` `Localizable.strings` — 16 new `catalogIcon.<symbol>` keys each (dynamic-key lookup via `L10n.catalogIconName`, outside the `L10n` enum — no enum change).
6. `ios/TimeOfLife/TimeOfLifeTests/CatalogIconTests.swift` — 16 new `canonicalSymbols` entries (iOS↔OpenAPI parity pin).

Enforcement: backend `TestSpec_CategoryIconEnumMatchesGo` (OpenAPI↔Go), iOS `CatalogIconTests.matchesCanonicalSet` (iOS↔canonical) + `LocalizationTests.catalogIconNamesResolve` (every case resolves EN+RU, iterates `allCases` — automatic). `IconPickerGrid` needs no change (reads `renderableSymbols`).

## Alternatives considered

- Force-include `turtle` via a custom fallback image. Rejected: the closed set is SF Symbols only; non-rendering symbols are dropped by rule.
- Use bare `lamp`. Rejected: does not render; `lamp.table` is the verified equivalent.
- Include all verified spares (`oven`, `cooktop`, `microwave`, `person.3`, alternate lamps) now. Rejected: proposal caps the change at ~14–16; spares are recorded above for later.
