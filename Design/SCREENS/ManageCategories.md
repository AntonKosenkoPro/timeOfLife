# Manage Categories Screen

Implements F2/F6/U8/R1/R3 of `Requirements/FURPS/Activity_Catalog_and_Categories.md`. Full CRUD surface for category tags, reached from Manage Activities.

A separate Manage Categories screen (per the user's decision) so category CRUD does not crowd the Manage Activities list. The screen lists all categories, lets the user create/edit/delete them, and seeds 7 localized defaults on first run after sign-in (F6). Deletions are undoable for 30 s (R3) and conflict with the server by last-write-wins (R2).

**Default categories (F6):**

| Name | Icon |
|---|---|
| Work | `briefcase` |
| Hobby | `paintbrush` |
| Sport | `figure.run` |
| Education | `book` |
| Relax | `cup.and.saucer` |
| Sleep | `bed.double` |
| Entertainment | `tv` |

Seeded on first run after sign-in, only if the user has zero categories. Localized names via `L10n` (EN + RU). Categories have a validated catalog icon. The seed list matches `Requirements/FURPS/Activity_Catalog_and_Categories.md` F6.

---

## Screen: ManageCategoriesView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Catalog/Views/ManageCategoriesView.swift`
- **Route**: `.manageCategories`
- **ViewModel**: `ManageCategoriesViewModel`

### Layout

Wrap in `NavigationStack` (iOS 16/15 polyfill like `TimerView`).

- Inline navigation title: `L10n.manageCategoriesTitle`.
- Toolbar trailing: `Image(systemName: "plus")` button, `accessibilityIdentifier("ManageCategoriesAddButton")` → presents `CategoryEditor` in create mode (sheet, D21).
- Body: `List` of `CategoryRow` (`COMPONENTS.md`) ordered by name ascending (alpha). List background `Theme.backgroundPrimary`. `accessibilityIdentifier("ManageCategoriesList")` on the list.
- Empty state (U8): when `vm.categories.isEmpty` show `EmptyState(icon: "tag", title: L10n.manageCategoriesEmptyTitle, subtitle: L10n.manageCategoriesEmptySubtitle)` centered in the available space.
- `UndoToast` (`COMPONENTS.md`) overlay via `.safeAreaInset(edge: .bottom)` when `vm.undoToast != nil` (R3/D17).
- `ErrorBanner` (`COMPONENTS.md`) when `vm.conflictMessage != nil`, `accessibilityId: "ManageCategoriesConflictBanner"` — shown above the list.

### Keyboard handling

N/A — the screen is a list with no text input; editors are handled in the `CategoryEditor` sheet (D13/D21).

### Behaviors

- On appear load categories from the local store (offline-first, R1/D7). The list is sourced from the synced catalog and rendered in alpha order by `name`.
- Tap row → `CategoryEditor` edit mode (sheet, D21). The editor owns name + icon (`IconPickerGrid`) editing; save returns to this screen.
- Swipe-to-delete on a row → single destructive confirm (see Delete flow below). On confirm enter the undo flow (30 s; R3/U6/D17). Undo re-applies the tag to all activities that carried it via the join cascade; after 30 s commit locally and enqueue `DELETE` for sync.
- Toolbar `+` → `CategoryEditor` create mode (sheet, D21). On create conflict (409 `category_exists`, case-insensitive name collision) re-map local refs to the surviving id and proceed (R2); in the editor surface `L10n.errorCategoryExists`.
- **Offline (R1):** list renders from the local store; create/edit/delete are queued locally and synced when connectivity returns. Disable no control here — list reads and optimistic mutations are offline-safe.
- **Conflict (R2):** on 409 `conflict`, show the inline `ErrorBanner` (`L10n.errorConflict`) and adopt the server's version as the source of truth (keep-latest). No field-level merge at MVP.
- **Seeding (F6):** on first run after sign-in, seed 7 localized categories — Work, Hobby, Sport, Education, Relax, Sleep, Entertainment — with their catalog icons via ordinary `POST /categories` requests. Seeds are first-class records: editable, icon-selectable, and deletable like any user-created category. Seeding is **idempotent** — it runs once, gated by a `categoriesSeeded` flag persisted locally; replays (same `POST` idempotently, or re-runs after relaunch before the flag is set) do not duplicate records.

### Delete flow

Single destructive confirm — a category has no entries-scope choice, so `ScopeConfirmation` is not used (D18 / INTERACTIONS Delete-scope confirmation: category case).

1. Swipe-to-delete on a `CategoryRow` presents a `.confirmationDialog`:
   - Title: `L10n.deleteCategoryTitle`.
   - Message: `String(format: L10n.deleteCategoryMessage.text, category.name)` — explicitly states the category will be removed from all activities (join cascade) and that **entries are unaffected** (D18, F2).
   - Confirm button: `L10n.deleteCategoryConfirm`, `role: .destructive`.
   - Cancel button: `L10n.deleteCategoryCancel`, `role: .cancel`.
2. On confirm, the category enters the client-side undo buffer (R3/D17): the local store removes the category and strips its tag from all activities via join cascade; entries are untouched. Show `UndoToast` with `L10n.undoCategoryDeleted` for 30 s.
3. Undo (tap or system shake-to-undo, U7) re-applies the tag to activities from the buffer before the window elapses; nothing is synced.
4. After 30 s (or supersession / relaunch), commit locally (hard delete) and enqueue `DELETE /categories/{id}` for sync; the server hard-deletes (no trash, per the API contract).

Reference: D17 and `Design/INTERACTIONS.md` → Undo flow + Delete-scope confirmation.

### States

| State | Visual |
|---|---|
| Loading | Empty `List` background; categories load from local store on appear (typically instant) |
| Empty | `EmptyState` (`tag` icon, empty title/subtitle) — U8 |
| Loaded | `List` of `CategoryRow` in alpha order |
| Deleting (undo visible) | `UndoToast` pinned at bottom safe area for 30 s; row already removed from list |
| Conflict | `ErrorBanner` above the list (`L10n.errorConflict`); server version adopted |

### Data model

```swift
struct Category: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var icon: CatalogIcon
    let createdAt: Date
    var updatedAt: Date
}
```

### Implementation checklist

- [ ] All strings use `L10n.*` keys (EN + RU).
- [ ] List has `accessibilityIdentifier("ManageCategoriesList")`.
- [ ] Add button has `accessibilityIdentifier("ManageCategoriesAddButton")`.
- [ ] Rows use `CategoryRow` with `CategoryRow(<id>)` identifiers (per `COMPONENTS.md`).
- [ ] Swipe-to-delete button has `accessibilityIdentifier("CategoryRowDelete(<id>)")`.
- [ ] Undo button uses `UndoToast` with `UndoToastButton` (per `COMPONENTS.md`).
- [ ] Category delete is tag-only — join cascade removes the tag from activities; entries are unaffected (state in confirm copy).
- [ ] Category icons use the validated `CatalogIcon` set.
- [ ] Seeding runs once and is idempotent (`categoriesSeeded` flag); seeds are editable/deletable.
- [ ] Offline queue handles create/edit/delete; conflict (409 `conflict`) shows `ErrorBanner` and adopts server version (R2).
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## New localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Manage categories
"manage.categories.title" = "Categories";
"manage.categories.emptyTitle" = "No categories yet";
"manage.categories.emptySubtitle" = "Add one to tag your activities.";

// Category delete confirmation
"delete.category.title" = "Delete category?";
"delete.category.message" = "%@ will be removed from all activities. Your entries are kept.";
"delete.category.confirm" = "Delete";
"delete.category.cancel" = "Cancel";

// Undo
"undo.categoryDeleted" = "Category deleted";
"undo.button" = "Undo";

// Errors
"error.categoryExists" = "A category with this name already exists.";
"error.conflict" = "Edited on another device. Showing the latest version.";

// Seeded categories (F6)
"category.seed.work" = "Work";
"category.seed.hobby" = "Hobby";
"category.seed.sport" = "Sport";
"category.seed.education" = "Education";
"category.seed.relax" = "Relax";
"category.seed.sleep" = "Sleep";
"category.seed.entertainment" = "Entertainment";
```

Russian:

```text
// Manage categories
"manage.categories.title" = "Категории";
"manage.categories.emptyTitle" = "Пока нет категорий";
"manage.categories.emptySubtitle" = "Добавьте категорию, чтобы размечать активности.";

// Category delete confirmation
"delete.category.title" = "Удалить категорию?";
"delete.category.message" = "%@ будет удалена со всех активностей. Записи сохранятся.";
"delete.category.confirm" = "Удалить";
"delete.category.cancel" = "Отмена";

// Undo
"undo.categoryDeleted" = "Категория удалена";
"undo.button" = "Отменить";

// Errors
"error.categoryExists" = "Категория с таким названием уже существует.";
"error.conflict" = "Изменено на другом устройстве. Показана актуальная версия.";

// Seeded categories (F6)
"category.seed.work" = "Работа";
"category.seed.hobby" = "Хобби";
"category.seed.sport" = "Спорт";
"category.seed.education" = "Образование";
"category.seed.relax" = "Отдых";
"category.seed.sleep" = "Сон";
"category.seed.entertainment" = "Развлечения";
```
