## 1. Category Contracts and Domain Types

- [x] 1.1 Define the authoritative `Category.icon` enum in `backend/api/openapi.yaml`, reconcile the Go `validIcons` set and `Design/TOKENS.md` to it, and add contract tests that fail when the lists drift.
- [x] 1.2 Add the iOS `CatalogIcon` closed raw-value type with `tag` default, runtime-renderability filtering/fallback, and parity tests against the authoritative icon set.
- [x] 1.3 Add `CategoryName` normalization/validation and `CategoryDraft`, including tests for trimming, empty input, the 60-character boundary, duplicate normalization, and unsupported icons.
- [x] 1.4 Add one dependency-injectable UUID v7 record-ID generator, use it for new Category, Activity, and Entry relay resources, and test UUID version/variant, lowercase formatting, ordering, and deterministic injection.

## 2. LocalStore Category Foundation and Seeding

- [x] 2.1 Update the in-place GRDB v1 schema with a case-insensitive normalized Category-name unique index and local metadata storage for `category_starters_seeded`, following the pre-release reset policy rather than adding compatibility branches.
- [x] 2.2 Replace primitive category create/update entry points with validated, typed `LocalStore` outcomes that atomically write state plus outbox, distinguish local duplicate/stale/invalid failures, and preserve the single mutation chokepoint.
- [x] 2.3 Implement `seedStarterCategoriesIfNeeded` as one transaction that inserts the seven localized ordinary Categories, their create outbox rows, and the completion marker; wire app initialization to supply EN/RU names and the specified icons.
- [x] 2.4 Extend erase-local-data behavior to clear the seed marker so a genuinely new local dataset seeds again, without reseeding when users merely delete all Categories.
- [x] 2.5 Add `LocalStoreTests` for atomic seed success/failure/retry, no reseed after deletion, reseed after erase, localized persisted names, category CRUD/outbox atomicity, normalized duplicate races, and stale updates.

## 3. Atomic Activity Associations and Relay Mapping

- [x] 3.1 Make local Activity-category replacement validate all referenced Categories, de-duplicate while preserving order, and roll back Activity fields, joins, and outbox together when any association is invalid.
- [x] 3.2 Preserve `activity_categories.position` when reading Activities and add tests for assigning multiple Categories, removing one, clearing all, invalid-ID rollback, and complete ordered Activity outbox payloads.
- [x] 3.3 Add explicit Activity wire DTOs in `RemoteCatalogRepository` that encode `category_ids`, decode embedded `categories`, and map them to local ordered `categoryIDs`; add repository tests against representative OpenAPI responses.
- [x] 3.4 Refactor SQLite and PostgreSQL Activity create/update operations so Activity fields and category-join replacement share one database transaction and failed Category validation leaves no partial Activity mutation.
- [x] 3.5 Add backend store/handler and PostgreSQL parity tests for atomic Activity create/update rollback, association ordering, Category deletion preserving Activities/Entries, and request/response association shapes.

## 4. Category Synchronization

- [x] 4.1 Change `SyncController` pull ordering to fetch and merge the full Category snapshot before Activities, then Entries, without weakening local foreign-key enforcement.
- [x] 4.2 Implement authoritative Category-snapshot reconciliation that removes clean local Categories absent from the relay while preserving Categories with pending create/update outbox work or an active undo snapshot.
- [x] 4.3 Complete `category_exists` recovery by fetching/merging the winner before atomically remapping joins and pending Activity payloads, removing the losing local identity without a delete operation, and clearing the losing create row.
- [x] 4.4 Add sync tests for first-sync with starter outbox rows, Category-first association merge, LWW Category edits, offline association push, remote Category deletion, dirty-local preservation, idempotent replay, and collision remapping without Activity/Entry loss.

## 5. Category Deletion and Undo

- [x] 5.1 Add a typed category-deletion snapshot containing the Category and ordered Activity associations, and implement one `LocalStore` transaction to enter the durable undo buffer and remove the Category/joins without an outbox row.
- [x] 5.2 Implement Category undo and expiry paths that respectively restore the same Category/joins without sync or finalize one Category DELETE outbox operation on foreground after the wall-clock window.
- [x] 5.3 Add reusable `UndoToast` wall-clock countdown behavior and system Undo registration on Manage Categories for the newest eligible deletion, with iOS 15+ behavior matching `Design/INTERACTIONS.md` and no app-wide completion claim.
- [x] 5.4 Add tests for deletion confirmation outcomes, assigned-Category snapshots, undo restoration, no outbox before expiry, foreground expiry, supersession, cold-launch navigation within the window, and unaffected Activities/Entries/timer state.

## 6. Category Management UI

