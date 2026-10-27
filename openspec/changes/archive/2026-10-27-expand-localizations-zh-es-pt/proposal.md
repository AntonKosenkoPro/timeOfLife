## Why

Lifio's launch markets are the USA plus China with a LatAm hedge, but the app ships only `en` + `ru` (~239 `L10n` keys, parity-enforced by `LocalizationTests`). English-only screenshots and copy bounce non-English buyers in China, Mexico, and Brazil; adding locales after screenshots are shot multiplies rework. Localize the strings now, shoot screenshots later.

## What Changes

- Add three iOS localizations: `zh-Hans` (Simplified, mainland China anchor), `es-419` (Latin America, Mexico City anchor), `pt-BR` (Brazil, São Paulo anchor). Existing `en` + `ru` unchanged.
- Translate all ~239 `L10n` keys per locale with **culture adaptation** (city-man persona per market: same timeline shape, locally rewritten entry texts, notes, starter-category names) — not 1:1 dictionary translation.
- Extend `LocalizationTests` parity to all five bundles: every `L10n` case must resolve in every locale or CI fails.
- Establish the LLM-only review protocol (translator family A → back-translator family B blind → reviewer family C adjudication + risk list), with a mechanical length gate (any key >1.3× EN chars or rendered truncation = must-fix, no LLM override).
- Expand the U4 locale rule (AGENTS.md / project-context.md) from "en + ru" to five locales for all new strings.
- Wire new `.lproj` dirs into `project.yml` resources (via `xcodegen generate`) so they ship in app + `LifioLiveActivities` appex.

## Capabilities

### New Capabilities

- `localization`: five-locale string contract (locale set, culture-adapted content decks, LLM review + length gates, CI parity, U4 expansion).

### Modified Capabilities

(none — no spec-level behavior changes; existing capabilities keep their requirements, only their string coverage widens.)

## Impact

- Affected: `ios/TimeOfLife/TimeOfLife/Localization/` (3 new `.lproj` dirs), `String+Localized.swift` (tests only, keys unchanged), `LocalizationTests`, `project.yml` resources, `docs/project-context.md` + `AGENTS.md` U4 wording, `Design/` locale notes.
- No backend, API, sync, or on-disk format changes. No new deps. No behavior changes.
- Non-goals (deferred to GH issues, NOT this change): App Store screenshot sets (10 sets: 5 locales × 2 sizes), marketing banners/press kit, App Preview video, Store-listing copy (subtitle/keywords/description), 21-day demo-data seeding + screenshot pipeline, native-speaker spot-check v1.1.

## Research bundle (ctx7, pin: iOS 18 SDK via Xcode 16+)

- SwiftUI `/websites/developer_apple_swiftui` — "localized strings String Catalogs" (+ "preparing views for localization": `LocalizedStringKey`, translator comments).
- HIG `/websites/developer_apple_design_human-interface-guidelines` — "localization internationalization" + "Localization" (RTL context, inclusive writing; CJK/LatAm layout risks).
- Foundation `/websites/developer_apple_foundation` — "Locale language identifier" (BCP-47 identifiers `zh-Hans`, `es-419`, `pt-BR`).
- Best-practice external query: waived with reason — multi-LLM translation review is a repo-internal process (strings + adjudication reports, no third-party SDK/service); evidence: no new deps in Impact.
