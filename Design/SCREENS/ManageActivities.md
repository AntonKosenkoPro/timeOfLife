# Manage Activities Screen

Implements F8/F10/F12/U8/R1–R3 of `Requirements/FURPS/Activity_Catalog_and_Categories.md`. Full CRUD surface for activities, reached from the timer screen (and a future account/menu destination).

Flows 5 and 6 in `Requirements/Usecases/Activity_Catalog_and_Categories.md`.

---

## Screen: ManageActivitiesView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Catalog/Views/ManageActivitiesView.swift` (new Features/Catalog area)
- **Route**: `.manageActivities` (new `AppRoute` case; add to the enum)
- **ViewModel**: `ManageActivitiesViewModel`

### Layout

Wrap in a `NavigationStack` (iOS 16 `NavigationStack`, iOS 15 `NavigationView(.stack)` polyfill — same pattern as `TimerView`). Inline nav title `L10n.manageActivitiesTitle`.

Toolbar:

- `ToolbarItem(placement: .topBarTrailing)` — `+` button: `Image(systemName: "plus")`, `accessibilityIdentifier("ManageActivitiesAddButton")`. Tapping presents `ActivityEditor` in create mode (sheet, D21).
- `ToolbarItem(placement: .topBarTrailing)` — Categories button: `Image(systemName: "slider.horizontal.3")` (or `tag.fill`), `accessibilityIdentifier("ManageActivitiesCategoriesButton")`. Tapping pushes `.manageCategories`.

Body: `List` of `ActivityRow`, ordered by `last_used_at` DESC (D19). Rows are lazy (`LazyVStack`-style lazy rows, P2, 60fps) — no work in row body. List background `Theme.backgroundPrimary`. `accessibilityIdentifier("ManageActivitiesList")` on the list.

If the list is empty → `EmptyState` centered:

- icon: `plus.circle.fill` (or `clock`)
- title: `L10n.manageActivitiesEmptyTitle`
- subtitle: `L10n.manageActivitiesEmptySubtitle`

Background: `Theme.backgroundPrimary`.

### Keyboard handling

N/A — this is a list screen with no text input.

### Behaviors

- On appear, load activities from the local store (offline-first, R1). Rows render lazily.
- Tap a row → `ActivityEditor` edit mode (sheet, pre-filled, D21).
- Swipe-to-delete on a row → delete flow (see below).
- `+` toolbar button → `ActivityEditor` create mode (sheet, D21).
- Categories toolbar button → push `.manageCategories`.
- Offline (F12 / D7): the list reads from the local store; CRUD is queued locally and synced when connectivity returns, per `Design/INTERACTIONS.md` → Offline. The `OfflineBanner` is rendered at the top by `RootView`.
- Sync conflict (R2): on 409 `conflict`, show an inline `ErrorBanner` ("Edited on another device") and adopt the server's current version as the source of truth (keep-latest). See `Design/INTERACTIONS.md` → Sync conflict.
- Seeding note: first-run seeds categories only (F6), not activities, so this list starts empty (U8). That is expected; the empty state guides toward creation and never blocks free-text timer start (D20).

### Delete flow

F10 / D17 / D18; see `Design/INTERACTIONS.md` → Undo flow and Delete-scope confirmation.

- **Activity with 0 entries:** single destructive confirm (system `.alert` / `.confirmationDialog`) → enter undo flow.
- **Activity with N > 0 entries:** present `ScopeConfirmation` (`entryCount: N`) offering two destructive choices, both naming N (D18):
  - delete the entire activity + all N entries (`onDeleteAll`)
  - delete only the latest entry (`onDeleteEntryOnly`)
  - cancel
- On confirm, the chosen item set is removed from the list immediately (optimistic) and `UndoToast` is shown for 30 s (R3 / U6). Undo re-inserts from the client-side undo buffer; after the window, commit locally and enqueue the `DELETE` for sync (the server hard-deletes, no trash).
- Bulk deletions (activity + its entries) are undoable as a unit — the buffer holds the whole set and Undo restores all of it.
- Shake-to-undo (U7) re-inserts the most recent undoable deletion until the buffer is superseded by the next undoable action or cleared on relaunch.

### States

| State | Visual |
|---|---|
| Loading | `ProgressView` centered over `Theme.backgroundPrimary` |
| Empty | `EmptyState` (icon + title + subtitle), centered |
| Loaded | `List` of `ActivityRow` ordered by `last_used_at` DESC |
| Deleting (undo toast visible) | Row(s) removed; `UndoToast` pinned at bottom safe area for 30 s |
| Conflict | Inline `ErrorBanner` ("Edited on another device"); server version adopted |

### Data model

```swift
struct Activity: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var notes: String?
    var lastUsedAt: Date?
    var categoryIds: [UUID]
}

struct Category: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var icon: CatalogIcon
    var createdAt: Date
    var updatedAt: Date
}
```

Entries reference an activity by `activity_id` (F9); the activity's name and tags are resolved from the activity at query time (nothing is denormalized onto the entry).

### Implementation checklist

- [ ] All strings use `L10n.*` keys (add new keys to EN and RU).
- [ ] List has `accessibilityIdentifier("ManageActivitiesList")`.
- [ ] Add button has `ManageActivitiesAddButton`; Categories button has `ManageActivitiesCategoriesButton`.
- [ ] Rows use `ActivityRow` with `accessibilityIdentifier("ActivityRow(\(id))")`; swipe-delete control has `ActivityRowDelete(\(id))`.
- [ ] Rows are lazy (`LazyVStack`-style) for P2 60fps with large catalogs.
- [ ] Undo flow + `ScopeConfirmation` follow `INTERACTIONS.md` and D17/D18.
- [ ] Offline queue + sync conflict (409 `conflict`) handling implemented per R1/R2.
- [ ] `EmptyState` shown when the list is empty (U8).
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## New localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Manage activities
"manage.activities.title" = "Activities";
"manage.activities.emptyTitle" = "No activities yet";
"manage.activities.emptySubtitle" = "Add one, or just type a name on the timer.";
"manage.activities.categories" = "Categories";

// Delete activity
"delete.activity.title" = "Delete activity?";
"delete.activity.message" = "This activity has %d entries.";
"delete.activity.entire" = "Delete activity and all %d entries";
"delete.activity.entryOnly" = "Delete only this entry";
"delete.activity.cancel" = "Cancel";

// Undo
"undo.activityDeleted" = "Activity deleted";
"undo.entriesDeleted" = "%d entries deleted";
"undo.button" = "Undo";

// Errors
"error.conflict" = "Edited on another device. Showing the latest version.";
"error.activityExists" = "An activity with this name already exists.";
```

Russian:

```text
// Manage activities
"manage.activities.title" = "Активности";
"manage.activities.emptyTitle" = "Пока нет активностей";
"manage.activities.emptySubtitle" = "Добавьте свою или просто введите название на таймере.";
"manage.activities.categories" = "Категории";

// Delete activity
"delete.activity.title" = "Удалить активность?";
"delete.activity.message" = "У этой активности %d записей.";
"delete.activity.entire" = "Удалить активность и все %d записи(ей)";
"delete.activity.entryOnly" = "Удалить только эту запись";
"delete.activity.cancel" = "Отмена";

// Undo
"undo.activityDeleted" = "Активность удалена";
"undo.entriesDeleted" = "Удалено записей: %d";
"undo.button" = "Отменить";

// Errors
"error.conflict" = "Изменено на другом устройстве. Показана актуальная версия.";
"error.activityExists" = "Активность с таким названием уже существует.";
```
