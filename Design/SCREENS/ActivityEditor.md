# Activity Editor Screen

Implements F1/F3/F7/U1/U2/U4 of `Requirements/FURPS/Activity_Catalog_and_Categories.md`. Shared sheet for creating and editing an activity; reused by the timer quick-add (F7) and Manage Activities (F8). Per decision D21.

---

## Screen: ActivityEditorView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Catalog/Views/ActivityEditorView.swift`
- **Route**: presented as a `.sheet` (not a nav route). Two modes: create / edit. In create-from-timer mode, on save it also selects the activity on the timer and links the upcoming entry (F7).
- **ViewModel**: `ActivityEditorViewModel`

### Layout

Presented as `.sheet` with `medium` detents (`.medium` + `.large()` if content scrolls). `ScrollView` → `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding` and `maxWidth: Theme.maxContentWidth`:

1. Title — create: `L10n.activityEditorCreateTitle`; edit: `L10n.activityEditorEditTitle` — `.title.bold()`, `Theme.textPrimary`.
2. `TextFieldWithError` for name:
   - `accessibilityId`: `ActivityEditorNameField`
   - title/placeholder: `L10n.activityEditorNameLabel` / `L10n.activityEditorNamePlaceholder`
   - `submitLabel`: `.done`
   - `autocapitalization`: `.sentences`
   - error: `vm.fieldErrors.name`
   - Focused on appear.
3. Notes — a styled `TextEditor` (multi-line) with the same field treatment as `TextFieldWithError`:
   - label above: `L10n.activityEditorNotesLabel` — `.caption`, `Theme.textSecondary`
   - `TextEditor(text: $vm.notes)` with `Theme.backgroundSecondary` fill, `Theme.hairline` 1 pt border, `Theme.cornerRadius`, min height ~96 pt
   - `accessibilityIdentifier("ActivityEditorNotesField")`
   - char counter beneath: `String(format: L10n.activityEditorNotesCounter.text, vm.notes.count)` — `.caption`, `Theme.textSecondary`, trailing-aligned; switches to `Theme.danger` when count > 280
4. `SectionHeader(L10n.activityEditorTagsLabel)` + `TagSelector(options: vm.availableCategories, selected: $vm.selectedCategoryIds, accessibilityId: "ActivityEditorTags")`. If `vm.availableCategories.isEmpty`, show a hint `L10n.activityEditorNoTags` (`.caption`, `Theme.textSecondary`) with a tappable link `L10n.activityEditorAddCategory` (`.subheadline`, `Theme.accentPrimary`, `accessibilityIdentifier("ActivityEditorAddCategoryButton")`) → presents `CategoryEditor` create sheet.
5. `ErrorBanner` if `vm.errorMessage != nil` — `accessibilityId: ActivityEditorErrorBanner`.
6. Fixed reserve for the pinned bottom action bar (`Color.clear` matching the measured bar height plus `Theme.spacingLarge`).

Background: `Theme.backgroundPrimary`.

### Pinned bottom action bar

Via `.safeAreaInset(edge: .bottom)` (D13):

- `PrimaryButton`:
  - title: `L10n.activityEditorSave`
  - `accessibilityId`: `ActivityEditorSaveButton`
  - disabled while name trim-empty or `isLoading`
  - `isLoading`: reflects `vm.isLoading`

Cancel mechanism (both present):

- System swipe-down dismiss (sheet).
- `.toolbar` Cancel item (`accessibilityIdentifier("ActivityEditorCancelButton")`) in the sheet's navigation bar — plain `Button(L10n.activityEditorCancel)`.

**Cancel during save:** If the user dismisses (swipe-down or Cancel tap) while `isLoading == true`, the sheet stays visible until the in-flight request completes or fails. Cancel is deferred — the sheet dismisses on success, or shows the error and remains interactive on failure. The Cancel button is disabled while `isLoading`.

### Keyboard handling

Follows `Design/INTERACTIONS.md` → **Keyboard and primary input placement** and **Editor sheets and keyboard placement** (D13/D21). The name field sits in the upper scrollable area (title, then field) so the caret stays visible when the keyboard opens; it is focused on appear. The Save `PrimaryButton` is pinned to `.safeAreaInset(edge: .bottom)` so it follows the keyboard and stays tappable without dismissing it. A measured bottom reserve prevents the name field from being hidden behind the bar on short screens.

### Behaviors

