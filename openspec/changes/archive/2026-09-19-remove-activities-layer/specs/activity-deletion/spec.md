## REMOVED Requirements

### Requirement: Activity editor offers Delete with scope confirmation
**Reason**: Cascade activity deletion no longer exists; per-entry delete remains under entry-editor.
**Migration**: Delete `ActivityEditorView` delete path, `deleteActivityUndoable`, `ActivityDeletionSnapshot`, and scope-confirmation copy.

### Requirement: Activity delete is blocked while its timer runs
**Reason**: No activity exists to block on; the running draft references no deletable parent.
**Migration**: Stop always saves; no blocked outcome remains.

### Requirement: Activity deletion is undoable through the system Undo confirmation
**Reason**: Activity snapshots no longer exist; undo covers entries and categories only.
**Migration**: Entry/category undo grammar unchanged (entry-editor, category-management).

### Requirement: Presenters settle after activity deletion
**Reason**: No detail sheet or Track activity selection remains to settle.
**Migration**: History reload covers entry deletes; Track draft clears on Stop.

### Requirement: Activity deletion is localized and accessible
**Reason**: The surface is deleted.
**Migration**: Remove its strings from both `Localizable.strings` + `L10n`.
