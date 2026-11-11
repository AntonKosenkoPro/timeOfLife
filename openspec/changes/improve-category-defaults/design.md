## Context

See `proposal.md` for motivation and the category-management delta for behavior. `LocalStore.starterCategoryIcons` and `String.starterCategoryNames` currently zip seven icons/names, protected by the durable `category_starters_seeded` marker. `AppContainer.prepareAccountStore` seeds behind the account gate. The relay does not provision starters.

`CatalogIcon.allSymbols`, authoritative OpenAPI `CategoryIcon`, Go `validIcons`, and `Design/TOKENS.md` mirror 63 accepted raw strings. The category editor currently sources every renderable symbol and retains a selected supported-but-unrenderable value. Both databases store icon strings without an enum constraint. This calls for catalog/editor policy, not schema migration.

## Goals / Non-Goals

**Goals:** separate discoverability from validity; preserve user-owned records; make all catalog mirrors, localization, and fixture assumptions testable in one change.

**Non-goals:** no hidden/deprecated flag on category records or wire payloads; no persistence-version branches, automatic data rewriting, picker sections, new dependency, or new category management surface.

## Decisions

### 1. Keep the existing once-only seed transaction

Append `fork.knife` and the matching Food name to the two eight-element seed lists. Add `category.seed.food` through `L10n` in all five locales. Preserve the existing marker gate, same-name skip behavior, outbox transaction, per-account isolation, and erase semantics. An already-seeded seven-category file returns without writes, even if users have deleted or renamed starters.

Alternative rejected: a seed-version migration/backfill would introduce unwanted categories into user-managed datasets. No new marker or storage format is needed. Use a pre-seeded seven-category test fixture with the existing marker to prove the boundary, not merely a second call using the new eight-name list. This is a local seeding rule, not a sync filter: an existing file can still receive a Food category created normally or seeded in a new dataset on another device.

### 2. Add a picker policy, not a smaller validity enum

Keep all existing `CatalogIcon` cases and localized names. Introduce a separately testable curated picker source: renderable supported symbols minus the hidden set. Retain existing declaration order for unchanged choices; place successful new food/child symbols near the related existing symbols without adding visible groups.

| Sports selectable for new categories | Hidden only from new selection |
|---|---|
| `figure.walk`, `figure.run`, `dumbbell`, `figure.yoga`, `figure.cycling`, `figure.swimming` | `figure.strengthtraining`, `figure.soccer`, `figure.basketball`, `figure.tennis`, `figure.gymnastics`, `figure.mindandbody`, `figure.core.training`, `bicycle` |

Generalize the editor's existing selected-value passthrough: if a supported selected symbol is absent from curated options, include it once. Saving a name-only edit must preserve it. A hidden symbol uses its original glyph if renderable; only genuine OS unavailability uses the existing `tag` visual fallback. Selecting a different icon is the only icon-changing action. All category editor entry points share this policy.

Alternative rejected: deleting enum/validator members would break relay writes and could coerce existing values to `tag` on edit. Keeping every sports choice visible would not satisfy the agreed reduction.

### 3. Freeze a bounded, runtime-verified expansion before catalog edits

| Domain | Existing choices | New candidates |
|---|---|---|
| Food/drink | `fork.knife`, `cup.and.saucer` | `carrot` |
| Children | `figure.and.child.holdinghands` | `stroller`, `teddybear` |

Generic `person.2` remains a people icon, outside the child-specific count. Run the existing `CatalogIcon.canRender` check on an actual iOS 18 simulator for each new candidate before admitting it. Target three choices per domain; a failed candidate is omitted with evidence, provided each domain retains two or three choices. If both child candidates fail, stop for a replacement decision rather than shipping only one or inventing another symbol. No candidate has been runtime-verified in this proposal.

