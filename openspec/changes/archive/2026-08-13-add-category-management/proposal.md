## Why

Categories already exist in the local-first data model and are referenced by the Activity editor contract, but users do not yet have a complete way to start with useful defaults, manage categories, or maintain Activity-category assignments. This change completes that product surface so Activities can be organized offline without making categorization a prerequisite for tracking time.

## What Changes

- Seed seven predefined, localized starter categories on first local database setup: Work, Hobby, Sport, Education, Relax, Sleep, and Entertainment.
- Add a Profile-owned Manage Categories surface for listing, creating, editing, and deleting categories.
- Require each category to have a validated name and an icon selected from the supported catalog SF Symbol set.
- Extend the shared Activity editor so a user can assign or remove multiple category tags while keeping category assignment optional.
- Persist category CRUD and Activity-category changes atomically through `LocalStore`, with outbox operations for optional relay sync.
- Keep category deletion limited to the category and its Activity associations; Activities, entries, and timer state remain intact, and the deletion remains undoable for 30 seconds on the Manage Categories surface.
- Add localized empty, validation, error, and destructive-confirmation states with stable accessibility identifiers.

Explicit non-goals:

- Making a category mandatory before an Activity can be created or timed.
- Showing Category metadata in Track search results or recency suggestions.
- Manual category ordering, nested categories, custom uploaded icons, colors, category analytics, or starter Activities.
- Completing unrelated deferred surfaces from `local-first-sync-architecture`, including app-wide rollout of UndoToast/shake beyond category deletion, the Enable Sync sheet, provenance labels, or the lock-screen ControlWidget.

## Capabilities

### New Capabilities

- `category-management`: Defines starter-category seeding, Profile-owned category CRUD, category validation and icon selection, optional many-to-many Activity assignment, deletion behavior, local-first persistence, and relay synchronization.

### Modified Capabilities

- None. The existing `app-shell` already assigns activity/category management to Profile, and `timer-capture-experience` already defines Categories as optional Activity metadata editable through Refine; this change supplies the dedicated behavior without changing those requirements.

## Impact

- **iOS:** `LocalStore` category and join-table mutations, seed initialization, Catalog models/repositories, Profile navigation, Manage Categories UI, the shared Activity editor, localization, accessibility identifiers, and tests.
- **Backend relay:** verify or complete category CRUD and Activity-category association transport using the existing catalog endpoints and conflict rules; update `backend/api/openapi.yaml` and contract tests if the authoritative contract lacks any required association shape.
- **Sync:** category records and Activity-category associations must remain available offline and converge through the transactional outbox and `SyncController` without bypassing `LocalStore`.
- **Authoritative documentation:** `Requirements/FURPS/Activity_Catalog_and_Categories.md`, `Requirements/Usecases/Activity_Catalog_and_Categories.md`, relevant `Design/` screen/component specifications, `docs/project-context.md`, and OpenAPI when its contract changes.
- **Affected existing capabilities:** `app-shell` constrains navigation ownership and `timer-capture-experience` constrains optional assignment and capture behavior; neither baseline spec is edited directly by this proposal.
