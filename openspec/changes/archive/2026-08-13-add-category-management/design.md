## Context

See `proposal.md` for motivation and `specs/category-management/spec.md` for the behavioral contract.

The local-first foundation already stores `categories` and `activity_categories`, exposes basic category mutations through `LocalStore`, includes complete category IDs in Activity outbox payloads, and has backend category CRUD. The shared Activity editor already renders a multi-select `TagSelector`. Profile displays Activities and Categories rows, but those rows are inert, there is no category-management/editor UI, and no starter seeding or client-side category validator exists.

The implementation must preserve `local-first-sync-architecture` decisions D1-D6: the App Group GRDB database is authoritative, `LocalStore` is the only mutation chokepoint, state and outbox writes are transactional, deletion uses the durable wall-clock undo buffer, first sync is pull-first, and `SyncController` remains optional and session-gated. The baseline `app-shell` keeps category management in Profile, while `timer-capture-experience` keeps Categories optional and absent from Track search and suggestions.

The existing relay contract has category CRUD and carries Activity associations as `category_ids` in writes and embedded `categories` in reads. Several implementation defects currently prevent that contract from working end to end: the iOS Activity decoder expects `category_ids` in responses, client resource IDs are UUID v4 while the API requires UUID v7, category icon sets differ between code and design, Activity pull precedes Category pull despite local foreign keys, and backend Activity fields and join replacement do not share one transaction. These are addressed here because they directly gate category assignment and synchronization.

## Goals / Non-Goals

**Goals:**

- Complete the category feature by building on the existing local schema, Activity editor, relay endpoints, and design components rather than introducing a parallel repository or storage path.
- Make starter creation, CRUD, association replacement, and category deletion atomic at their defined mutation boundaries.
- Keep category behavior deterministic across offline use, relaunch, undo, and optional cross-device synchronization.
- Reconcile the icon and Activity-association wire contracts across iOS, OpenAPI, and Go.
- Reuse the durable undo architecture for category deletion without claiming app-wide completion for other deletion surfaces.

**Non-Goals:**

- Introduce a new endpoint for Activity-category joins; associations remain part of the Activity resource.
- Add category colors, hierarchy, custom symbols, ordering, merge UI, or analytics.
- Add create-mode Activity management or a Manage Activities screen except where the existing edit-mode Activity editor must support category assignment.
- Add server-side trash or deletion tombstones. Category pull remains a full authoritative snapshot because the current API has no category delta cursor.
- Preserve pre-release databases or accept obsolete icon values; the repository's pre-release policy permits an in-place schema reset.

## Decisions

### D1 - One validated category domain model at every mutation boundary

**Choice:** Add `CategoryName` validation/normalization matching `ActivityName`, a raw-string `CatalogIcon` type with a closed allowed set and `tag` default, and a `CategoryDraft`. `LocalStore` category create/update methods accept validated domain input and return typed outcomes for success, duplicate normalized name, invalid input, stale update, and persistence failure. Add a local unique index on `lower(name)` after trimming names before writes, so the database remains the final race guard.

The OpenAPI `Category.icon` enum is the machine-readable canonical icon list. The Swift `CatalogIcon` cases and Go validator mirror it, while `Design/TOKENS.md` documents the same set. Contract/unit tests compare each implementation against the documented set. The icon picker hides catalog symbols unavailable on the running OS; a valid synchronized symbol that cannot render on that OS is displayed as `tag` without changing the stored value.

**Rationale:** Validation only in a ViewModel can be bypassed by seeding, sync conflict handling, intents, or future clients. A closed icon type prevents arbitrary SF Symbol strings and removes the current drift between iOS, Go, and design.

**Alternatives considered:**

- Keep `Category.icon` as an unconstrained `String` and validate only in the editor. Rejected because non-UI mutations could persist values the relay rejects.
- Add a separate icon table. Rejected because the icon catalog is static application metadata, not user data.
- Rely only on pre-save duplicate lookup. Rejected because concurrent local operations still need a database uniqueness guard.

