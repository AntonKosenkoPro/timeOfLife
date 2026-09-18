## Context

See `proposal.md` (Why) for motivation: the "Time of Life" name is taken, so the product ships as **Lifio**. Current state: the user-visible name lives in exactly two functional places — `CFBundleDisplayName` (`ios/TimeOfLife/project.yml` → generated `Info.plist`, with a duplicate literal in `TimeOfLife/Configuration/Info.plist`) and the `app.name` localization key (`en`/`ru.lproj` → `L10n.appName`, rendered by `WelcomeView`). Everything else named "Time of Life" is prose (specs, docs, code comments, backend API title) or a stable machine identifier that must not move. Constraints from `docs/project-context.md`: XcodeGen-managed project (edit `project.yml`, run `xcodegen generate`, never hand-edit `.pbxproj`); every user-facing string in both locales + `L10n` (U4); OpenAPI is the authoritative API contract (S10, docs-only change here); pre-release — no on-disk migration.

## Goals / Non-Goals

**Goals:**
- After this change, every user-visible surface says "Lifio" and `rg -i "time of life"` is clean outside `openspec/changes/archive/` (history) and the stable-identifier values named below.
- Zero functional change: same bundle, same container, same database, same backend, same tests green.

**Non-Goals:**
- No bundle-ID / App Group / Keychain / database-file / backend-domain rename (proposal Non-goals). No icon-artwork redesign. No App Store Connect provisioning or signing changes.

## Decisions

### D1: User-facing rename only — internal module stays `TimeOfLife`
Change `CFBundleDisplayName` and `app.name`; keep the Xcode target/scheme/module, source directories, and `@testable import TimeOfLife` untouched.
- *Rationale:* renaming the module means moving dozens of files, touching every import, the SPM product surface, and CI scheme references — pure churn with regression risk, invisible to users. Apple distinguishes display name from bundle/executable freely.
- *Alternative considered:* full rename to `Lifio` module/target — rejected (churn, no user benefit).

### D2: `project.yml` is the source of truth for the display name
Edit `CFBundleDisplayName` in `project.yml` and mirror the literal in `TimeOfLife/Configuration/Info.plist` (the checked-in plist carries the same literal; XcodeGen `info.properties` wins at generation time, but both must agree so a stale generate never resurrects the old name). Then run `xcodegen generate` once.
- *Rationale:* per project-context, hand-editing the `.pbxproj` is forbidden; the plist literal is defense-in-depth.
- *Alternative considered:* editing only the plist — rejected (violates XcodeGen-managed rule).

### D3: Brand name invariant across locales
`app.name` becomes `"Lifio"` in **both** `en.lproj` and `ru.lproj`, including the file header comments.
- *Rationale:* product brand names don't translate (U4 still requires both files updated, which this does).
- *Alternative considered:* transliterating into Cyrillic — rejected (brand dilution, store-listing mismatch).

### D4: Machine identifiers frozen
`PRODUCT_BUNDLE_IDENTIFIER`, App Group entitlement + `LocalStore.appGroupID`, Keychain service/keys, `databaseFileName`, GCD queue labels, backend DB/Docker/image names, production API domain, and `APPLE_CLIENT_ID` examples stay byte-identical.
- *Rationale:* all are keyed storage or addressing; changing any of them orphans dev data, Keychain sessions, or relay addressing for zero user benefit. Pre-release policy allows the rename without migration precisely because nothing keyed moves.
- *Alternative considered:* renaming bundle/group to `lifio` — rejected (breaks Keychain + App Group continuity; can be revisited as its own change if ever wanted).

### D5: Backend change is docs-only
Update `backend/api/openapi.yaml` `title`/description product reference; no endpoint, schema, or domain change. Backend code comments mentioning the product name are updated opportunistically in the same files touched by nothing else (no behavior diff).
- *Rationale:* S10 keeps OpenAPI as the authoritative contract — its human-readable title should match the product, but the contract itself is untouched.

### D6: Prose sweep with a bounded allowlist
Replace remaining "Time of Life" product prose in specs deltas (this change), `README.md`, `AGENTS.md`, `docs/project-context.md`, `openspec/config.yaml` inline context, `Design/*.md` + `Design/SCREENS/*`, `WelcomeView`/`TimeOfLifeApp`/xcconfig comments, and localization file headers. Explicitly excluded: `openspec/changes/archive/**` (immutable history) and stable-identifier string values (D4).
- *Rationale:* a bounded grep-verifiable sweep prevents the old name lingering in user-facing or maintainer-facing prose without rewriting history.

## Risks / Trade-offs

- [Risk] A missed literal resurrects "Time of Life" somewhere visible → Mitigation: tasks end with a repo-wide `rg -i "time of life"` check whose only allowed hits are `archive/` history and D4 identifier values; `rg "TimeOfLife"` (module name) hits remain expected.
- [Risk] `xcodegen generate` produces unrelated project diff → Mitigation: single generate, inspect diff is limited to display-name lines; never hand-edit `.pbxproj`.
- [Risk] `LocalizationTests` (key-count based) could miss a value typo like `"Lifoo"` → Mitigation: tasks add an explicit value assertion step (grep both strings files for `"app.name" = "Lifio"`).
- [Risk] Translators/reviewers expect a Russian brand variant → Mitigation: spec scenario pins the invariant ("still reads Lifio"), reviewed in this change.
- [Risk] App Store Connect name "Lifio" availability can't be verified from the repo → Mitigation: manual human check called out in tasks; implementation proceeds regardless (name is uniform to re-change if needed).

## Migration Plan

No migration. Pre-release: no shipped data, nothing keyed moves (D4). Deploy is a normal merge: iOS rebuild + backend docs-only change. Rollback is revert-the-commit; no state to unwind.

## Open Questions

- None blocking. Deferred (answerable later without changing specs, approach, or tasks): whether to ever rename the bundle ID / App Group / API domain to `lifio` for vanity (needs its own change with a migration story once external installs exist); whether the icon artwork needs a Lifio wordmark (artwork currently carries no product text — verify during implementation, follow up separately if it does).
