## REMOVED Requirements

### Requirement: Activity detail sheet presentation
**Reason**: No activity entity exists; History rows open the entry form directly.
**Migration**: Delete `ActivityDetailView`, its view model, and the History-to-detail sheet route. Tap presents the unified entry form (entry-editor) as a full-screen cover.

### Requirement: Sheet header shows each activity field exactly once
**Reason**: Activity identity header has no subject.
**Migration**: Entry text, categories, and notes live on the entry form itself.

### Requirement: Entry list is visually separated and day-grouped
**Reason**: Per-activity entry lists have no subject.
**Migration**: History remains the only day-grouped entry list.

### Requirement: Entry rows show only entry data
**Reason**: Subsumed by the entry form; no intermediate row surface remains.
**Migration**: No replacement.

### Requirement: Entries section header shows the all-time total
**Reason**: Per-activity totals have no subject.
**Migration**: Insights activity lens (exact-text grouping) is the aggregation surface.

### Requirement: Sheet routes to the activity editor
**Reason**: The activity editor is deleted with the catalog.
**Migration**: Category creation stays in Manage Categories; entry tags edit inline.

### Requirement: Sheet is unavailable for a deleted activity
**Reason**: Cascade deletion no longer exists.
**Migration**: No dismissal path needed.

### Requirement: Sheet offers Log time for its activity
**Reason**: No activity context exists to prefill from.
**Migration**: History `[+]` opens the Log Time sheet blank.

### Requirement: Sheet refreshes after the entry form dismisses
**Reason**: No sheet remains to refresh.
**Migration**: History invalidate/reload covers edits and deletes.