### D2 - Seed once through an atomic LocalStore initializer

**Choice:** Add a small local metadata table with a `category_starters_seeded` marker. During app data initialization, the composition root supplies the seven localized names and fixed icons to `LocalStore.seedStarterCategoriesIfNeeded`. One database transaction checks the marker, inserts all seven ordinary Category rows, creates their category-create outbox rows, and writes the marker. A failed transaction writes none of them; a successful transaction is never replayed, even if every seed is later deleted. Clearing all local data removes the marker, so the next new local dataset receives a new starter set.

Seed names are materialized in the active supported language at creation. They are not localization keys stored in Category records and do not auto-rename after locale changes.

**Rationale:** The marker, records, and outbox rows need one commit boundary to guarantee exactly-once local behavior across crashes. Passing localized values into the store keeps localization out of the persistence layer while preserving `LocalStore` as the mutation chokepoint.

**Alternatives considered:**

- Seed whenever the category table is empty. Rejected because deleting all categories would unexpectedly recreate them.
- Store localization keys and resolve names at render time. Rejected because seeds must become ordinary editable/synchronizable records.
- Seed directly from a ViewModel. Rejected because multiple entry points could race and it would bypass the mutation chokepoint.

### D3 - Use client UUID v7 for all relay resource identities

**Choice:** Introduce one dependency-injectable client record-ID generator that emits lowercase UUID v7 strings. Use it for new Categories and replace existing UUID v4 generation for Activities and Entries. Outbox and undo-buffer row IDs remain local implementation identities and do not need the relay's UUID v7 contract.

**Rationale:** Category synchronization cannot be considered functional while related Activity or Entry requests are rejected by the authoritative OpenAPI ID validator. A shared generator also makes deterministic tests possible.

**Alternatives considered:**

- Relax the backend to accept UUID v4. Rejected because UUID v7 is an explicit API invariant and is used for time-ordered client identities.
- Fix Category IDs only. Rejected because assigning a valid Category to an invalid Activity ID would still fail as one Activity write.

### D4 - Profile presents a dedicated management destination and shared editor sheet

**Choice:** Make the existing Profile Categories row a navigation control inside Profile's navigation container. `ManageCategoriesViewModel` reads the local catalog, owns list/editor/delete presentation state, and refreshes after mutations. `ManageCategoriesView` renders the alphabetized list, empty state, add control, category rows, conflict banner, and category-scoped undo affordance. `CategoryEditorViewModel` owns a `CategoryDraft` for create/edit modes; `CategoryEditorView` is a sheet with name input, catalog icon grid, field errors, Cancel, and a keyboard-safe pinned Save action.

The existing Activity editor continues to use `TagSelector` for zero-or-more assignments; its chip visuals follow D9. It receives category updates after a category edit and keeps its selection draft until Activity Save. Category creation remains owned by Profile for this change; no nested Category editor is added to Track refinement.

All views use `Theme` semantic colors, EN/RU `L10n` keys, native SwiftUI controls, Dynamic Type, VoiceOver labels, and the stable identifiers defined in the design documents.

**Rationale:** This follows app-shell Profile ownership and existing decisions D13, D21, D22, D24, and D30 while avoiding another navigation architecture or duplicate category editor.

**Alternatives considered:**

- Route Categories through a future Manage Activities screen. Rejected because Profile already exposes a dedicated Categories row and Manage Activities is not part of this change.
- Allow category creation inside Track refinement. Deferred because the requested management location is Profile and nested sheets increase capture-flow complexity.

### D5 - Activity association replacement is one atomic Activity mutation

**Choice:** Continue representing associations as the Activity's ordered `categoryIDs`, not as standalone domain resources. Before replacing joins, `LocalStore` validates that every selected category exists and de-duplicates IDs while preserving selection order. Activity fields, the complete join replacement, and one Activity outbox payload commit in a single transaction. A missing Category rolls back the entire edit and preserves the editor draft.

