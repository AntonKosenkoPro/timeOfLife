# Category Editor Screen

Implements F2/U1/U2 of `Requirements/FURPS/Activity_Catalog_and_Categories.md`. Shared sheet for creating and editing a category; reached from Manage Categories and the Activity Editor's add-category link. Per decision D21.

---

## Screen: CategoryEditorView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Catalog/Views/CategoryEditorView.swift`
- **Route**: presented as a `.sheet`. Create / edit modes.
- **ViewModel**: `CategoryEditorViewModel`

### Layout

`.sheet` with `medium` detents. `ScrollView` → `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding` and `Theme.maxContentWidth`:

1. Title — `.title.bold()`, `Theme.textPrimary`. Create: `L10n.categoryEditorCreateTitle`; edit: `L10n.categoryEditorEditTitle`.
2. `TextFieldWithError` for name:
   - `accessibilityId`: `CategoryEditorNameField`
   - title / placeholder: `L10n.categoryEditorNameLabel` / `L10n.categoryEditorNamePlaceholder`
   - `submitLabel`: `.done`
   - `autocapitalization`: `.sentences`
   - error: `vm.fieldErrors.name`
   - Focused on appear.
3. `SectionHeader(L10n.categoryEditorColorLabel)` + `ColorSwatchGrid(options: ActivityColor.allCases, selection: $vm.color, accessibilityId: "CategoryEditorColor")`.
4. `ErrorBanner` if `vm.errorMessage != nil`:
   - `accessibilityId`: `CategoryEditorErrorBanner`
5. Fixed reserve for the pinned bottom action bar.

Background: `Theme.backgroundPrimary`.

Pinned bottom action bar via `.safeAreaInset(edge: .bottom)` (D13):

- `PrimaryButton`:
  - title: `L10n.categoryEditorSave`
  - `accessibilityId`: `CategoryEditorSaveButton`
  - disabled while name is whitespace-only (trimmed) or `vm.isLoading`
- Cancel via swipe-down and a toolbar `Cancel` button with `accessibilityIdentifier("CategoryEditorCancelButton")`.

### Keyboard handling

Follows `Design/INTERACTIONS.md` → **Editor sheets and keyboard placement** (D13 / D21). The name field sits in the upper scrollable area, focused on appear. The Save `PrimaryButton` is pinned to `.safeAreaInset(edge: .bottom)` so it follows the keyboard and stays tappable. A measured bottom reserve prevents the field from being hidden behind the action bar on short screens. Dismiss the sheet on save success or cancel; do not leave the keyboard up after save.

### Behaviors

- Focus the name field on appear.
- Validate (U1/U2): name non-empty and ≤ 60 chars → unified `validation.name*` message; collapse multiple rules into a single message per field (U2).
- Edit mode pre-fills `vm.name` and `vm.color` from the passed-in `Category`.
- On 422 show field errors beneath the name field.
- On 409 `category_exists` (case-insensitive name collision), reuse the existing category per `Design/INTERACTIONS.md` → **Sync conflict**: dismiss the sheet and surface `L10n.errorCategoryExists` to the caller; re-map local references to the surviving id (no editor-level error).
- Save success: dismiss the sheet. If opened from the Activity Editor's add-category link, the new category appears pre-selected in the `TagSelector`.
- Clear field error when `vm.name` changes.
- Disable Save while `vm.isLoading` or name is empty/whitespace-only.

### States

| State | Visual |
|---|---|
| Create | Empty name field, default color swatch selected, Save disabled (name empty) |
| Edit | Name + color pre-filled from the existing `Category`, Save enabled |
| Saving | Save button shows `ProgressView`; fields and swatches disabled |
| Validation error | Name field border + error label in `Theme.danger`; Save disabled if name empty/invalid |
| Conflict (409 `category_exists`) | Sheet dismissed; caller surfaces `error.categoryExists` banner |

### Data model

```swift
struct CategoryEditorDraft {
    var name: String
    var color: ActivityColor?
}

struct Category: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var color: ActivityColor
    var updatedAt: Date
}
```

- The draft holds `name` and `color`.
- On save, the ViewModel produces a `Category`: `POST` (create) or `PATCH` (edit) carrying `updated_at` (R2, last-write-wins).

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys (add new keys to EN and RU).
- [ ] Accessibility identifiers: `CategoryEditorNameField`, `CategoryEditorColor`, `CategoryEditorSaveButton`, `CategoryEditorCancelButton`, `CategoryEditorErrorBanner`.
- [ ] Keyboard placement follows D13 (name upper, Save pinned bottom, measured reserve).
- [ ] Validation uses unified `validation.name*` messages (U2).
- [ ] 409 `category_exists` reuses the existing category and dismisses the editor (per `INTERACTIONS.md`).
- [ ] Edit mode pre-fills name + color from the passed-in `Category`.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## New localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Category editor
"categoryEditor.createTitle" = "New category";
"categoryEditor.editTitle" = "Edit category";
"categoryEditor.nameLabel" = "Name";
"categoryEditor.namePlaceholder" = "e.g. Sport";
"categoryEditor.colorLabel" = "Color";
"categoryEditor.save" = "Save";
"categoryEditor.cancel" = "Cancel";

// Errors
"error.categoryExists" = "A category with this name already exists.";
```

Russian:

```text
// Category editor
"categoryEditor.createTitle" = "Новая категория";
"categoryEditor.editTitle" = "Изменить категорию";
"categoryEditor.nameLabel" = "Название";
"categoryEditor.namePlaceholder" = "напр. Спорт";
"categoryEditor.colorLabel" = "Цвет";
"categoryEditor.save" = "Сохранить";
"categoryEditor.cancel" = "Отмена";

// Errors
"error.categoryExists" = "Категория с таким названием уже существует.";
```