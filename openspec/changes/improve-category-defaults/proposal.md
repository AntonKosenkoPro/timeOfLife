## Why

The defaults omit Food, while the icon picker offers 14 sports choices but only two food/drink symbols and one child-specific symbol. Issue [#243](https://github.com/AntonKosenkoPro/timeOfLife/issues/243) calls for better everyday coverage without growing an excessive catalog.

## What Changes

- Append Food (`fork.knife`) as the eighth starter category, localized at first seeding in all five supported languages. Apply only to newly initialized datasets; never backfill already-seeded account files.
- Add exactly three icons: `carrot`, `stroller`, and `teddybear`. Food/drink choices become exactly three (`fork.knife`, `cup.and.saucer`, `carrot`); child-specific choices become exactly three (`figure.and.child.holdinghands`, `stroller`, `teddybear`). Counts include existing symbols. Generic `person.2` remains unchanged.
- Verify all three new icons on iOS 18 as an acceptance check. If any fails, stop for an explicit decision; do not silently omit, substitute, or expand the agreed set.
- Hide exactly eight sports icons from new selection: `figure.strengthtraining`, `figure.soccer`, `figure.basketball`, `figure.tennis`, `figure.gymnastics`, `figure.mindandbody`, `figure.core.training`, and `bicycle`. Keep `figure.walk`, `figure.run`, `dumbbell`, `figure.yoga`, `figure.cycling`, and `figure.swimming` visible where renderable; `figure.cycling` covers cycling without a second bicycle choice. Preserve every existing accepted raw value, rendering, editing, and sync behavior; retain a hidden selected icon when editing its category.
- Add Food and new icon accessibility names in `en`, `ru`, `zh-Hans`, `es-419`, and `pt-BR`. Update catalog mirrors and seed-count-dependent tests/fixtures together.

Non-goals: backfill/reseed or rename existing data; remove accepted icons; migrate storage; add default child categories; redesign/group/search the picker; change category CRUD, undo, authentication, or sync algorithms.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `category-management`: eight first-seeding starters, exactly three new food/children icons, and a curated picker distinct from the full accepted icon catalog.

## Impact

- iOS: `LocalStore` seeding, `String.starterCategoryNames`/`L10n`, `CatalogIcon`, category editor options, five string bundles, seeding/lifecycle/catalog/localization/editor tests, and count-sensitive UI-test/capture fixtures.
- API: additive `CategoryIcon` enum entries in authoritative `backend/api/openapi.yaml`, matching Go `validIcons`, iOS catalog, and contract/handler tests. No endpoint, payload-shape, or database migration changes. Deploy backend acceptance before exposing new choices in the app.
- Documentation at implementation: `Design/TOKENS.md`, `Design/COMPONENTS.md`, category screen docs, relevant FURPS rows, and `docs/project-context.md`. Baselines remain untouched until approved archive; the existing localization contract already covers all five languages.
- Research: Context7 `/websites/developer_apple_design_human-interface-guidelines`, queries “Choosing familiar recognizable SF Symbols with clear meanings and consistent visual weight for category icon selection” and “SF Symbols symbol availability on older operating systems and verifying symbols in the SF Symbols app”; fetched for this proposal. Apple API supplement: [UIImage.init(systemName:)](https://developer.apple.com/documentation/uikit/uiimage/init(systemname:)), fetched directly from Apple's documentation JSON; missing symbols return nil. Target pin: iOS 18 SDK via Xcode 16+, with actual iOS 18 runtime verification still an implementation gate. No separate external-library/setup research is applicable: no dependency or service integration changes; existing repository catalog/validation mechanisms are reused. Details and acceptance gates are in `design.md`.
