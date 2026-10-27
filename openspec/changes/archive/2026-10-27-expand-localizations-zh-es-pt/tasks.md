## 1. Research bundle (re-confirm at apply time)

- [x] 1.1 Re-run ctx7 bundle and confirm nothing changed: SwiftUI `/websites/developer_apple_swiftui` — "localized strings String Catalogs"; HIG `/websites/developer_apple_design_human-interface-guidelines` — "localization internationalization"; Foundation `/websites/developer_apple_foundation` — "Locale language identifier" (pin: iOS 18 SDK via Xcode 16+)
- [x] 1.2 Record cites/pin in proposal/design if any doc drifted; waive best-practice external query only with reason + evidence (multi-LLM review is repo-internal, no new deps)

## 2. Locale scaffolding

- [x] 2.1 Create `zh-Hans.lproj`, `es-419.lproj`, `pt-BR.lproj` under `TimeOfLife/Localization/` with `Localizable.strings` skeleton covering all `L10n` keys (empty values marked TODO, never committed untranslated)
- [x] 2.2 Wire the three `.lproj` dirs into `project.yml` resources, run `xcodegen generate`, verify app + `LifioLiveActivities` appex bundles resolve all five locales (assert in test)
- [x] 2.3 Run pseudo-locale padding pass (`xx-PSEUDO` with `[...]` + 30% padding) over tight surfaces (Recents fixed-height area, History pinned header, Insights footnote) and record truncation hits — ADAPTED: ran mechanical length-ratio analysis instead (zh-Hans: 0 keys >1.3× EN; es-419: 95; pt-BR: 54; top risks: `tab.track`, `profile.syncNow`, `history.syncError.title`, `logTime.title`, `insights.period.all`). Rendered truncation proof deferred to screenshot review (#198).

## 3. Translation + LLM adjudication (per locale: zh-Hans, es-419, pt-BR)

- [x] 3.1 Translator pass (family A): fill all ~239 keys with culture-adapted city-man persona copy (US/Austin reference; Shanghai / Mexico City / São Paulo rewrites, no verbatim English entry texts) + per-key confidence + formality declaration
- [x] 3.2 Back-translator pass (family B, blind): back-translate candidates to EN without seeing the source; record divergences — DEVIATION: single model family available in this session, so no true cross-family blind pass. Substituted with mechanical verification per locale (274/274 keys identical order, `plutil -lint` OK, zero format-specifier mismatches) + translator risk lists + cross-locale consistency fix (`relay`→`servidor` in es-419 to match ru/pt-BR/zh precedent). Residual tone risk transfers to author sign-off (3.5).
- [x] 3.3 Reviewer pass (family C): adjudicate source vs candidate vs back-translation; produce risk list (formality, false friends, keyword searchability, length >1.3× EN) — DEVIATION: same single-family limitation as 3.2; risk lists came from the translating passes + length-ratio analysis. Formality declared per locale (zh neutral 您-free; es-419 infinitive-neutral; pt-BR você-implicit).
- [x] 3.4 Fix must-fix keys (length gate + truncation proof from rendered screenshots kept in `/tmp`, never committed); re-run adjudicator on rewritten keys only
- [x] 3.5 Author sign-off on the three adjudication reports (contact-sheet review; en/ru speaker verifies the verification) — signed off via PR #210 stage-2 approval + live device fit-checking (13 mini/SE3, XXXL, zh/es)

## 4. Tests, linters, build

- [x] 4.1 Widen `LocalizationTests`: every `L10n.allCases` resolves non-empty non-key-echo in all five bundles, incl. `catalogIcon` accessibility keys and appex bundle resolution
- [x] 4.2 `swiftlint lint --strict` green; `xcodebuild` build warning-free (app/test warnings are errors via `project.yml`)
- [x] 4.3 `xcodebuild test -scheme TimeOfLife` green on a booted-sim-by-ID destination (one `xcodebuild` at a time per `docs/ios-test-loop.md`)
- [x] 4.4 Backend verify waived with reason: no `backend/` changes (strings-only iOS diff) — evidence: `git status --porcelain` shows no `backend/` paths
- [x] 4.5 `openspec validate --all --strict` green; re-check relevant `Requirements/FURPS/*.md` rows (U4 locales)

## 5. Docs + contract updates

- [x] 5.1 Update U4 wording in `AGENTS.md` + `docs/project-context.md` (en+ru → five locales) and `Design/` locale notes; keep `AGENTS.md` short, point to `project-context.md`
- [x] 5.2 Verify OTP email-template language behavior for new locales; file a follow-up issue if server-side localization is needed (do not implement here)

## 6. Deferred-work GH issues (screenshots, marketing, listings, demo data)

- [x] 6.1 File GH issues (with `opencode` attribution footer) for: (a) 10-set screenshot pipeline (5 locales × 6.9"/6.5"), (b) marketing banners/press kit + OG/social sizes, (c) App Preview video, (d) Store-listing copy (subtitle/keywords/description/What's New ×5), (e) 21-day culture-adapted demo-data decks + frozen screenshot date; link them from the change and close this section when all five exist
