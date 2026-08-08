# Activity Catalog & Categories — Use cases

Narrative flows for **Epic 1: Activity Catalog & Categories**. Each flow maps to rows in [`FURPS/Activity_Catalog_and_Categories.md`](../FURPS/Activity_Catalog_and_Categories.md).

## 1. First run — seeded defaults

1. The user launches the app and lands on the Track screen (no account required) for the first time.
2. The app seeds a localized (EN or RU per device language) starter set of 7 categories: Work, Hobby, Sport, Education, Relax, Sleep, Entertainment. No starter activities are seeded.
3. The seeded categories are ordinary records; the user can rename, change their icons, or delete any of them later.
4. With an empty catalog, the Track screen shows the idle timer and supporting copy; activating Activity search shows the empty-catalog guidance prompting the user to enter a name in the native search field. There is no separate creation alert.

## 2. Start a timer from a suggestion

1. On the Track screen, the user sees their 3–5 most recently used Activities as tappable suggestions with Activity names and recency only, ranked on-device from the local catalog by `last_used_at` — no server round-trip, works offline. Category icons and names are not shown during capture.
2. The user taps a suggestion; the Activity is prepared (ready state) and linked to the upcoming entry.
3. The user taps **Start**; the timer runs and the entry is recorded against the selected activity (and its category tags).

## 3. Start a timer with a brand-new name (auto-create)

1. The user activates Activity search on Track and enters a name that does not match any existing activity (case-insensitive, whitespace-trimmed).
2. The search content offers **Create** for the unmatched name; the user confirms quick creation.
3. The app auto-creates a new activity with that name and no categories, prepares it (ready state), and dismisses search. The timer starts only after the user taps **Start**.
4. The new activity now appears in suggestions on future sessions.
5. If the entered name matches an existing activity (case-insensitive, whitespace-trimmed), the existing activity is reused — no duplicate is created. Creation rechecks identity at confirmation time through the atomic local create-or-resolve operation, so a concurrent duplicate resolves to the existing winning Activity.
6. If a non-expired pending-deletion Activity matches the name, the search content offers explicit **Restore** instead of creation; confirming restores the original Activity (same id, no sync) and prepares it.

## 4. Quick-add an activity from the timer

1. The user activates Activity search on Track and enters an unmatched valid name.
2. The user taps the configure target on the create row; the shared Activity Editor opens with the name prefilled.
3. The user optionally adds notes and category tags, and saves.
4. The editor and search close; the new activity is prepared on Track (ready state) without starting timing.
5. If the user cancels the editor, no Activity is created and the active search returns with the query preserved.
6. If saving collides with an existing normalized name (or a pending-deletion identity), the app offers an explicit choice: **Use Existing** (prepares the existing Activity; the draft notes and Categories are never applied) or **Keep Editing** (reopens the editor with the draft intact).

## 5. Manage activities and categories

1. The user opens the **Manage Activities** screen.
2. The user sees all Activities with their category metadata, ordered by most-recently-used, and can edit or delete them. A separate **Manage Categories** screen owns category create/edit/delete. No manual reorder is offered at MVP.
3. Editing an activity updates its name/notes/categories; existing past entries reflect the current category-derived representation at query time (entries store an `activity_id`, not a snapshot, while the activity exists).

## 6. Delete an activity that has history

1. From Manage Activities, the user chooses to delete an activity that has past entries.
2. The app shows a destructive confirmation stating the scope choice: **delete the entire activity (and all N entries)**, or **delete only the current entry**.
3. The user confirms. A transient **Undo** affordance appears for 30 seconds with an **Undo** button.
4. If the user taps **Undo** (or shakes the device before the next undoable action / relaunch), the deletion is restored from the client-side undo buffer and nothing is synced.
5. If the 30-second window passes without undo, the deletion is committed to the local store and synced to the backend (hard delete; no long-lived trash).

## 7. Work offline

1. With no connectivity, the user creates, edits, and deletes activities/categories and starts timers.
2. All changes are applied locally and queued.
3. When connectivity returns, the queue syncs to the backend; conflicts resolve by last-write-wins on `updated_at`.