The accepted catalog becomes 63 plus the admitted subset (at most 66); ordinary picker choices become that set minus eight hidden sports values, additionally filtered by OS renderability. Keep all mirrors and tests pinned to the same final exact subset. Preserve dynamic `catalogIcon.<rawValue>` VoiceOver keys for every old value and add each admitted symbol in five locales. Do not add separate `L10n` enum cases for dynamic icon keys; Food's seed key does need one and localization snapshot coverage.

### 4. Preserve capture fixtures without expanding the screenshot project

Shipping seeds and capture-only fixtures are separate. `ScreenshotFixture.categories` currently uses seven starter identities plus its existing custom Food identity (`shot-cat-food`); keep that identity and the eight-category/55-entry capture contract. Update any shared count/name assumptions intentionally rather than blindly adding a ninth Food row. Update the seven-token `seedZhFitCategories` UI-testing list with Food if it follows shipping seeds. No panel rendering, screenshot regeneration, owner-approval changes, or binary commits belong to this change.

### 5. Research and requirements basis

Proposal-time research: three Context7 calls (resolve HIG once, then two single-topic docs queries), plus the official Apple API supplement below. Re-confirm before implementation.

- Topic/HIG: `/websites/developer_apple_design_human-interface-guidelines`, query “Choosing familiar recognizable SF Symbols with clear meanings and consistent visual weight for category icon selection” → simple familiar meanings and consistent font-aligned weights/scales. [SF Symbols HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols).
- Availability: same ID, query “SF Symbols symbol availability on older operating systems and verifying symbols in the SF Symbols app” → individual symbols vary by OS; the current host OS is not proof of iOS 18 support.
- Apple API supplement, fetched directly: [UIImage.init(systemName:)](https://developer.apple.com/documentation/uikit/uiimage/init(systemname:)); official JSON `https://developer.apple.com/tutorials/data/documentation/uikit/uiimage/init(systemname:).json` confirms a failable initializer returning nil when no suitable symbol exists. API available since iOS 13; deployment/test pin remains **iOS 18 SDK via Xcode 16+**, with runtime evidence required on iOS 18. The existing wrapper is reused; no new framework API is introduced, so no additional API-specific ctx7 lookup is required for this proposal.
- External-library/setup item: N/A; only existing repository enum/picker/seed mechanisms change, with no dependency, cloud setup, GRDB schema/API, or service integration changes.
- Constraints re-checked: category FURPS F2/F6/F12/U1/U9/R1–R3 and Common U1/U3/U4/U5/S3/S5/S10. Update F6 and its resolved seed decision from seven/EN+RU to eight/five locales during implementation; no category-delete/undo/conflict changes.

## Risks / Trade-offs

- [Candidate missing on iOS 18] → gate admission before all mirrors change; record omissions and enforce the two-to-three bounds without unapproved substitutes.
- [Hidden icon lost on editor initialization/save] → keep validity separate, test name-only saves for all hidden values and explicit replacement, including after reload/sync.
- [Client offers symbols before relay accepts them] → deploy additive backend allowlist first; no removal during normal rollback.
- [Seed-count changes break first paint or capture fixtures] → lifecycle, localized seed, existing-marker, UI-test fixture, and capture fixture regressions; no duplicate Food.
- [Old EN+RU-only wording gets repeated] → update affected category spec/design wording to five locales; retain the existing localization baseline unchanged.

## Migration Plan

1. Human reviews this proposal PR; all implementation tasks remain unchecked until apply.
2. On this same branch, confirm research/runtime availability, implement additive catalog mirrors and the iOS seed/picker changes, then pass the listed tests and manual checks.
3. Deploy backend acceptance before distributing an app exposing new symbols. No data/schema migration or backfill runs.
4. If rolling back the app, keep the additive backend allowlist deployed: newly persisted symbols remain valid. Do not blindly revert backend validation after use; retain additive acceptance in a rollback build if necessary. A reverted app may use its existing unknown-symbol fallback without a migration.
5. Human approval, implementation review, and normal archive follow later; this proposal is not release acceptance.