- [x] 6.1 Implement or complete `CategoryRow` and `IconPickerGrid` using `Theme` tokens, Dynamic Type, renderable catalog icons, meaningful VoiceOver labels, and stable accessibility identifiers.
- [x] 6.2 Implement `CategoryEditorViewModel` create/edit modes with draft preservation, field-level validation, duplicate and persistence errors, stale-conflict adoption, and deterministic tests.
- [x] 6.3 Implement `CategoryEditorView` as the shared keyboard-safe sheet with prefilled edit state, default `tag` create state, icon selection, Cancel, pinned Save, error presentation, and light/dark EN/RU previews.
- [x] 6.4 Implement `ManageCategoriesViewModel` for alphabetized local loading, editor presentation, delete confirmation, conflict messaging, refresh after mutation, and category-scoped undo state, with unit tests.
- [x] 6.5 Implement `ManageCategoriesView` with list/empty/loading/conflict states, Add/edit/swipe-delete controls, destructive copy explaining tag-only deletion, UndoToast, and all documented identifiers.
- [x] 6.6 Make the Profile Categories row navigate to Manage Categories for signed-in and signed-out users without disturbing the selected primary tab or timer state; add Profile/navigation tests.
- [x] 6.7 Finish Activity editor Category behavior by keeping zero-or-more multi-selection ordered, refreshing available Categories safely, preserving the draft on atomic save failure, and testing assign/remove/clear plus unchanged Track timer state.
- [x] 6.8 Add every new user-facing string to EN and RU `Localizable.strings` and `L10n`, then extend localization enumeration/parity tests for editor, validation, list, empty, confirmation, conflict, seed, accessibility, and undo copy.
- [x] 6.9 Redesign `TagSelector` chips per D9: content-sized chips in a wrapping flow layout with equal `Theme.spacingSmall` spacing, uniform 10 pt padding on all sides, icon-only unselected state and `checkmark`-only selected state (both 30% larger than `.caption`, scaling with Dynamic Type), no outline circles, and `Theme.minTapArea` (44 pt) minimum tap targets; update `Design/COMPONENTS.md` `TagSelector` visual/states/accessibility sections to match.

## 7. Documentation and Cross-Change Reconciliation

- [x] 7.1 Re-check and reconcile `Requirements/FURPS/Activity_Catalog_and_Categories.md` and its use cases with the implemented seed, Profile navigation, optional multi-tagging, deletion, undo, offline, and sync behavior.
- [x] 7.2 Update `Design/SCREENS/ManageCategories.md`, `CategoryEditor.md`, `ActivityEditor.md`, `Design/COMPONENTS.md`, `Design/INTERACTIONS.md`, `Design/TOKENS.md`, and `Design/DECISIONS.md` to remove stale navigation/model/icon assumptions and match the delivered UI.
- [x] 7.3 Update `docs/project-context.md`, `openspec/README.md`, and relevant `local-first-sync-architecture/tasks.md` notes to record this active change and category-specific undo progress without marking other deferred undo surfaces complete.
- [x] 7.4 Update `README.md` and OpenAPI descriptions/contract assertions where category synchronization, icon validation, UUID v7 generation, or Activity association transport changed; keep OpenAPI authoritative.

## 8. Verification

- [x] 8.1 Run `openspec validate add-category-management --strict` and `openspec validate --all`; resolve every proposal/spec/design/task coherence error.
- [x] 8.2 From `backend/`, run `go test ./... -cover`, `golangci-lint run`, `gofmt -l .`, `go vet ./...`, and `go build ./...`; fix every failure and ensure `gofmt -l .` is empty.
- [x] 8.3 From `ios/TimeOfLife/`, run `xcodegen generate`, `swiftlint lint --strict`, and the warning-as-error generic iOS Simulator build; fix every failure without hand-editing the generated project.
- [x] 8.4 Run the full iOS test suite on an available simulator, including the new validator, seed, LocalStore, undo, ViewModel, repository, sync, navigation, localization, and UUID v7 tests.
- [x] 8.5 Smoke-test with no account and no connectivity: verify starter Categories, Profile navigation, create/edit/delete/undo, empty state, and assigning zero/one/multiple Categories while timer preparation and running state remain intact.
- [x] 8.6 Smoke-test EN/RU, light/dark, Dynamic Type, VoiceOver labels, iOS 15-compatible symbol fallbacks, and stable accessibility identifiers on the category list/editor and Activity selector.
- [ ] 8.7 Run a signed-in relay smoke test for Category CRUD, Activity assignment round-trip, cross-device edit/delete convergence, and normalized-name collision remapping with no lost Activities or Entries. (Deferred: sign-in is not reachable from the UI — Profile "Enable Sync" does a silent `restoreSession()`; presenting `AuthFlowView` is `local-first-sync-architecture` task 5.2.)
- [x] 8.8 Re-run Activity-editor smoke verification for the redesigned chips: EN/RU, light/dark, Dynamic Type including accessibility sizes, VoiceOver check-state announcement, and stable identifiers.
