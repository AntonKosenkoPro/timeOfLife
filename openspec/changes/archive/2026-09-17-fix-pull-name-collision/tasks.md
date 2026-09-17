## 1. Pull collision recovery (newer-owns-the-name)

- [x] 1.1 `applyServer(_ category:)`: on same-name/different-id rival, server-newer → `remapCategoryReferences` adopt; else skip + secret-free log. No other behavior change.
- [x] 1.2 `applyServer(_ activity:)`: same rule via `remapActivityReferences` (translate winner tags first — D2); on adopt, rewrite moved entries' outbox payloads (existing push-path pattern). Else skip + log.
- [x] 1.3 Category-id translation helper: server id → local id by id, else by normalized name from the pulled snapshot; unresolvable → `AssociationError.invalidCategory` (existing skip contract). Reused by pull-merge and `adoptServerVersion`.
- [x] 1.4 `applyServer(_ entry:)`: skip + log when the activity is absent locally (was FK crash).
- [x] 1.5 `EntryWireDTO.source`: default absent/null to "manual" (pre-provenance relays omit it; mirrors the relay's own back-compat) instead of failing the pull on `keyNotFound`.

## 2. Regression coverage (SyncControllerTests fakes + temp store)

- [x] 2.1 Reported shape end-to-end: local seed + create row vs older same-name server category → first `activate()` completes idle with NO error; server identity adopted (joins moved, create row cleared) without any push round-trip.
- [x] 2.2 Local-newer seed vs server category + server activity tagging it + server entry: cycle completes; local kept; activity merged with translated (local) tag; drain's push-409 `category_exists` heals identity (full convergence, outbox empty, idle).
- [x] 2.3 Activity collision both directions (adopt newer server incl. entry-payload rewrite; skip older server incl. its entries) with no cycle failure.
- [x] 2.4 `RemoteCatalogRepositoryTests`: entry without `source` decodes with "manual" default (provenance-less fixture mirroring the production relay).

## 3. Verification and docs

- [x] 3.1 `swiftlint lint --strict` clean; warning-free build; `xcodebuild test` green (backend untouched).
- [x] 3.2 Simulator E2E on the SE iOS 15.5 sim against local backend with pre-seeded conflicting relay data: sign-in completes to "Last synced", no error row.
- [x] 3.3 Re-check `Requirements/FURPS/Timetracking.md` F5–F8 + `Activity_Catalog_and_Categories.md` R2 for conflicts (expected: none — same LWW protocol, hardened recovery). Update `docs/project-context.md` sync-plane bullet (one line). No OpenAPI changes.
