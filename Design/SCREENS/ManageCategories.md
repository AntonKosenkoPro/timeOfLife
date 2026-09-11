# Manage Categories Screen

Implements F2/F6/U8/R1/R3 of `Requirements/FURPS/Activity_Catalog_and_Categories.md`. Full CRUD surface for category tags, reached from Profile for signed-in and signed-out users.

A separate Manage Categories screen (per the user's decision) so category CRUD does not crowd the Manage Activities list. The screen lists all categories, lets the user create/edit them, and seeds 7 localized defaults on first run (F6). Deletion lives in the category editor and is undoable until the app restarts via the system Undo confirmation (R3); conflicts with the server resolve by last-write-wins (R2).

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

Seeded once per local dataset by the `category_starters_seeded` marker. Deleting all Categories does not reseed; Erase local data clears the marker so a genuinely new dataset receives the set again. Localized names use `L10n` (EN + RU), and Categories have a validated catalog icon.

---

## Screen: ManageCategoriesView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Catalog/Views/ManageCategoriesView.swift`
- **Route**: Profile → Categories (`NavigationLink`)
- **ViewModel**: `ManageCategoriesViewModel`

### Layout

Use the existing Profile-owned `NavigationView` stack (iOS 15-compatible).

- Inline navigation title: `L10n.manageCategoriesTitle`.
- Toolbar trailing: `Image(systemName: "plus")` button, `accessibilityIdentifier("ManageCategoriesAddButton")` → presents `CategoryEditor` in create mode (sheet, D21).
- Body: `List` of `CategoryRow` (`COMPONENTS.md`) ordered by name ascending (alpha). List background `Theme.backgroundPrimary`. `accessibilityIdentifier("ManageCategoriesList")` on the list.
- Loading state: show a progress indicator while the local catalog is read; a load failure is an error state, not a misleading empty state.
- Empty state (U8): when `vm.categories.isEmpty` show `EmptyState(icon: "tag", title: L10n.manageCategoriesEmptyTitle, subtitle: L10n.manageCategoriesEmptySubtitle)` plus the Add action.
- `ErrorBanner` (`COMPONENTS.md`) when `vm.conflictMessage != nil`, `accessibilityId: "ManageCategoriesConflictBanner"` — shown above the list.

### Keyboard handling

N/A — the screen is a list with no text input; editors are handled in the `CategoryEditor` sheet (D13/D21).

### Behaviors

- On appear load categories from the local store (offline-first, R1/D7). The list is sourced from the synced catalog and rendered in alpha order by `name`.
- Tap row → `CategoryEditor` edit mode (sheet, D21). The editor owns name + icon (`IconPickerGrid`) editing plus the destructive Delete button; save/delete return to this screen.
- The list offers no delete affordance (no swipe, no context menu) — deletion is initiated only from the category editor's Delete button (see Delete flow below).
- Toolbar `+` → `CategoryEditor` create mode (sheet, D21). On create conflict (409 `category_exists`, case-insensitive name collision) re-map local refs to the surviving id and proceed (R2); in the editor surface `L10n.errorCategoryExists`.
- **Offline (R1):** list renders from the local store; create/edit/delete are queued locally and synced when connectivity returns. Disable no control here — list reads and optimistic mutations are offline-safe.
- **Conflict (R2):** on a stale local edit, show the inline `ErrorBanner` (`L10n.errorConflict`) and prefill the editor with the latest local/server-adopted version. No field-level merge at MVP.
- **Seeding (F6):** on first local-dataset setup, seed 7 localized categories — Work, Hobby, Sport, Education, Relax, Sleep, Entertainment — with their catalog icons via ordinary outbox-backed Category creates. Seeds are first-class records: editable, icon-selectable, and deletable like any user-created category. Seeding is **idempotent** through the persisted `category_starters_seeded` marker.

### Delete flow

Single destructive confirm in the category editor (edit mode) — a category has no entries-scope choice, so `ScopeConfirmation` is not used (D18 / INTERACTIONS Delete-scope confirmation: category case).

1. The editor's bottom Delete button (`CategoryEditorDeleteButton`) presents an alert:
   - Title: `L10n.deleteCategoryTitle`.
   - Message: `String(format: L10n.deleteCategoryMessage.text, category.name)` — explicitly states the category will be removed from all activities (join cascade), that **entries are unaffected** (D18, F2), and that shaking undoes until the app restarts.
   - Confirm button: `L10n.deleteCategoryConfirm`, `role: .destructive`.
   - Cancel button: `L10n.categoryEditorCancel`, `role: .cancel`.
2. On confirm, the category enters the client-side undo buffer (R3/D17): the local store removes the category and strips its tag from all activities via join cascade; entries are untouched. The editor dismisses and the list reloads.
3. Undo is the DEFAULT system Undo confirmation only (U7, no toast): shaking on Manage Categories surfaces the system prompt, and confirming restores the newest eligible category deletion with its activity assignments; nothing is synced.
4. On app restart, commit locally (hard delete) and enqueue `DELETE /categories/{id}` for sync; the server hard-deletes (no trash, per the API contract).

Reference: D17 and `Design/INTERACTIONS.md` → Undo flow + Delete-scope confirmation.

### States

| State | Visual |
|---|---|
| Loading | Progress indicator while categories load from the local store |
| Empty | `EmptyState` (`tag` icon, empty title/subtitle) — U8 |
| Loaded | `List` of `CategoryRow` in alpha order |
| Deleting (undoable) | Row already removed from list; shake surfaces the system Undo confirmation until the app restarts |
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

- [x] All strings use `L10n.*` keys (EN + RU), including icon VoiceOver names.
- [x] List has `accessibilityIdentifier("ManageCategoriesList")`.
- [x] Add button has `accessibilityIdentifier("ManageCategoriesAddButton")`.
- [x] Rows use `CategoryRow` with `CategoryRow(<id>)` identifiers (per `COMPONENTS.md`).
- [x] Category editor Delete button has `accessibilityIdentifier("CategoryEditorDeleteButton")`.
- [x] Undo is the system Undo confirmation only (no toast component).
- [x] Category delete is tag-only — the deletion transaction removes joins; entries and timer state are unaffected.
- [x] Category icons use the validated `CatalogIcon` set with a renderable picker and fallback display.
- [x] Seeding runs once and is idempotent (`category_starters_seeded` marker); seeds are editable/deletable.
- [x] Offline queue handles create/edit/delete; stale edits adopt the latest persisted version.
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

// Category delete confirmation (in the category editor)
"delete.category.title" = "Delete category?";
"delete.category.message" = "%@ will be removed from all activities. Your entries are kept. You can shake to undo until you restart the app.";
"delete.category.confirm" = "Delete";
"categoryEditor.delete" = "Delete category";

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

// Category delete confirmation (in the category editor)
"delete.category.title" = "Удалить категорию?";
"delete.category.message" = "%@ будет удалена со всех активностей. Записи сохранятся. Отменить можно встряской в течение 30 секунд.";
"delete.category.confirm" = "Удалить";
"categoryEditor.delete" = "Удалить категорию";

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
