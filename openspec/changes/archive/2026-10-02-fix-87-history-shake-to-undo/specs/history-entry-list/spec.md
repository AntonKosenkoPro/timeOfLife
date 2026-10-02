## ADDED Requirements

### Requirement: History offers entry shake-to-undo through the system Undo confirmation

The History destination SHALL offer restore of a confirmed entry deletion through the DEFAULT system Undo confirmation only: shaking the device surfaces the system Undo prompt, and confirming restores exactly one entry — the most recent entry-owned buffered deletion. The registration SHALL be cleared-then-single (one shake+confirm restores at most one deletion) and SHALL cover entry-owned snapshots only: when the newest buffer row belongs to another surface (e.g. a category deletion), History SHALL offer nothing. While the row's `DELETE` push is in flight, undo SHALL be refused with the existing persistence error. No UndoToast SHALL be shown. Confirming an entry delete in the entry form SHALL still dismiss the form; the entry disappears from History via the existing invalidate/reload chain until restored.

#### Scenario: Shake on History after entry delete restores the entry

- **WHEN** the user confirms an entry deletion, returns to History, shakes the device, and confirms the system Undo prompt
- **THEN** the entry is restored with its text, values, and ordered categories back into its day group, and nothing is synced

#### Scenario: Category-newest buffer offers nothing on History

- **WHEN** the newest buffered deletion is category-owned and the user shakes on History
- **THEN** no Undo action is offered and nothing is restored

#### Scenario: Entry-newest buffer offers nothing on Manage Categories

- **WHEN** the newest buffered deletion is entry-owned and the user shakes on Manage Categories
- **THEN** no category Undo action is offered and nothing is restored

#### Scenario: In-flight push refuses History undo

- **WHEN** the user shakes on History and confirms while the buffered entry deletion's `DELETE` push is in flight
- **THEN** the undo is refused with the existing persistence error and the list is unchanged

#### Scenario: No toast on History undo path

- **WHEN** the user confirms an entry deletion
- **THEN** no UndoToast is shown on the entry form or on History; restore is offered only through the system Undo confirmation
