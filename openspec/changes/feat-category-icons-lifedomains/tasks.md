## 1. Runtime verification (done first, throwaway)

- [x] 1.1 Probe every candidate with the production `UIImage(systemName:)` logic on the iOS 18 simulator via a temporary test target file; drop non-rendering symbols (`turtle`, bare `lamp`), never force-include; delete the probe file afterwards (do not ship the check).
- [x] 1.2 Finalize the 16-symbol list in `design.md` grouped by domain (Pets 5 / Home+Housekeeping 7 / People+Family 2 / Body+Rest 2).

## 2. Change artifacts

- [x] 2.1 Write `specs/category-management/spec.md` (MODIFIED delta: expanded closed set + scenarios).
- [x] 2.2 Write `design.md` (final symbol table + dropped candidates + parity plan).
- [x] 2.3 Run `openspec validate feat-category-icons-lifedomains --strict` and fix every finding.

## 3. Implementation (parity lockstep)

- [x] 3.1 `CatalogIcon.swift`: add the 16 cases (no renames/removals of existing cases).
- [x] 3.2 `backend/api/openapi.yaml`: add the 16 `CategoryIcon` enum entries.
- [x] 3.3 `backend/internal/handlers/catalog_validators.go`: add the 16 `validIcons` entries.
- [x] 3.4 `Design/TOKENS.md`: add the 16 catalog-icon rows.
- [x] 3.5 `en.lproj` + `ru.lproj` `Localizable.strings`: add the 16 `catalogIcon.*` keys each.
- [x] 3.6 `TimeOfLifeTests/CatalogIconTests.swift`: add the 16 `canonicalSymbols` entries.
- [x] 3.7 Re-check `Requirements/FURPS/Activity_Catalog_and_Categories.md` rows F2/U1 (closed icon set still validated; no requirement text change needed).

## 4. Verification

- [ ] 4.1 Backend: `gofmt -l .` empty, `go vet ./...`, `go test ./...` green (incl. `TestSpec_CategoryIconEnumMatchesGo`).
- [ ] 4.2 iOS: `swiftlint lint --strict` clean, warning-as-error Simulator build green, full test suite green on a booted simulator (incl. `CatalogIconTests`, `LocalizationTests`).
- [ ] 4.3 Push branch `feat/38-category-icons-lifedomains` and open a PR targeting `main` ("Fixes #38", final symbol table + verification evidence). DO NOT merge.