- Focus the name field on appear (D13).
- Validate on save (U1/U2): name non-empty after trim & ≤ 60 → unified `validation.nameEmpty` / `validation.nameTooLong`; notes ≤ 280 → `validation.notesTooLong`. Multiple rules for one field collapse into a single unified message (U2).
- Clear a field's error when the user edits that field.
- On 422 `validation_error`: map `details` into `vm.fieldErrors` and show each beneath its field.
- On 409 `activity_exists` (case-insensitive name collision on create): reuse the existing activity per INTERACTIONS — in create-from-timer mode, select that activity on the timer, link it to the upcoming entry (F7), and dismiss; in create-from-manage mode, dismiss and surface `error.activityExists` via `ErrorBanner`.
- On 409 `conflict` (LWW stale write, R2): show `ErrorBanner` and adopt the server's version as the source of truth (keep-latest); pre-fill the editor from the server version.
- Save success: dismiss the sheet; create-from-timer also links the activity to the upcoming entry (F7) and prefills the timer field with the activity's name.
- Dismiss the keyboard on save / cancel; do not leave it up after the sheet closes.
- Haptic `.notification(.error)` on validation error (INTERACTIONS Haptics).
- Offline: queue the create / edit locally and sync on reconnect (R1); the Save button stays tappable offline.

### States

| State | Visual |
|---|---|
| Create | Title `activityEditorCreateTitle`; Save disabled while name trim-empty |
| Edit | Title `activityEditorEditTitle`; fields pre-filled from the activity; Save enabled if name non-empty and changed |
| Saving | `PrimaryButton` shows `ProgressView`; Save disabled |
| Validation error | Field errors beneath name / notes; `.notification(.error)` haptic; Save re-enables after edit |
| Conflict (409 `activity_exists`) | create-from-timer: dismiss and reuse; create-from-manage: `ErrorBanner` `error.activityExists` |
| Conflict (409 `conflict`) | `ErrorBanner`; editor reset to server version (keep-latest) |

### Data model

The editor holds a draft:

```swift
struct ActivityDraft {
    var name: String
    var notes: String?
    var categoryIds: [UUID]
}
```

On save it produces an `Activity` (create) or a PATCH body (edit) carrying `updated_at` for LWW (R2). Category order is preserved in `categoryIds`.

### Implementation checklist

- [ ] All strings use `L10n.*` keys (add new keys to EN and RU).
- [ ] Accessibility IDs: `ActivityEditorNameField`, `ActivityEditorNotesField`, `ActivityEditorTags`, `ActivityEditorSaveButton`, `ActivityEditorCancelButton`, `ActivityEditorAddCategoryButton`.
- [ ] Keyboard placement follows D13 / D21: name upper, Save pinned bottom, measured reserve.
- [ ] Validation uses unified messages (`validation.nameEmpty` / `validation.nameTooLong` / `validation.notesTooLong`); 409 `activity_exists` reuses the existing activity per INTERACTIONS.
- [ ] 409 `conflict` adopts the server version (R2 keep-latest).
- [ ] Sheet dismisses on save success and on cancel (swipe + toolbar Cancel).
- [ ] Screen previews exist for light/dark and EN/RU, in both create and edit modes.
- [ ] SwiftLint passes with zero findings.

---

## New localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Activity editor
"activityEditor.createTitle" = "New activity";
"activityEditor.editTitle" = "Edit activity";
"activityEditor.nameLabel" = "Name";
"activityEditor.namePlaceholder" = "e.g. Gym";
"activityEditor.notesLabel" = "Notes";
"activityEditor.notesPlaceholder" = "Optional notes";
"activityEditor.notesCounter" = "%d / 280";
"activityEditor.tagsLabel" = "Categories";
"activityEditor.noTags" = "No categories yet.";
"activityEditor.addCategory" = "Add a category";
"activityEditor.save" = "Save";
"activityEditor.cancel" = "Cancel";

// Validation
"validation.nameEmpty" = "Enter a name.";
"validation.nameTooLong" = "Name must be at most 60 characters.";
"validation.notesTooLong" = "Notes must be at most 280 characters.";

// Errors
"error.activityExists" = "An activity with this name already exists.";
```

Russian:

```text
// Activity editor
"activityEditor.createTitle" = "Новая активность";
"activityEditor.editTitle" = "Изменить активность";
"activityEditor.nameLabel" = "Название";
"activityEditor.namePlaceholder" = "напр. Спортзал";
"activityEditor.notesLabel" = "Заметки";
"activityEditor.notesPlaceholder" = "Необязательные заметки";
"activityEditor.notesCounter" = "%d / 280";
"activityEditor.tagsLabel" = "Категории";
"activityEditor.noTags" = "Пока нет категорий.";
"activityEditor.addCategory" = "Добавить категорию";
"activityEditor.save" = "Сохранить";
"activityEditor.cancel" = "Отмена";

// Validation
"validation.nameEmpty" = "Введите название.";
"validation.nameTooLong" = "Название должно быть не длиннее 60 символов.";
"validation.notesTooLong" = "Заметки должны быть не длиннее 280 символов.";

// Errors
"error.activityExists" = "Активность с таким названием уже существует.";
```
