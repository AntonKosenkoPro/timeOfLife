## Context

See proposal.md (Why). Current state: `L10n` enum + `en`/`ru` `Localizable.strings` (~239 keys), `LocalizationTests` parity for two bundles, U4 rule "en + ru", XcodeGen `project.yml` resources shipping two `.lproj` dirs to app + `LifioLiveActivities` appex. Constraints: LocalStore chokepoint untouched (strings only), no new deps, Theme-only views, portait iPhone-first, tight surfaces (Recents fixed-height scroll, History pinned header, Insights one-line footnote).

## Goals / Non-Goals

**Goals:**

- Ship `zh-Hans` / `es-419` / `pt-BR` bundles with CI parity and reviewer-auditable LLM reports.
- Keep keys stable (`L10n` cases unchanged; only tests + bundles widen).
- Prove tight-surface rendering per locale before merge (pseudo-locale + real screenshots in `/tmp`, never committed per AGENTS.md no-binaries rule).

**Non-Goals:**

- No screenshot sets, marketing art, preview video, Store-listing copy, demo-data seeding (GH issues).
- No String Catalog migration (stay on `Localizable.strings`; catalog switch is a separate change).
- No backend email-template localization (verify OTP template language separately).

## Decisions

### 1. Stay on `Localizable.strings`, don't migrate to `.xcstrings`

Why: 239 keys + `L10n` + parity tests already work; `.xcstrings` migration touches every screen + export tooling and doubles review surface. Alternatives considered: Xcode 15+ String Catalogs (better pluralization/variation UI per SwiftUI `/websites/developer_apple_swiftui` "localized strings String Catalogs") — deferred as its own change; this change adds locales in the current format.

### 2. BCP-47 identifiers `zh-Hans`, `es-419`, `pt-BR`

Why: Foundation `/websites/developer_apple_foundation` "Locale language identifier" — identifiers are BCP-47; `zh-Hans` = Simplified mainland, `es-419` = Latin America (Mexico City anchor), `pt-BR` = Brazil (São Paulo anchor). One variant per language avoids `es-ES`/`es-MX` and `pt-PT`/`pt-BR` splits in v1. Alternative (generic `es`/`pt`/`zh`) rejected: Xcode resolves generic fallbacks unpredictably across device regions; explicit identifiers photograph deterministically.

### 3. `LocalizedStringKey` + translator comments stay as-is; no key renames

Why: SwiftUI resolves `Text("key")` via `LocalizedStringKey` with fallback to the literal (per ctx7 SwiftUI docs); renaming keys would churn all call sites + tests for zero behavior gain. Translators get context from the adjudication report's screen/width notes instead of new code comments in v1.

### 4. Three-family LLM adjudication + 1.3× mechanical gate

Why: user constraint is no native-verifier budget; single-family self-review barely catches formality/length drift. Blind back-translation (family B sees candidate only) + adjudicator (family C) + mechanical length/render gate gives an auditable bar the author (en/ru speaker) can verify. Alternative (professional review) deferred to v1.1; alternative (single-pass MT) rejected — uncapped length risk in fixed-height surfaces.

### 5. Parity tests widen, keys frozen

`LocalizationTests`: iterate `L10n.allCases` × five bundles, assert non-empty non-key-echo; add `catalogIcon` accessibility keys per locale. No `L10n` case additions in this change (new strings ride the U4 rule going forward). HIG `/websites/developer_apple_design_human-interface-guidelines` "localization internationalization" constrains layout: no hardcoded widths, Dynamic Type-safe chips, device-locale dates stay automatic.

## Risks / Trade-offs

- [LLM misses cultural tone, e.g. 加班 negativity, tú/usted inconsistency] → Mitigation: adjudication report forces explicit formality declaration per locale; author rejects on inconsistency.
- [CJK glyph height / es-419 string length breaks Recents fixed-height area or pinned header] → Mitigation: pseudo-locale padding run + per-locale rendered screenshots (in `/tmp`) with truncation checklist; 1.3× gate blocks merge.
- [`es-419`/`pt-BR` device fallback surprises (user on `es-ES` device)] → Mitigation: explicit identifiers + QA on `es-ES`-region device shows `es-419` fallback; documented in tasks.
- [Appex bundle misses a locale] → Mitigation: `xcodegen generate` + explicit test asserting appex bundle resolves all five.
- [Scope creep into Store listings/demo data] → Mitigation: GH issues own that work; this change's tasks reference but don't implement them.

## Migration Plan

No migration: additive `.lproj` dirs + test widening. Rollback = revert the three dirs + test diff; no on-disk format change (pre-release, no compat branches). Deploy: land behind normal PR checks (swiftlint, xcodebuild build+test, `openspec validate --all --strict`); bump nothing (no version impact).

## Open Questions

- OTP email template language for new locales: verify current template behavior during implementation; file a follow-up if server-side localization is needed.
- Pluralization pressure points (e.g. "2h 35m tracked" grammar in zh/es/pt): adjudicator flags; if ICU plurals needed, propose a String Catalog follow-up.
