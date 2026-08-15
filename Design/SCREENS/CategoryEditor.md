# Category Editor Screen

Implements F2/U1/U2 of `Requirements/FURPS/Activity_Catalog_and_Categories.md`. Shared sheet for creating and editing a category; reached from Manage Categories and the Activity Editor's add-category link. Per decision D21.

---

## Screen: CategoryEditorView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Catalog/Views/CategoryEditorView.swift`
- **Route**: presented as a `.sheet`. Create / edit modes.
- **ViewModel**: `CategoryEditorViewModel`

### Layout

`.sheet` with `medium` and `large` detents on iOS 16+ (the iOS 15 fallback uses the system sheet height). `ScrollView` → `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding` and `Theme.maxContentWidth`:

1. Native collapsing navigation title via `EditorSheetScaffold`. Create: `L10n.categoryEditorCreateTitle`; edit: `L10n.categoryEditorEditTitle`. At the top edge the system renders its large-title form with Cancel in the top bar; scrolling collapses it into an inline material bar beside Cancel, and returning to the top expands it again.
2. `TextFieldWithError` for name:
   - `accessibilityId`: `CategoryEditorNameField`
   - title / placeholder: `L10n.categoryEditorNameLabel` / `L10n.categoryEditorNamePlaceholder`
   - `submitLabel`: `.done`
   - `autocapitalization`: `.sentences`
   - error: `vm.fieldErrors.name`
   - Focused on appear.
3. `SectionHeader(L10n.categoryEditorIconLabel)` + `IconPickerGrid(options: CatalogIcon.renderableSymbols, selection: $vm.icon, accessibilityId: "CategoryEditorIcon")`. A valid synchronized icon unavailable on the current OS remains selected by raw value and is displayed with the `tag` fallback until the user changes it.
4. `ErrorBanner` if `vm.errorMessage != nil`:
   - `accessibilityId`: `CategoryEditorErrorBanner`
5. Reserve matching the measured pinned bottom action bar height.

Background: `Theme.backgroundPrimary`.

Pinned bottom action bar via `.safeAreaInset(edge: .bottom)` (D13):

- `PrimaryButton`:
  - title: `L10n.categoryEditorSave`
  - `accessibilityId`: `CategoryEditorSaveButton`
  - disabled while name is whitespace-only (trimmed) or `vm.isLoading`
- Cancel via swipe-down and the scaffold's native cancellation toolbar item with `accessibilityIdentifier("CategoryEditorCancelButton")`; both dismiss paths are disabled while saving.

### Keyboard handling

Follows `Design/INTERACTIONS.md` → **Editor sheets and keyboard placement** (D13 / D21). The name field sits in the upper scrollable area, focused on appear. The Save `PrimaryButton` is pinned to `.safeAreaInset(edge: .bottom)` so it follows the keyboard and stays tappable. A measured bottom reserve prevents the field from being hidden behind the action bar on short screens. Dismiss the sheet on save success or cancel; do not leave the keyboard up after save.

### Behaviors

- Focus the name field on appear.
- Validate (U1/U2): name non-empty and ≤ 60 chars → unified `validation.name*` message; collapse multiple rules into a single message per field (U2).
- Edit mode pre-fills `vm.name` and `vm.icon` from the passed-in `Category`.
- On 422 show field errors beneath the name field.
- On a normalized duplicate, keep the editor open with the draft intact, show `L10n.errorCategoryExists`, and allow correction. Relay collision recovery remaps local references to the surviving id in `SyncController`.
- Save success: dismiss the sheet. If opened from the Activity Editor's add-category link, the new category appears pre-selected in the `TagSelector`.
- Clear field error when `vm.name` changes.
- Disable Save while `vm.isLoading` or name is empty/whitespace-only.

### States

| State | Visual |
|---|---|
| Create | Empty name field, default `tag` icon selected, Save disabled (name empty) |
| Edit | Name + icon pre-filled from the existing `Category`, Save enabled |
| Saving | Save button shows `ProgressView`; fields and swatches disabled |
| Validation error | Name field border + error label in `Theme.danger`; Save disabled if name empty/invalid |
| Duplicate name | Editor remains open with the draft and a localized correction error |

### Data model

```swift
struct CategoryEditorDraft {
    var name: String
    var icon: CatalogIcon?
}

struct Category: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var icon: CatalogIcon
    var updatedAt: Date
}
```

- The draft holds `name` and `icon`.
- On save, the ViewModel produces a `Category`: `POST` (create) or `PATCH` (edit) carrying `updated_at` (R2, last-write-wins).

### Implementation checklist

- [x] All strings use `L10n.*` keys (EN + RU).
- [x] Accessibility identifiers: `CategoryEditorNameField`, `CategoryEditorIcon`, `CategoryEditorSaveButton`, `CategoryEditorCancelButton`, `CategoryEditorErrorBanner`.
- [x] Keyboard placement follows D13 (name upper, Save pinned bottom, measured reserve).
- [x] Validation uses unified category-name messages (U2).
- [x] Duplicate names preserve the draft and keep the editor open.
- [x] Edit mode pre-fills name + icon from the passed-in `Category`.
- [x] iOS 16+ medium/large detents are availability guarded.
- [ ] Screen previews exist for light/dark and EN/RU.
- [x] SwiftLint passes with zero findings.

---

## New localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Category editor
"categoryEditor.createTitle" = "New category";
"categoryEditor.editTitle" = "Edit category";
"categoryEditor.nameLabel" = "Name";
"categoryEditor.namePlaceholder" = "e.g. Sport";
"categoryEditor.iconLabel" = "Icon";
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
"categoryEditor.iconLabel" = "Значок";
"categoryEditor.save" = "Сохранить";
"categoryEditor.cancel" = "Отмена";

// Errors
"error.categoryExists" = "Категория с таким названием уже существует.";
```