Apply the same transaction boundary in both backend stores: Activity create/update and `activity_categories` replacement succeed or fail together. Requests continue to use `category_ids`; backend responses continue to embed `categories`. `RemoteCatalogRepository` uses explicit wire DTOs to map embedded Category objects to local `categoryIDs` rather than decoding the local Activity model directly.

**Rationale:** The Activity is the synchronization aggregate for its Category set. A standalone join outbox would add ordering and partial-failure cases, while the existing full-replacement API already expresses the desired behavior.

**Alternatives considered:**

- Add tag/untag endpoints and one outbox row per join. Rejected as unnecessary API and reconciliation complexity.
- Keep the current two backend transactions. Rejected because a failed association replacement can otherwise leave Activity fields partially committed.
- Change the API response to return only `category_ids`. Rejected because embedded Category metadata is already the authoritative OpenAPI response and serves other clients.

### D6 - Pull Categories before Activities and reconcile the full snapshot

**Choice:** A sync pull fetches the complete Category collection first, merges it by `updated_at`, and reconciles relay deletions before fetching Activities and Entries. A clean local Category absent from the relay snapshot is removed locally without creating an outbox row; a Category with a pending create/update outbox operation or active undo record is preserved. Activities are then mapped from embedded Category DTOs and merged after referenced Categories exist.

On `category_exists`, the client fetches and merges the winning Category before atomically remapping local joins and pending Activity payloads, removing the losing local Category without emitting a delete, and clearing the losing create operation. Category DELETE remains the only operation needed at expiry because both local and relay foreign-key cascades remove joins without deleting Activities or Entries.

**Rationale:** Categories currently have no `modified_since` contract or tombstones. A full snapshot is small at the expected catalog size and is the only way to observe cross-device hard deletes with the existing API. Merge order must satisfy local foreign keys.

**Alternatives considered:**

- Pull Activities before Categories and temporarily disable foreign keys. Rejected because it weakens a safety invariant and permits dangling associations.
- Add category tombstones and delta pull now. Rejected as a larger API/data-retention change than this feature needs.
- Infer deletion from an empty or partial response without considering outbox state. Rejected because first-sync would delete unsynchronized local Categories, including starters.

### D7 - Category deletion specializes the existing durable undo buffer

**Choice:** Add a typed category-deletion snapshot containing the Category and its ordered Activity associations. Confirmation invokes one `LocalStore` transaction that writes the undo snapshot and removes the Category/joins with no outbox row. Undo restores the same Category and joins and removes the buffer row in one transaction. Expiry follows local-first D3: foreground reconciliation removes the buffer and emits one category DELETE outbox row. Manage Categories renders the wall-clock countdown and registers the system Undo action for the newest eligible category deletion while that surface is active.

This change supplies the reusable toast/countdown behavior and category-screen wiring, but it does not mark app-wide undo tasks complete until the other management/history surfaces adopt them.

**Rationale:** Immediate category deletion is inconsistent with the repository's R3 contract. The snapshot must include joins because a foreign-key cascade otherwise loses the information needed to restore assignments.

**Alternatives considered:**

- Delete immediately and recreate on Undo. Rejected because the relay could observe the delete and identity/association restoration would no longer be atomic.
- Add server-side soft delete. Rejected by the local-first hard-delete design.

### D8 - Test contracts at local, UI-state, wire, and backend boundaries

**Choice:** Add focused tests for category validation/icon parity, transactional seeding, category CRUD outcomes, association rollback/order, deletion snapshot/undo/expiry, ViewModel draft/error behavior, Profile routing, DTO mapping, Category-first pull, full-snapshot deletion, collision remapping, UUID v7 generation, and backend Activity transaction atomicity. Extend OpenAPI contract checks for the icon enum and Activity request/response association shapes. UI accessibility behavior is verified with stable identifiers and simulator smoke coverage.

**Rationale:** The existing local tests cover basic rows and outbox writes, but the discovered failures live at boundaries those tests do not exercise.

### D9 - Category chips are content-sized, evenly spaced, and touch-friendly

**Choice:** Render each `TagSelector` chip at its content width — icon (or checkmark), name, and uniform padding — in a wrapping flow layout with equal `Theme.spacingSmall` spacing between all chips, left-aligned. A chip's internal padding is uniform on all sides (10 pt; vertical and horizontal match), so a short chip is visibly smaller than a long one while gaps stay constant. Unselected chips show only the category icon, enlarged 30% above the caption size and scaling with Dynamic Type; selected chips swap the icon for a `checkmark` of the same enlarged size. No outline circle in either state. Selection is conveyed by the icon/checkmark swap plus the existing accent fill, so state remains perceivable by shape, not color alone. Each chip's interactive area remains at least 44×44 pt (`Theme.minTapArea`), following Apple HIG's 44×44 pt tap-target recommendation and WCAG 2.2 SC 2.5.5 (AAA), exceeding the 24×24 pt floor of WCAG SC 2.5.8 (AA).

**Rationale:** The uniform-width reserved-slot variant (first D9 iteration) made short chips visually sparse and felt rigid. Content-sized chips read as a natural tag cloud, equal spacing is what users perceive as "even", and the icon↔checkmark swap confines the selection change to one glyph position. The enlarged icon remains the primary recognition cue; the 44 pt target keeps the touch affordance.

**Alternatives considered:**

- Keep the reserved circular check slot with uniform chip widths (first D9 iteration). Rejected after implementation feedback: the constant circle reads as unfinished checkbox chrome, and uniform widths leave large internal gaps for short names.
- Fixed two-column stretching. Rejected because long localized names produce large internal gaps (the original complaint).
- Replace chips with list rows or radio controls. Rejected because chips fit the multi-select tag metaphor (D5) and keep the editor compact.

## Risks / Trade-offs

- **[Localized starter names can produce conceptually duplicate seeds when separate unsigned installations use different languages before joining the same relay account]** -> Name-collision remapping handles same-language duplicates; different-language seeds remain ordinary distinct Categories. Avoid adding hidden semantic fields when the agreed Category model is name plus icon, and revisit only if cross-locale duplication is observed.
- **[A full Category snapshot adds work to each sync]** -> Category catalogs are expected to stay small; indexed ID comparison is linear and avoids a new tombstone protocol. Add a delta/tombstone contract only if measurement justifies it.
- **[Snapshot reconciliation could erase a local-only Category]** -> Never remove an absent Category with a pending outbox mutation or active undo snapshot; cover first-sync with starter outbox rows in tests.
- **[Some catalog SF Symbols are unavailable on older supported OS versions]** -> Filter picker options by runtime availability and render a `tag` fallback while preserving valid synchronized raw values.
- **[Category-specific undo can be mistaken for completion of the global deferred undo work]** -> Update the active local-first task notes and project context precisely; leave other screen integrations open.
- **[Changing the local v1 schema invalidates developer databases]** -> This is permitted by the explicit pre-release policy; tests and simulator installs start with a clean database.

## Migration Plan

1. Reconcile the OpenAPI icon enum, Go validator, Swift `CatalogIcon`, and design token documentation; add contract tests before UI work.
2. Update the in-place local schema with category-name uniqueness and metadata storage, add the UUID v7 generator, and implement transactional seeding/category/association/deletion APIs through `LocalStore`.
3. Fix relay DTO mapping, backend Activity transaction boundaries, Category-first pull, full-snapshot reconciliation, and collision remapping.
4. Add Profile navigation, Manage Categories, Category Editor, category-scoped undo, and Activity editor integration.
5. Run backend and iOS tests/linters/builds, perform EN/RU and offline simulator smoke tests, then update requirements, Design, project context, and active local-first task notes.

No production data migration is required. Existing development databases are deleted/reinstalled rather than upgraded. The backend API shape remains compatible; rollback is an app/backend code rollback before release, with local development data reset if the schema is reverted.
